#!/usr/bin/env python3
"""Poll Slack proxy, filter new messages since last watermark, save filtered JSON.

Outputs the filtered file path to stdout if new messages found, empty if not.
Exit code 0 regardless (no new messages is not an error).
"""
import json, os, sys
from lib import load_config, proxy_get, log, ensure_dirs, today, now_ts

def main():
    cfg = load_config()
    ensure_dirs(cfg)
    data_dir = cfg["data_dir"]
    state_file = os.path.join(data_dir, "state", "last_poll.json")
    ts = now_ts()
    raw_dir = os.path.join(data_dir, "raw", today())
    filtered_path = os.path.join(raw_dir, f"filtered_{ts}.json")
    raw_path = os.path.join(raw_dir, f"poll_{ts}.json")

    # Load state
    try:
        with open(state_file) as f:
            state = json.load(f)
    except Exception:
        state = {"last_mention_ts": "0", "last_thread_ts": "0", "channels": {}}
        log("Initialized state file", "poll")

    # Fetch from proxy
    log("Polling Slack...", "poll")

    mentions_resp = proxy_get("/api/mentions/all?count=30&includeThreads=true", cfg)
    mentions = mentions_resp.get("data", {}).get("mentions", []) if mentions_resp.get("success") else []

    threads_resp = proxy_get("/api/activity/threads-im-in?count=20", cfg)
    threads = threads_resp.get("data", {}).get("threads", []) if threads_resp.get("success") else []

    my_threads_resp = proxy_get("/api/activity/my-threads?count=20&includeReplies=true", cfg)
    my_threads = my_threads_resp.get("data", {}).get("threads", []) if my_threads_resp.get("success") else []

    # Merge my-threads, dedup
    seen = {(t.get("thread_ts", ""), t.get("channel_id", "")) for t in threads}
    for mt in my_threads:
        key = (mt.get("thread_ts", ""), mt.get("channel_id", ""))
        if key not in seen:
            threads.append(mt)
            seen.add(key)

    # Fetch channel messages
    channel_messages = {}
    for ch_spec in cfg["channels"].split(","):
        parts = ch_spec.strip().split(":")
        if len(parts) < 2:
            continue
        ch_id, ch_name = parts[0], parts[1]
        tier = parts[2] if len(parts) > 2 else "org"
        count = 8 if tier == "team" else 5
        resp = proxy_get(f"/api/channels/{ch_id}/recent-messages?count={count}&includeThreads=true", cfg)
        if resp.get("success"):
            msgs = resp.get("data", {}).get("messages", [])
            if msgs:
                channel_messages[ch_name] = {"channel_id": ch_id, "tier": tier, "messages": msgs}

    poll_data = {"poll_time": ts, "mentions": mentions, "threads": threads, "channels": channel_messages}

    # Filter new messages
    def mention_ts(m):
        return m.get("message_ts", m.get("ts", "0"))

    def thread_latest_ts(t):
        replies = t.get("replies", []) or t.get("complete_thread", {}).get("replies", [])
        if replies:
            return max(r.get("ts", "0") for r in replies)
        parent = t.get("parent_message", {}) or t.get("complete_thread", {}).get("parent", {}) or {}
        return parent.get("ts", t.get("thread_ts", "0"))

    new_mentions = [m for m in mentions if mention_ts(m) > state.get("last_mention_ts", "0")]
    new_threads = [t for t in threads if thread_latest_ts(t) > state.get("last_thread_ts", "0")]

    new_channels = {}
    new_ch_count = 0
    for ch_name, ch_data in channel_messages.items():
        last_ts = state.get("channels", {}).get(ch_name, "0")
        new_msgs = [m for m in ch_data["messages"] if m.get("ts", "0") > last_ts]
        if new_msgs:
            new_channels[ch_name] = {"channel_id": ch_data["channel_id"], "tier": ch_data["tier"], "messages": new_msgs}
            new_ch_count += len(new_msgs)

    total = len(new_mentions) + len(new_threads) + new_ch_count

    if total == 0:
        log(f"No new messages.", "poll")
        return

    # Save filtered
    filtered = {"poll_time": ts, "mentions": new_mentions, "threads": new_threads, "channels": new_channels}
    with open(filtered_path, "w") as f:
        json.dump(filtered, f)

    # Save raw for debugging
    with open(raw_path, "w") as f:
        json.dump(poll_data, f)

    # Update watermarks from filtered data only
    if new_mentions:
        latest = max(mention_ts(m) for m in new_mentions)
        if latest > state.get("last_mention_ts", "0"):
            state["last_mention_ts"] = latest
    if new_threads:
        latest = max(thread_latest_ts(t) for t in new_threads)
        if latest > state.get("last_thread_ts", "0"):
            state["last_thread_ts"] = latest
    if "channels" not in state:
        state["channels"] = {}
    for ch_name, ch_data in channel_messages.items():
        msgs = ch_data.get("messages", [])
        if msgs:
            latest = max(m.get("ts", "0") for m in msgs)
            if latest > state.get("channels", {}).get(ch_name, "0"):
                state["channels"][ch_name] = latest
    with open(state_file, "w") as f:
        json.dump(state, f, indent=2)

    log(f"Found {total} new items (mentions={len(new_mentions)}, threads={len(new_threads)}, channels={new_ch_count})", "poll")
    # Output filtered path for the bash caller
    print(filtered_path)

if __name__ == "__main__":
    main()

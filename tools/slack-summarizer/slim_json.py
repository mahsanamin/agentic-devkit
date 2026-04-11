#!/usr/bin/env python3
"""Pre-filter JSON for Claude: truncate text, limit replies, add permalinks.

Usage: python3 slim_json.py <input.json> <output.json>
"""
import json, sys, os
from lib import load_config, make_permalink

def slim_message(msg, channel_id="", cfg=None):
    return {
        "ts": msg.get("ts", ""),
        "user_id": msg.get("user_id", msg.get("user", "")),
        "user_name": msg.get("user_name", ""),
        "text": (msg.get("text", "") or "")[:1200],
        "permalink": msg.get("permalink", "") or make_permalink(channel_id, msg.get("ts", ""), cfg),
    }

def main():
    if len(sys.argv) < 3:
        print("Usage: slim_json.py <input.json> <output.json>", file=sys.stderr)
        sys.exit(1)

    cfg = load_config()
    with open(sys.argv[1]) as f:
        data = json.load(f)

    # Mentions
    slim_mentions = []
    for m in data.get("mentions", []):
        ch_id = m.get("channel_id", "")
        sm = slim_message(m, ch_id, cfg)
        sm["channel_id"] = ch_id
        sm["channel_name"] = m.get("channel_name", "")
        if m.get("is_thread_reply") or m.get("thread_ts"):
            sm["thread_ts"] = m.get("thread_ts", "")
        slim_mentions.append(sm)

    # Threads
    slim_threads = []
    for t in data.get("threads", []):
        ch_id = t.get("channel_id", "")
        thread_ts = t.get("thread_ts", "")
        parent = t.get("parent_message", {}) or t.get("complete_thread", {}).get("parent", {}) or {}
        replies = t.get("replies", []) or t.get("complete_thread", {}).get("replies", [])
        kept = replies[:2] + replies[-6:] if len(replies) > 10 else replies
        slim_threads.append({
            "channel_name": t.get("channel_name", ""),
            "channel_id": ch_id,
            "thread_ts": thread_ts,
            "topic": (parent.get("text", "") or t.get("parent_text", "") or "")[:600],
            "parent_user_id": parent.get("user_id", parent.get("user", "")),
            "parent_user_name": parent.get("user_name", ""),
            "reply_count": t.get("thread_stats", {}).get("reply_count", len(replies)),
            "permalink": make_permalink(ch_id, thread_ts, cfg),
            "replies": [slim_message(r, ch_id, cfg) for r in kept],
        })

    # Channels
    slim_channels = {}
    for ch_name, ch_data in data.get("channels", {}).items():
        ch_id = ch_data.get("channel_id", "")
        slim_channels[ch_name] = {
            "channel_id": ch_id,
            "tier": ch_data.get("tier", "org"),
            "messages": [slim_message(m, ch_id, cfg) for m in ch_data.get("messages", [])],
        }

    # Include user map so Claude can resolve @mentions by name
    from lib import load_user_map, extract_users, save_user_map
    user_map = load_user_map(cfg)
    user_map.update(extract_users(data))
    save_user_map(user_map, cfg)

    result = {"poll_time": data.get("poll_time", ""), "user_map": user_map, "mentions": slim_mentions, "threads": slim_threads, "channels": slim_channels}
    with open(sys.argv[2], "w") as f:
        json.dump(result, f, indent=1)

    orig_kb = os.path.getsize(sys.argv[1]) / 1024
    slim_kb = os.path.getsize(sys.argv[2]) / 1024
    print(f"Slimmed: {orig_kb:.0f}KB -> {slim_kb:.0f}KB", file=sys.stderr)

if __name__ == "__main__":
    main()

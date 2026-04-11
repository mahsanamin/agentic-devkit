#!/usr/bin/env python3
"""Scan all historical filtered data, fetch fresh thread state, prune stale.

Usage: python3 enrich_threads.py <output.json>
Produces enriched JSON with threads, mentions, channel_messages, user_map, stats.
"""
import json, glob, os, sys, time
from lib import load_config, proxy_get, make_permalink, log, extract_users, load_user_map, save_user_map

def main():
    if len(sys.argv) < 2:
        print("Usage: enrich_threads.py <output.json>", file=sys.stderr)
        sys.exit(1)

    cfg = load_config()
    out_file = sys.argv[1]
    stale_cutoff = time.time() - (cfg["stale_days"] * 86400)

    # Scan all filtered files
    files = sorted(glob.glob(os.path.join(cfg["data_dir"], "raw", "*", "filtered_*.json")))
    log(f"Scanning {len(files)} filtered files...", "consolidate")

    hist_threads, mentions, channel_msgs = {}, {}, {}
    user_map = load_user_map(cfg)

    for fpath in files:
        try:
            with open(fpath) as f:
                d = json.load(f)
        except Exception:
            continue
        user_map.update(extract_users(d))

        for t in d.get("threads", []):
            key = (t.get("thread_ts", ""), t.get("channel_id", ""))
            if not key[0]:
                continue
            replies = t.get("replies", t.get("complete_thread", {}).get("replies", []))
            count = t.get("thread_stats", {}).get("reply_count", len(replies))
            existing = hist_threads.get(key)
            if not existing or count > existing.get("_reply_count", 0):
                t["_reply_count"] = count
                t["_replies"] = replies
                hist_threads[key] = t

        for m in d.get("mentions", []):
            ts = m.get("ts", m.get("message_ts", ""))
            if ts and ts not in mentions:
                mentions[ts] = m

        for ch_name, ch_data in d.get("channels", {}).items():
            ch_id = ch_data.get("channel_id", "")
            tier = ch_data.get("tier", "org")
            for msg in ch_data.get("messages", []):
                ts = msg.get("ts", "")
                mkey = (ch_name, ts)
                if ts and mkey not in channel_msgs:
                    msg["_channel_name"] = ch_name
                    msg["_channel_id"] = ch_id
                    msg["_tier"] = tier
                    channel_msgs[mkey] = msg

    # Fetch fresh thread state
    log(f"Fetching latest state for {len(hist_threads)} threads...", "consolidate")
    merged, stale_count, fetch_ok, fetch_fail = [], 0, 0, 0

    for (thread_ts, channel_id), hist in hist_threads.items():
        resp = proxy_get(f"/api/channels/{channel_id}/thread/{thread_ts}", cfg)

        if resp.get("success"):
            fetch_ok += 1
            data = resp.get("data", {})
            parent = data.get("parent_message", {}) or {}
            replies = data.get("replies", [])
        else:
            fetch_fail += 1
            parent = hist.get("parent_message", {}) or {}
            replies = hist.get("_replies", [])

        latest_ts = thread_ts
        if replies:
            latest_ts = max(r.get("ts", "0") for r in replies)
        latest_float = float(latest_ts) if latest_ts else 0

        if latest_float < stale_cutoff:
            stale_count += 1
            continue

        kept = replies[:2] + replies[-8:] if len(replies) > 10 else replies
        last_reply_by = replies[-1].get("user_name", "") if replies else ""
        last_reply_text = (replies[-1].get("text", "") or "")[:200] if replies else ""

        merged.append({
            "thread_ts": thread_ts, "channel_id": channel_id,
            "channel_name": hist.get("channel_name", ""),
            "topic": (parent.get("text", "") or hist.get("topic", "") or "")[:500],
            "parent_user_name": parent.get("user_name", hist.get("parent_user_name", "")),
            "parent_user_id": parent.get("user_id", parent.get("user", hist.get("parent_user_id", ""))),
            "reply_count": data.get("reply_count", len(replies)) if resp.get("success") else hist.get("_reply_count", len(replies)),
            "permalink": make_permalink(channel_id, thread_ts, cfg),
            "last_activity": latest_ts,
            "last_activity_date": time.strftime("%Y-%m-%d %H:%M", time.localtime(latest_float)) if latest_float > 0 else "?",
            "last_reply_by": last_reply_by, "last_reply_text": last_reply_text,
            "latest_replies": [{"user_name": r.get("user_name", ""), "user_id": r.get("user_id", r.get("user", "")),
                                "text": (r.get("text", "") or "")[:500], "ts": r.get("ts", "")} for r in kept],
            "source": "fresh" if resp.get("success") else "historical",
        })

    merged.sort(key=lambda x: float(x.get("last_activity", "0")), reverse=True)
    log(f"Fetched: {fetch_ok} OK, {fetch_fail} historical, {stale_count} stale pruned", "consolidate")

    # Mentions
    mention_list = sorted(mentions.values(), key=lambda x: float(x.get("ts", x.get("message_ts", "0"))), reverse=True)
    for m in mention_list:
        if not m.get("permalink"):
            m["permalink"] = make_permalink(m.get("channel_id", ""), m.get("ts", m.get("message_ts", "")), cfg)

    # Channel messages
    active_msgs = sorted(
        [m for m in channel_msgs.values() if float(m.get("ts", "0")) >= stale_cutoff],
        key=lambda x: float(x.get("ts", "0")), reverse=True
    )

    save_user_map(user_map, cfg)

    result = {
        "threads": merged, "mentions": mention_list, "channel_messages": active_msgs, "user_map": user_map,
        "stats": {
            "active_threads": len(merged), "stale_threads": stale_count,
            "fresh_threads": sum(1 for t in merged if t.get("source") == "fresh"),
            "mentions": len(mention_list), "active_channel_msgs": len(active_msgs),
        }
    }
    with open(out_file, "w") as f:
        json.dump(result, f)

    s = result["stats"]
    log(f"Result: {s['active_threads']} threads ({s['fresh_threads']} fresh), {s['stale_threads']} pruned", "consolidate")
    print(out_file)

if __name__ == "__main__":
    main()

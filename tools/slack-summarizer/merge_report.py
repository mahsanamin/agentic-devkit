#!/usr/bin/env python3
"""Merge 24h of filtered_*.json into one combined JSON for daily report.

Usage: python3 merge_report.py <output.json>
Looks for filtered files in $DATA_DIR/raw/{today,yesterday}/
"""
import json, os, sys, glob
from datetime import datetime, timedelta
from lib import load_config, log

def main():
    if len(sys.argv) < 2:
        print("Usage: merge_report.py <output.json>", file=sys.stderr)
        sys.exit(1)

    cfg = load_config()
    out_file = sys.argv[1]
    today = datetime.now().strftime("%Y-%m-%d")
    yesterday = (datetime.now() - timedelta(days=1)).strftime("%Y-%m-%d")

    files = []
    for day in [yesterday, today]:
        pattern = os.path.join(cfg["data_dir"], "raw", day, "filtered_*.json")
        files.extend(sorted(glob.glob(pattern)))

    if not files:
        log(f"No filtered data for {yesterday} or {today}", "report")
        sys.exit(0)

    log(f"Merging {len(files)} filtered file(s)", "report")

    all_mentions, all_threads, all_channels = [], [], {}
    seen_mention_ts, seen_thread_keys = set(), set()

    for fpath in files:
        try:
            with open(fpath) as f:
                data = json.load(f)
        except Exception as e:
            log(f"Skipping {fpath}: {e}", "report")
            continue

        for m in data.get("mentions", []):
            ts = m.get("ts", m.get("message_ts", ""))
            if ts and ts not in seen_mention_ts:
                seen_mention_ts.add(ts)
                all_mentions.append(m)

        for t in data.get("threads", []):
            key = (t.get("thread_ts", ""), t.get("channel_id", ""))
            if key[0] and key not in seen_thread_keys:
                seen_thread_keys.add(key)
                all_threads.append(t)
            elif key[0]:
                new_count = t.get("thread_stats", {}).get("reply_count", len(t.get("replies", [])))
                for i, ex in enumerate(all_threads):
                    if (ex.get("thread_ts", ""), ex.get("channel_id", "")) == key:
                        ex_count = ex.get("thread_stats", {}).get("reply_count", len(ex.get("replies", [])))
                        if new_count > ex_count:
                            all_threads[i] = t
                        break

        for ch_name, ch_data in data.get("channels", {}).items():
            if ch_name not in all_channels:
                all_channels[ch_name] = {
                    "channel_id": ch_data.get("channel_id", ""),
                    "tier": ch_data.get("tier", "org"),
                    "messages": [],
                }
                seen_ts = set()
            else:
                seen_ts = {m.get("ts", "") for m in all_channels[ch_name]["messages"]}
            for msg in ch_data.get("messages", []):
                ts = msg.get("ts", "")
                if ts and ts not in seen_ts:
                    seen_ts.add(ts)
                    all_channels[ch_name]["messages"].append(msg)

    result = {
        "source_files": len(files),
        "mentions": all_mentions,
        "threads": all_threads,
        "channels": all_channels,
    }
    with open(out_file, "w") as f:
        json.dump(result, f)

    total = len(all_mentions) + len(all_threads) + sum(len(c["messages"]) for c in all_channels.values())
    log(f"Merged: {len(all_mentions)} mentions, {len(all_threads)} threads, {total} total", "report")
    print(out_file)

if __name__ == "__main__":
    main()

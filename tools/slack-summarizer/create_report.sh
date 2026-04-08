#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# create_report.sh — Aggregate last 24h filtered data into a daily report
#
# Finds all filtered_*.json files from today and yesterday, merges them into
# one combined JSON, and passes it to claude_summarizer.sh with report-specific
# overrides (report prompt, fixed output filename, optional skip-send).
#
# Usage:
#   ./create_report.sh                        # generate + send to DM
#   ./create_report.sh --no-send              # generate only, skip Slack DM
#   ./create_report.sh --output ~/report.md   # save to custom path
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
[[ -f "$SCRIPT_DIR/config.env" ]] && source "$SCRIPT_DIR/config.env"
DATA_DIR="${DATA_DIR:-$SCRIPT_DIR}"

TODAY=$(date +%Y-%m-%d)
YESTERDAY=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d "yesterday" +%Y-%m-%d)
LOG_PREFIX="[$(date '+%Y-%m-%d %H:%M:%S')] [report]"
COMBINED_FILE="/tmp/slack_report_combined_$$.json"
SUMMARIZER="$SCRIPT_DIR/claude_summarizer.sh"

SKIP_SEND=0
OUTPUT_PATH=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-send) SKIP_SEND=1; shift ;;
        --output) OUTPUT_PATH="$2"; shift 2 ;;
        *) shift ;;
    esac
done

log() {
    echo "$LOG_PREFIX $*"
}

cleanup() {
    rm -f "$COMBINED_FILE"
}
trap cleanup EXIT

# ── Find filtered_*.json files from last 24 hours ────────────────────────────
FILTERED_FILES=()
for dir in "$DATA_DIR/raw/$YESTERDAY" "$DATA_DIR/raw/$TODAY"; do
    if [[ -d "$dir" ]]; then
        while IFS= read -r -d '' f; do
            FILTERED_FILES+=("$f")
        done < <(find "$dir" -name 'filtered_*.json' -print0 2>/dev/null)
    fi
done

if [[ ${#FILTERED_FILES[@]} -eq 0 ]]; then
    log "No filtered data found for $YESTERDAY or $TODAY. Nothing to report."
    exit 0
fi

log "Found ${#FILTERED_FILES[@]} filtered file(s) to merge"

# ── Merge all filtered files into one combined JSON ──────────────────────────
python3 - "$COMBINED_FILE" "${FILTERED_FILES[@]}" << 'MERGEEOF'
import json, sys

out_file = sys.argv[1]
input_files = sys.argv[2:]

all_mentions = []
all_threads = []
all_channels = {}

seen_mention_ts = set()
seen_thread_keys = set()  # (thread_ts, channel_id)

for fpath in input_files:
    try:
        with open(fpath) as f:
            data = json.load(f)
    except Exception as e:
        print(f"WARNING: Skipping {fpath}: {e}", file=sys.stderr)
        continue

    # Mentions: deduplicate by ts (or message_ts)
    for m in data.get("mentions", []):
        ts = m.get("ts", m.get("message_ts", ""))
        if ts and ts not in seen_mention_ts:
            seen_mention_ts.add(ts)
            all_mentions.append(m)

    # Threads: deduplicate by (thread_ts, channel_id), keep version with more replies
    for t in data.get("threads", []):
        key = (t.get("thread_ts", ""), t.get("channel_id", ""))
        if key[0] and key not in seen_thread_keys:
            seen_thread_keys.add(key)
            all_threads.append(t)
        elif key[0] and key in seen_thread_keys:
            # Replace if this version has more replies
            new_count = t.get("thread_stats", {}).get("reply_count", len(t.get("replies", [])))
            for i, existing in enumerate(all_threads):
                ex_key = (existing.get("thread_ts", ""), existing.get("channel_id", ""))
                if ex_key == key:
                    ex_count = existing.get("thread_stats", {}).get("reply_count", len(existing.get("replies", [])))
                    if new_count > ex_count:
                        all_threads[i] = t
                    break

    # Channels: merge by channel name, deduplicate messages by ts
    for ch_name, ch_data in data.get("channels", {}).items():
        if ch_name not in all_channels:
            all_channels[ch_name] = {
                "channel_id": ch_data.get("channel_id", ""),
                "tier": ch_data.get("tier", "org"),
                "messages": [],
            }
            seen_msg_ts = set()
        else:
            seen_msg_ts = {m.get("ts", "") for m in all_channels[ch_name]["messages"]}

        for msg in ch_data.get("messages", []):
            ts = msg.get("ts", "")
            if ts and ts not in seen_msg_ts:
                seen_msg_ts.add(ts)
                all_channels[ch_name]["messages"].append(msg)

result = {
    "report_date": sys.argv[1].split("/")[-1] if "/" in sys.argv[1] else "",
    "source_files": len(input_files),
    "mentions": all_mentions,
    "threads": all_threads,
    "channels": all_channels,
}

with open(out_file, "w") as f:
    json.dump(result, f)

total = len(all_mentions) + len(all_threads) + sum(len(c["messages"]) for c in all_channels.values())
print(f"Merged {len(input_files)} files: {len(all_mentions)} mentions, {len(all_threads)} threads, {sum(len(c['messages']) for c in all_channels.values())} channel msgs ({total} total)")
MERGEEOF

if [[ ! -s "$COMBINED_FILE" ]]; then
    log "ERROR: Failed to merge filtered files"
    exit 1
fi

# ── Run claude_summarizer.sh with report-specific overrides ──────────────────
if [[ -n "$OUTPUT_PATH" ]]; then
    # Ensure .md extension
    [[ "$OUTPUT_PATH" != *.md ]] && OUTPUT_PATH="${OUTPUT_PATH}.md"
    # Create parent directory if needed
    mkdir -p "$(dirname "$OUTPUT_PATH")"
    export SUMMARY_OUTPUT_FILE="$OUTPUT_PATH"
else
    REPORT_DIR="$DATA_DIR/summaries/$TODAY"
    mkdir -p "$REPORT_DIR"
    export SUMMARY_OUTPUT_FILE="$REPORT_DIR/daily_report.md"
fi

export SYSTEM_PROMPT_OVERRIDE="$SCRIPT_DIR/report_prompt.txt"
export SKIP_SLACK_SEND="$SKIP_SEND"

log "Generating daily report..."
"$SUMMARIZER" "$COMBINED_FILE"

log "Daily report saved to $SUMMARY_OUTPUT_FILE"
log "Done."

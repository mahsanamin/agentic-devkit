#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# slack_poller.sh — Lightweight Slack poller (no Claude tokens)
#
# Runs on a schedule via cron. Fetches mentions, threads, and key channel
# messages from the local Slack proxy. Only triggers Claude when new
# messages are detected since the last poll.
#
# API returns compact format by default (no blocks, attachments, etc.)
# Threads are flat: parent_message + replies[] (no complete_thread wrapper)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Config ───────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
[[ -f "$SCRIPT_DIR/config.env" ]] && source "$SCRIPT_DIR/config.env"
DATA_DIR="${DATA_DIR:-$SCRIPT_DIR}"

API_BASE="${SLACK_PROXY_URL:?Error: SLACK_PROXY_URL not set in config.env}"
API_KEY="${SLACK_PROXY_API_KEY:?Error: SLACK_PROXY_API_KEY not set in config.env}"
STATE_FILE="$DATA_DIR/state/last_poll.json"
TODAY=$(date +%Y-%m-%d)
NOW_TS=$(date +%H%M%S)
RAW_DIR="$DATA_DIR/raw/$TODAY"
SUMMARIZER="$SCRIPT_DIR/claude_summarizer.sh"
LOG_PREFIX="[$(date '+%Y-%m-%d %H:%M:%S')]"
TMP_POLL="/tmp/slack_poll_$$.json"

# ── Channel Config ───────────────────────────────────────────────────────────
# CHANNELS array should be defined in config.env
# Format: "CHANNEL_ID:friendly_name:TIER"
if [[ ${#CHANNELS[@]} -eq 0 ]]; then
    echo "$LOG_PREFIX WARNING: No CHANNELS configured in config.env"
fi

# ── Helpers ──────────────────────────────────────────────────────────────────
log() {
    echo "$LOG_PREFIX $*"
}

cleanup() {
    rm -f "$TMP_POLL"
}
trap cleanup EXIT

# ── Ensure dirs ──────────────────────────────────────────────────────────────
mkdir -p "$RAW_DIR" "$DATA_DIR/state" "$DATA_DIR/summaries/$TODAY"

# ── Init state if missing ────────────────────────────────────────────────────
if [[ ! -f "$STATE_FILE" ]]; then
    echo '{"last_mention_ts": "0", "last_thread_ts": "0", "channels": {}}' > "$STATE_FILE"
    log "Initialized state file"
fi

# ── Fetch data ───────────────────────────────────────────────────────────────
log "Polling Slack..."

# Build comma-separated channel list from bash array
CHANNELS_CSV=""
for ch in "${CHANNELS[@]}"; do
    CHANNELS_CSV="${CHANNELS_CSV:+$CHANNELS_CSV,}$ch"
done
export CHANNELS_LIST="$CHANNELS_CSV"
export SLACK_API_BASE="$API_BASE"
export SLACK_API_KEY="$API_KEY"

python3 - "$TMP_POLL" << 'PYEOF'
import json, ssl, urllib.request, sys, os

API_BASE = os.environ["SLACK_API_BASE"]
API_KEY = os.environ["SLACK_API_KEY"]
CHANNELS_RAW = os.environ.get("CHANNELS_LIST", "")
out_file = sys.argv[1]

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

def api_get(endpoint):
    req = urllib.request.Request(
        f"{API_BASE}{endpoint}",
        headers={"X-API-Key": API_KEY}
    )
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=15) as resp:
            return json.loads(resp.read())
    except Exception as e:
        return {"success": False, "error": str(e)}

mentions_resp = api_get("/api/mentions/all?count=30&includeThreads=true")
mentions = mentions_resp.get("data", {}).get("mentions", []) if mentions_resp.get("success") else []

threads_resp = api_get("/api/activity/threads-im-in?count=20")
threads = threads_resp.get("data", {}).get("threads", []) if threads_resp.get("success") else []

# Threads you started or replied to (catches your own activity)
my_threads_resp = api_get("/api/activity/my-threads?count=20&includeReplies=true")
my_threads = my_threads_resp.get("data", {}).get("threads", []) if my_threads_resp.get("success") else []

# Merge my-threads into threads, dedup by thread_ts+channel
seen_threads = {(t.get("thread_ts", ""), t.get("channel_id", "")) for t in threads}
for mt in my_threads:
    key = (mt.get("thread_ts", ""), mt.get("channel_id", ""))
    if key not in seen_threads:
        threads.append(mt)
        seen_threads.add(key)

channel_messages = {}
for ch_spec in CHANNELS_RAW.split(","):
    parts = ch_spec.split(":")
    if len(parts) < 2:
        continue
    ch_id = parts[0]
    ch_name = parts[1]
    tier = parts[2] if len(parts) > 2 else "org"
    # Team channels get more messages, org channels get fewer
    count = 8 if tier == "team" else 5
    resp = api_get(f"/api/channels/{ch_id}/recent-messages?count={count}&includeThreads=true")
    if resp.get("success"):
        msgs = resp.get("data", {}).get("messages", [])
        if msgs:
            channel_messages[ch_name] = {
                "channel_id": ch_id,
                "tier": tier,
                "messages": msgs,
            }

result = {
    "poll_time": os.environ.get("NOW_TS", ""),
    "mentions": mentions,
    "threads": threads,
    "channels": channel_messages
}

with open(out_file, "w") as f:
    json.dump(result, f)
PYEOF

if [[ ! -s "$TMP_POLL" ]]; then
    log "ERROR: Failed to fetch data from Slack proxy"
    exit 1
fi

# ── Compare + filter + update state (single pass) ────────────────────────────
RAW_FILE="$RAW_DIR/poll_${NOW_TS}.json"
FILTERED_FILE="$RAW_DIR/filtered_${NOW_TS}.json"

HAS_NEW=$(python3 - "$TMP_POLL" "$STATE_FILE" "$FILTERED_FILE" << 'PROCEOF'
import json, sys

poll_file, state_file, out_file = sys.argv[1], sys.argv[2], sys.argv[3]

with open(poll_file, "r") as f:
    poll_data = json.load(f)
try:
    with open(state_file, "r") as f:
        state = json.load(f)
except Exception:
    state = {"last_mention_ts": "0", "last_thread_ts": "0", "channels": {}}

# ── Helpers ──
def mention_ts(m):
    """Get mention timestamp — compact uses ts, verbose had message_ts."""
    return m.get("message_ts", m.get("ts", "0"))

def thread_latest_ts(t):
    """Get latest activity timestamp from a thread.
    Compact format: flat replies[] array.
    Verbose fallback: complete_thread.replies[]."""
    replies = t.get("replies", [])
    if not replies:
        replies = t.get("complete_thread", {}).get("replies", [])
    if replies:
        return max(r.get("ts", "0") for r in replies)
    # No replies — use parent ts or thread_ts
    parent = t.get("parent_message", {}) or t.get("complete_thread", {}).get("parent", {}) or {}
    return parent.get("ts", t.get("thread_ts", "0"))

# ── Count + filter mentions ──
last_mention_ts = state.get("last_mention_ts", "0")
new_mentions = [m for m in poll_data.get("mentions", [])
                if mention_ts(m) > last_mention_ts]

# ── Count + filter threads ──
last_thread_ts = state.get("last_thread_ts", "0")
new_threads = [t for t in poll_data.get("threads", [])
               if thread_latest_ts(t) > last_thread_ts]

# ── Count + filter channels ──
new_channels = {}
new_ch_msg_count = 0
for ch_name, ch_data in poll_data.get("channels", {}).items():
    last_ch_ts = state.get("channels", {}).get(ch_name, "0")
    new_msgs = [msg for msg in ch_data.get("messages", [])
                if msg.get("ts", "0") > last_ch_ts]
    if new_msgs:
        new_channels[ch_name] = {
            "channel_id": ch_data.get("channel_id", ""),
            "tier": ch_data.get("tier", "org"),
            "messages": new_msgs,
        }
        new_ch_msg_count += len(new_msgs)

total = len(new_mentions) + len(new_threads) + new_ch_msg_count

# ── Write filtered output + update state only if there's new data ──
if total > 0:
    filtered = {
        "poll_time": poll_data.get("poll_time", ""),
        "mentions": new_mentions,
        "threads": new_threads,
        "channels": new_channels,
    }
    with open(out_file, "w") as f:
        json.dump(filtered, f)

    # Update state watermarks from FILTERED data only
    if new_mentions:
        latest = max(mention_ts(m) for m in new_mentions)
        if latest > state.get("last_mention_ts", "0"):
            state["last_mention_ts"] = latest

    if new_threads:
        ts_list = [thread_latest_ts(t) for t in new_threads]
        latest = max(ts_list)
        if latest > state.get("last_thread_ts", "0"):
            state["last_thread_ts"] = latest

    if "channels" not in state:
        state["channels"] = {}
    for ch_name, ch_data in poll_data.get("channels", {}).items():
        msgs = ch_data.get("messages", [])
        if msgs:
            latest = max(m.get("ts", "0") for m in msgs)
            if latest > state.get("channels", {}).get(ch_name, "0"):
                state["channels"][ch_name] = latest

    with open(state_file, "w") as f:
        json.dump(state, f, indent=2)

    sys.stderr.write(f"Filtered: {total} new items (mentions={len(new_mentions)}, threads={len(new_threads)}, channels={new_ch_msg_count})\n")

print(total)
PROCEOF
)

log "Found $HAS_NEW new message(s) since last poll"

if [[ "$HAS_NEW" == "0" ]]; then
    log "No new messages. Exiting."
    exit 0
fi

# ── Save full raw poll for debugging ─────────────────────────────────────────
cp "$TMP_POLL" "$RAW_FILE"
log "Saved raw data to $RAW_FILE"

# ── Trigger Claude summarizer with filtered (new-only) data ──────────────────
if [[ -x "$SUMMARIZER" ]]; then
    log "Triggering Claude summarizer..."
    "$SUMMARIZER" "$FILTERED_FILE" &
    log "Summarizer running in background (PID: $!)"
else
    log "WARNING: Summarizer not found or not executable at $SUMMARIZER"
fi

log "Done."

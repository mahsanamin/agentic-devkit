#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# claude_summarizer.sh — Spins up Claude to summarize new Slack data
#
# Called by slack_poller.sh ONLY when new messages are detected.
# 1. Pre-filters JSON (truncate text, limit replies, add permalinks)
# 2. Claude haiku generates text summary (--print mode, no tools)
# 3. Bash sends summary to Slack DM via local proxy API
#
# Expects compact API format: flat parent_message + replies[], user_id field,
# no blocks/attachments, pre-cleaned text.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
[[ -f "$SCRIPT_DIR/config.env" ]] && source "$SCRIPT_DIR/config.env"
DATA_DIR="${DATA_DIR:-$SCRIPT_DIR}"

TODAY=$(date +%Y-%m-%d)
NOW_TS=$(date +%H%M%S)
SUMMARY_DIR="$DATA_DIR/summaries/$TODAY"
DM_CHANNEL="${SLACK_DM_CHANNEL:?Error: SLACK_DM_CHANNEL not set in config.env}"
API_BASE="${SLACK_PROXY_URL:?Error: SLACK_PROXY_URL not set in config.env}"
API_KEY="${SLACK_PROXY_API_KEY:?Error: SLACK_PROXY_API_KEY not set in config.env}"
SLACK_BASE="${SLACK_WORKSPACE_URL:?Error: SLACK_WORKSPACE_URL not set in config.env}/archives"
# Allow callers to override defaults via env vars
SYSTEM_PROMPT_FILE="${SYSTEM_PROMPT_OVERRIDE:-$SCRIPT_DIR/system_prompt.txt}"
SKIP_SEND="${SKIP_SLACK_SEND:-0}"
LOG_PREFIX="[$(date '+%Y-%m-%d %H:%M:%S')] [summarizer]"
SLIM_FILE="/tmp/slack_slim_$$.json"
SEND_PAYLOAD_FILE="/tmp/slack_send_$$.json"

POLL_FILE="${1:-}"

if [[ -z "$POLL_FILE" || ! -f "$POLL_FILE" ]]; then
    echo "$LOG_PREFIX ERROR: No poll file provided or file not found: $POLL_FILE"
    exit 1
fi

mkdir -p "$SUMMARY_DIR"

log() {
    echo "$LOG_PREFIX $*"
}

cleanup() {
    rm -f "$SLIM_FILE" "$SEND_PAYLOAD_FILE" "/tmp/slack_pub_$$.md"
}
trap cleanup EXIT

log "Starting Claude summarizer for: $POLL_FILE"

# ── Step 1: Slim down the JSON ──────────────────────────────────────────────
# API already returns compact data (no blocks, attachments, cleaned text).
# This step: truncates long text, limits thread replies, constructs permalinks.
log "Pre-filtering JSON..."

export SLACK_ARCHIVES_BASE="$SLACK_BASE"

python3 - "$POLL_FILE" "$SLIM_FILE" << 'FILTEREOF'
import json, sys, os

poll_file, out_file = sys.argv[1], sys.argv[2]

with open(poll_file) as f:
    data = json.load(f)

SLACK_BASE = os.environ.get("SLACK_ARCHIVES_BASE", "")

def make_permalink(channel_id, ts):
    """Construct a Slack permalink from channel ID and message timestamp."""
    if channel_id and ts and SLACK_BASE:
        return f"{SLACK_BASE}/{channel_id}/p{ts.replace('.', '')}"
    return ""

def slim_message(msg, channel_id=""):
    """Slim a compact message: truncate text, ensure permalink."""
    return {
        "ts": msg.get("ts", ""),
        "user_id": msg.get("user_id", msg.get("user", "")),
        "user_name": msg.get("user_name", ""),
        "text": (msg.get("text", "") or "")[:1200],
        "permalink": msg.get("permalink", "") or make_permalink(channel_id, msg.get("ts", "")),
    }

# ── Mentions ──
slim_mentions = []
for m in data.get("mentions", []):
    ch_id = m.get("channel_id", "")
    sm = slim_message(m, ch_id)
    sm["channel_id"] = ch_id
    sm["channel_name"] = m.get("channel_name", "")
    # Thread context (if this mention is a thread reply)
    if m.get("is_thread_reply") or m.get("thread_ts"):
        sm["thread_ts"] = m.get("thread_ts", "")
    slim_mentions.append(sm)

# ── Threads (compact: flat parent_message + replies[]) ──
slim_threads = []
for t in data.get("threads", []):
    ch_id = t.get("channel_id", "")
    thread_ts = t.get("thread_ts", "")

    # Parent message — compact format has it directly
    parent = t.get("parent_message", {}) or {}
    # Verbose fallback
    if not parent:
        parent = t.get("complete_thread", {}).get("parent", {}) or {}

    # Replies — compact format has flat array
    replies = t.get("replies", [])
    # Verbose fallback
    if not replies:
        replies = t.get("complete_thread", {}).get("replies", [])
    # Keep first 2 replies (context) + last 6 replies (resolution/outcome)
    if len(replies) <= 10:
        kept_replies = replies
    else:
        kept_replies = replies[:2] + replies[-6:]

    topic = (parent.get("text", "") or t.get("parent_text", "") or "")[:600]
    parent_user_id = parent.get("user_id", parent.get("user", ""))
    parent_user_name = parent.get("user_name", "")

    permalink = make_permalink(ch_id, thread_ts)

    slim_threads.append({
        "channel_name": t.get("channel_name", ""),
        "channel_id": ch_id,
        "thread_ts": thread_ts,
        "topic": topic,
        "parent_user_id": parent_user_id,
        "parent_user_name": parent_user_name,
        "reply_count": t.get("thread_stats", {}).get("reply_count", len(replies)),
        "permalink": permalink,
        "replies": [slim_message(r, ch_id) for r in kept_replies],
    })

# ── Channels ──
slim_channels = {}
for ch_name, ch_data in data.get("channels", {}).items():
    ch_id = ch_data.get("channel_id", "")
    slim_channels[ch_name] = {
        "channel_id": ch_id,
        "tier": ch_data.get("tier", "org"),
        "messages": [slim_message(m, ch_id) for m in ch_data.get("messages", [])],
    }

result = {
    "poll_time": data.get("poll_time", ""),
    "mentions": slim_mentions,
    "threads": slim_threads,
    "channels": slim_channels,
}

with open(out_file, "w") as f:
    json.dump(result, f, indent=1)

orig_kb = len(open(poll_file).read()) / 1024
slim_kb = len(open(out_file).read()) / 1024
print(f"Slimmed: {orig_kb:.0f}KB -> {slim_kb:.0f}KB ({slim_kb/orig_kb*100:.0f}%)" if orig_kb > 0 else "Slimmed: 0KB")
FILTEREOF

if [[ ! -s "$SLIM_FILE" ]]; then
    log "ERROR: Failed to slim JSON"
    exit 1
fi

# ── Step 2: Claude haiku generates summary (no tools, stdin input) ───────────
SUMMARY_FILE="${SUMMARY_OUTPUT_FILE:-$SUMMARY_DIR/summary_${NOW_TS}.md}"

log "Running Claude (haiku)..."

# Build system prompt with user identity injected
CLAUDE_INPUT_FILE="/tmp/slack_claude_input_$$.txt"
{
    # Inject user context at the top of the prompt
    echo "The manager's Slack user_id is ${MY_SLACK_USER_ID:-unknown} (${MY_SLACK_USER_NAME:-unknown}). Any message from this user_id is the manager's OWN message — do not present it as someone else's action."
    echo ""
    # Read the rest of the system prompt (skip first 2 lines which were the old hardcoded identity)
    tail -n +3 "$SYSTEM_PROMPT_FILE"
    echo ""
    echo "---"
    echo "Here is the Slack poll JSON data. Produce the briefing:"
    echo ""
    cat "$SLIM_FILE"
} > "$CLAUDE_INPUT_FILE"

EXIT_CODE=0
cat "$CLAUDE_INPUT_FILE" | claude -p \
    --model haiku \
    --tools "" \
    --max-budget-usd 1.00 \
    --no-session-persistence \
    > "$SUMMARY_FILE" 2>"$SUMMARY_DIR/claude_err_${NOW_TS}.log" \
    || EXIT_CODE=$?
rm -f "$CLAUDE_INPUT_FILE"

if [[ $EXIT_CODE -ne 0 ]]; then
    log "ERROR: Claude exited with code $EXIT_CODE"
    log "stderr: $(cat "$SUMMARY_DIR/claude_err_${NOW_TS}.log")"
    [[ -s "$SUMMARY_FILE" ]] || rm -f "$SUMMARY_FILE"
    exit 1
fi

if [[ ! -s "$SUMMARY_FILE" ]]; then
    log "WARNING: Claude produced empty output"
    rm -f "$SUMMARY_FILE"
    exit 1
fi

# Check for auth failure (Claude prints "Not logged in" to stdout with exit 0)
if grep -qi -e "not logged in" -e "please run /login" "$SUMMARY_FILE" 2>/dev/null; then
    log "ERROR: Claude not authenticated. Run 'claude /login' in a terminal."
    rm -f "$SUMMARY_FILE"
    exit 1
fi

# Clean up error log on success
rm -f "$SUMMARY_DIR/claude_err_${NOW_TS}.log"

if [[ "$SKIP_SEND" != "1" ]]; then
    log "Summary generated, sending to Slack DM..."

    # ── Step 3: Send to Slack DM via proxy API ───────────────────────────────
    python3 - "$SUMMARY_FILE" "$SEND_PAYLOAD_FILE" << 'MKJSON'
import json, sys
summary_file, payload_file = sys.argv[1], sys.argv[2]
with open(summary_file) as f:
    text = f.read().strip()
with open(payload_file, "w") as f:
    json.dump({"text": text, "unfurl_links": False, "unfurl_media": False}, f)
MKJSON

    SEND_RESPONSE=$(curl -sk -X POST "${API_BASE}/api/messages/${DM_CHANNEL}/send" \
        -H "X-API-Key: ${API_KEY}" \
        -H "Content-Type: application/json" \
        -d @"$SEND_PAYLOAD_FILE" \
        2>&1)

    if echo "$SEND_RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d.get('success') else 1)" 2>/dev/null; then
        log "Sent digest to Slack DM $DM_CHANNEL"
    else
        log "WARNING: Failed to send to Slack: $SEND_RESPONSE"
    fi
else
    log "Summary generated (skip-send mode, not sending to Slack)"
fi

# ── Step 4: Publish living docs (convert Slack mrkdwn -> Markdown first) ──
# Skip for daily reports and "all quiet" summaries (nothing new)
source "$SCRIPT_DIR/publish.sh"
IS_QUIET=$(grep -ci 'all quiet' "$SUMMARY_FILE" 2>/dev/null || true)

if publish_enabled && [[ -z "${SYSTEM_PROMPT_OVERRIDE:-}" ]]; then
    SYNC_TS="_Last synced: $(date '+%Y-%m-%d %H:%M')_"

    if [[ "$IS_QUIET" -gt 0 || ! -s "$SUMMARY_FILE" ]]; then
        # Quiet — just update the sync timestamp on existing content
        PUB_EXISTING="/tmp/slack_pub_existing_$$.md"
        publish_read "slack/latest.md" > "$PUB_EXISTING" 2>/dev/null || true
        if [[ -s "$PUB_EXISTING" ]]; then
            python3 -c "
import re, sys
content = open(sys.argv[1]).read()
content = re.sub(r'^_Last synced:.*_\n*', '', content)
print(sys.argv[2] + '\n\n' + content.strip())
" "$PUB_EXISTING" "$SYNC_TS" | publish_write "slack/latest.md" \
                && log "Updated sync timestamp on slack/latest.md (no new messages)" \
                || log "WARNING: Failed to update sync timestamp"
        fi
        rm -f "$PUB_EXISTING"
    fi
fi

if publish_enabled && [[ -s "$SUMMARY_FILE" ]] && [[ -z "${SYSTEM_PROMPT_OVERRIDE:-}" ]] && [[ "$IS_QUIET" -eq 0 ]]; then
    PUB_TMP="/tmp/slack_pub_$$.md"

    export SLACK_ARCHIVES_BASE="$SLACK_BASE"

    python3 -c "
import re, sys, json, os, glob as g

summary_file, poll_file = sys.argv[1], sys.argv[2]
text = open(summary_file).read()

# Build user_map from persistent cache + consolidated + all filtered files + current poll
user_map = {}
data_dir = os.path.dirname(os.path.dirname(poll_file))  # up from raw/YYYY-MM-DD/
cache_file = os.path.join(data_dir, 'state', 'user_map.json')

try: user_map.update(json.load(open(cache_file)))
except: pass
try: user_map.update(json.load(open(os.path.join(data_dir, 'consolidated', 'enriched.json'))).get('user_map', {}))
except: pass

def extract_users(d):
    users = {}
    for m in d.get('mentions', []):
        uid, name = m.get('user_id', m.get('user', '')), m.get('user_name', '')
        if uid and name: users[uid] = name
    for t in d.get('threads', []):
        uid, name = t.get('parent_user_id', ''), t.get('parent_user_name', '')
        if uid and name: users[uid] = name
        for r in t.get('replies', t.get('_replies', [])):
            uid, name = r.get('user_id', r.get('user', '')), r.get('user_name', '')
            if uid and name: users[uid] = name
    for ch in d.get('channels', {}).values():
        for m in ch.get('messages', []):
            uid, name = m.get('user_id', m.get('user', '')), m.get('user_name', '')
            if uid and name: users[uid] = name
    return users

for fp in g.glob(os.path.join(data_dir, 'raw', '*', 'filtered_*.json')):
    try: user_map.update(extract_users(json.load(open(fp))))
    except: pass
try: user_map.update(extract_users(json.load(open(poll_file))))
except: pass
try:
    os.makedirs(os.path.dirname(cache_file), exist_ok=True)
    json.dump(user_map, open(cache_file, 'w'))
except: pass

def replace_user(m):
    uid = m.group(1)
    return '@' + user_map.get(uid, uid)
text = re.sub(r'<@([A-Z0-9]+)>', replace_user, text)
text = re.sub(r'<#[A-Z0-9]+\|([^>]+)>', r'#\1', text)
text = re.sub(r'<(https?://[^|>]+)\|([^>]+)>', r'[\2](\1)', text)
text = re.sub(r'<(https?://[^>]+)>', r'\1', text)

EMOJI_MAP = {
    ':newspaper:': '\U0001F4F0', ':zap:': '\u26A1', ':rotating_light:': '\U0001F6A8',
    ':warning:': '\u26A0\uFE0F', ':hammer_and_wrench:': '\U0001F6E0\uFE0F',
    ':globe_with_meridians:': '\U0001F310', ':eyes:': '\U0001F440',
    ':white_check_mark:': '\u2705', ':white_square_button:': '\u2B1C',
    ':point_right:': '\U0001F449', ':fire:': '\U0001F525', ':rocket:': '\U0001F680',
    ':bulb:': '\U0001F4A1', ':memo:': '\U0001F4DD', ':link:': '\U0001F517',
    ':lock:': '\U0001F512', ':gear:': '\u2699\uFE0F', ':tada:': '\U0001F389',
    ':x:': '\u274C', ':heavy_check_mark:': '\u2714\uFE0F', ':clock3:': '\U0001F552',
    ':speech_balloon:': '\U0001F4AC', ':pushpin:': '\U0001F4CC',
    ':red_circle:': '\U0001F534', ':large_blue_circle:': '\U0001F535',
    ':arrow_right:': '\u27A1\uFE0F', ':hourglass:': '\u231B',
    ':chart_with_upwards_trend:': '\U0001F4C8', ':wrench:': '\U0001F527',
    ':package:': '\U0001F4E6', ':bookmark:': '\U0001F516',
}
for code, uni in EMOJI_MAP.items():
    text = text.replace(code, uni)
text = re.sub(r':([a-z0-9_+-]+):', r'\1', text)

print(text, end='')
" "$SUMMARY_FILE" "$SLIM_FILE" > "$PUB_TMP"

    # Read existing content, deduplicate threads, prepend new summary
    PUB_EXISTING="/tmp/slack_pub_existing_$$.md"
    PUB_DEDUPED="/tmp/slack_pub_deduped_$$.md"
    publish_read "slack/latest.md" > "$PUB_EXISTING" 2>/dev/null || true

    # Extract workspace domain for dedup regex
    SLACK_DOMAIN=$(echo "$SLACK_WORKSPACE_URL" | sed 's|https://||' | sed 's|/$||')
    export SLACK_DOMAIN

    python3 - "$PUB_TMP" "$PUB_EXISTING" "$PUB_DEDUPED" << 'DEDUP_EOF'
"""Merge new briefing into existing latest.md.

Simple approach: keep the original briefing format exactly as Claude
generates it. Group by date — merge same-date briefings, remove
duplicate thread links (newer wins). Older dates stay below.
"""
import re, sys, datetime, os

new_file, old_file, out_file = sys.argv[1], sys.argv[2], sys.argv[3]
slack_domain = os.environ.get("SLACK_DOMAIN", "")

new_text = open(new_file).read().strip()
try:
    old_text = open(old_file).read().strip()
except:
    old_text = ""

# Strip old sync timestamp
old_text = re.sub(r'^_Last synced:.*_\n*', '', old_text).strip()

def extract_all_link_keys(text):
    """Extract all thread keys from all link formats."""
    keys = set()
    # slack://channel?team=X&id=CHANNEL&message=TS
    for m in re.finditer(r'slack://channel\?team=[^&]+&id=([A-Z0-9]+)&message=([0-9.]+)', text):
        keys.add(f"{m.group(1)}:{m.group(2)}")
    # https://<workspace>.slack.com/archives/CHANNEL/pTS
    if slack_domain:
        pattern = re.escape(slack_domain) + r'/archives/([A-Z0-9]+)/p(\d+)'
    else:
        pattern = r'[\w-]+\.slack\.com/archives/([A-Z0-9]+)/p(\d+)'
    for m in re.finditer(pattern, text):
        raw_ts = m.group(2)
        ts = f"{raw_ts[:10]}.{raw_ts[10:]}" if len(raw_ts) > 10 else raw_ts
        keys.add(f"{m.group(1)}:{ts}")
    # https://slack.com/app_redirect?team=X&channel=CHANNEL&message_ts=TS
    for m in re.finditer(r'slack\.com/app_redirect\?team=[^&]+&channel=([A-Z0-9]+)&message_ts=([0-9.]+)', text):
        keys.add(f"{m.group(1)}:{m.group(2)}")
    return keys

MONTHS = {'jan':'01','feb':'02','mar':'03','apr':'04','may':'05','jun':'06',
          'jul':'07','aug':'08','sep':'09','oct':'10','nov':'11','dec':'12'}

def extract_date(section):
    """Extract date from a briefing section header."""
    m = re.search(r'Briefing.*?(\d{4}-\d{2}-\d{2})', section)
    if m:
        return m.group(1)
    m = re.search(r'Briefing.*?((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\w*)\s+(\d+),?\s+(\d{4})', section, re.IGNORECASE)
    if m:
        mon = MONTHS.get(m.group(1)[:3].lower())
        if mon:
            return f"{m.group(3)}-{mon}-{int(m.group(2)):02d}"
    return None

def section_has_content(section):
    """Check if a section has real content beyond just headers."""
    for line in section.split("\n"):
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("_Last synced"):
            continue
        if re.match(r'^[\U0001F4F0].*Briefing', stripped):
            continue
        if re.match(r'^[\U0001F300-\U0001FFFF\u2600-\u27FF\u2B00-\u2BFF]', stripped) and 'slack.com' not in stripped and 'slack://' not in stripped:
            continue
        return True
    return False

# Split existing content into sections by ---
old_sections = [s.strip() for s in re.split(r'\n---\n', old_text) if s.strip()]

new_links = extract_all_link_keys(new_text)
new_date = extract_date(new_text)

kept_sections = []

for section in old_sections:
    section_date = extract_date(section)

    if section_date and new_date and section_date == new_date:
        lines = section.split("\n")
        filtered = []
        skip_next_empty = False
        for line in lines:
            line_links = extract_all_link_keys(line)
            if line_links & new_links:
                skip_next_empty = True
                continue
            if skip_next_empty and not line.strip():
                skip_next_empty = False
                continue
            skip_next_empty = False
            filtered.append(line)

        remaining = "\n".join(filtered).strip()
        if section_has_content(remaining):
            remaining_lines = remaining.split("\n")
            remaining_lines = [l for l in remaining_lines
                               if not re.match(r'^[\U0001F4F0].*Briefing', l.strip())]
            remaining_body = "\n".join(remaining_lines).strip()
            if remaining_body:
                new_text = new_text.rstrip() + "\n\n" + remaining_body
        continue

    section_links = extract_all_link_keys(section)
    if section_links & new_links:
        lines = section.split("\n")
        filtered = []
        for line in lines:
            line_links = extract_all_link_keys(line)
            if line_links & new_links:
                continue
            filtered.append(line)
        section = "\n".join(filtered).strip()

    if section_has_content(section):
        kept_sections.append(section)

sync_ts = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
parts = [f"_Last synced: {sync_ts}_\n\n{new_text}"]
parts.extend(kept_sections)

total_old = len(old_sections)
total_kept = len(kept_sections)
print(f"  Merge: new into {new_date}, {total_old} old sections -> {total_kept} kept", file=sys.stderr)

with open(out_file, "w") as f:
    f.write("\n\n---\n\n".join(parts) + "\n")
DEDUP_EOF

    if [[ -s "$PUB_DEDUPED" ]]; then
        publish_write "slack/latest.md" < "$PUB_DEDUPED" \
            && log "Published summary to slack/latest.md (deduped + prepended)" \
            || log "WARNING: Failed to publish to slack/latest.md"
    else
        log "WARNING: Dedup output empty — skipping write to avoid data loss"
    fi
    rm -f "$PUB_TMP" "$PUB_EXISTING" "$PUB_DEDUPED"
fi

log "Summary saved to $SUMMARY_FILE"
log "Done."

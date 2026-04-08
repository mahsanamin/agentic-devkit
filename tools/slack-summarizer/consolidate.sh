#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# consolidate.sh — Daily consolidation of Slack summaries into living docs
#
# Scans all filtered_*.json, extracts unique threads/mentions/messages,
# fetches latest thread state via activity endpoints, then generates:
#   1. links.md          — Thread tracker with Claude-summarized one-liners
#   2. latest_summary.md — Consolidated status summary (Claude-generated)
#
# Pruning: Threads with no reply in STALE_DAYS are removed from all files.
#
# Usage:
#   ./consolidate.sh                  # generate all files
#   ./consolidate.sh --dry-run        # show what would be done, don't write
#   ./consolidate.sh --delete-old     # also delete old DM messages
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$SCRIPT_DIR/config.env" ]] && source "$SCRIPT_DIR/config.env"
DATA_DIR="${DATA_DIR:-$SCRIPT_DIR}"

API_BASE="${SLACK_PROXY_URL:?Error: SLACK_PROXY_URL not set in config.env}"
API_KEY="${SLACK_PROXY_API_KEY:?Error: SLACK_PROXY_API_KEY not set in config.env}"
DM_CHANNEL="${SLACK_DM_CHANNEL:?Error: SLACK_DM_CHANNEL not set in config.env}"
SLACK_BASE="${SLACK_WORKSPACE_URL:?Error: SLACK_WORKSPACE_URL not set in config.env}/archives"
CONSOLIDATE_DIR="$DATA_DIR/consolidated"
STALE_DAYS="${STALE_DAYS:-30}"
LOG_PREFIX="[$(date '+%Y-%m-%d %H:%M:%S')] [consolidate]"
DRY_RUN=0
DELETE_OLD=0
DELETE_OLDER_THAN_DAYS="${DELETE_OLDER_THAN_DAYS:-7}"
MY_USER_ID="${MY_SLACK_USER_ID:-unknown}"
MY_USER_NAME="${MY_SLACK_USER_NAME:-unknown}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --delete-old) DELETE_OLD=1; shift ;;
        *) shift ;;
    esac
done

log() { echo "$LOG_PREFIX $*"; }

mkdir -p "$CONSOLIDATE_DIR"

ENRICHED_JSON="/tmp/consolidate_enriched_$$.json"
SUMMARY_INPUT="/tmp/consolidate_summary_input_$$.json"
cleanup() { rm -f "$ENRICHED_JSON" "$SUMMARY_INPUT"; }
trap cleanup EXIT

# ── Step 1: Extract all data from filtered files + fetch fresh threads ────
log "Scanning filtered data and fetching latest thread states..."

export SLACK_ARCHIVES_BASE="$SLACK_BASE"

python3 - "$DATA_DIR" "$ENRICHED_JSON" "$STALE_DAYS" "$API_BASE" "$API_KEY" << 'MAIN_EOF'
import json, glob, sys, time, os, ssl, urllib.request

data_dir = sys.argv[1]
out_file = sys.argv[2]
stale_days = int(sys.argv[3])
api_base = sys.argv[4]
api_key = sys.argv[5]

now = time.time()
stale_cutoff = now - (stale_days * 86400)
SLACK_BASE = os.environ.get("SLACK_ARCHIVES_BASE", "")

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

def api_get(endpoint, retries=3):
    for attempt in range(retries):
        req = urllib.request.Request(
            f"{api_base}{endpoint}",
            headers={"X-API-Key": api_key}
        )
        try:
            with urllib.request.urlopen(req, context=ctx, timeout=15) as resp:
                return json.loads(resp.read())
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < retries - 1:
                wait = (attempt + 1) * 3
                print(f"  Rate limited, waiting {wait}s...", file=sys.stderr)
                time.sleep(wait)
                continue
            return {"success": False, "error": str(e)}
        except Exception as e:
            return {"success": False, "error": str(e)}

def make_permalink(channel_id, ts):
    if channel_id and ts and SLACK_BASE:
        return f"{SLACK_BASE}/{channel_id}/p{ts.replace('.', '')}"
    return ""

# ── Scan filtered files for historical data ──
files = sorted(glob.glob(os.path.join(data_dir, "raw", "*", "filtered_*.json")))
print(f"Scanning {len(files)} filtered files...", file=sys.stderr)

hist_threads = {}
mentions = {}
channel_msgs = {}
user_map = {}

for fpath in files:
    try:
        with open(fpath) as f:
            d = json.load(f)
    except Exception:
        continue

    for t in d.get("threads", []):
        key = (t.get("thread_ts", ""), t.get("channel_id", ""))
        if not key[0]:
            continue
        replies = t.get("replies", t.get("complete_thread", {}).get("replies", []))
        new_count = t.get("thread_stats", {}).get("reply_count", len(replies))
        existing = hist_threads.get(key)
        if not existing or new_count > existing.get("_reply_count", 0):
            t["_reply_count"] = new_count
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
            uid = msg.get("user_id", msg.get("user", ""))
            name = msg.get("user_name", "")
            if uid and name:
                user_map[uid] = name

    for m in d.get("mentions", []):
        uid = m.get("user_id", m.get("user", ""))
        name = m.get("user_name", "")
        if uid and name:
            user_map[uid] = name
    for t in d.get("threads", []):
        uid = t.get("parent_user_id", "")
        name = t.get("parent_user_name", "")
        if uid and name:
            user_map[uid] = name
        for r in t.get("replies", t.get("_replies", [])):
            uid = r.get("user_id", r.get("user", ""))
            name = r.get("user_name", "")
            if uid and name:
                user_map[uid] = name

# ── Fetch latest state for EVERY thread via thread endpoint ──
print(f"Fetching latest state for {len(hist_threads)} threads from Slack...", file=sys.stderr)

merged_threads = []
stale_count = 0
fetch_ok = 0
fetch_fail = 0

for (thread_ts, channel_id), hist in hist_threads.items():
    resp = api_get(f"/api/channels/{channel_id}/thread/{thread_ts}")

    if resp.get("success"):
        fetch_ok += 1
        data = resp.get("data", {})
        parent = data.get("parent_message", {}) or {}
        replies = data.get("replies", [])
        reply_count = data.get("reply_count", len(replies))

        latest_ts = thread_ts
        if replies:
            latest_ts = max(r.get("ts", "0") for r in replies)
        latest_float = float(latest_ts) if latest_ts else 0

        if latest_float < stale_cutoff:
            stale_count += 1
            continue

        topic = (parent.get("text", "") or hist.get("topic", "") or "")[:500]
        parent_user_name = parent.get("user_name", hist.get("parent_user_name", ""))
        parent_user_id = parent.get("user_id", parent.get("user", hist.get("parent_user_id", "")))

        if len(replies) <= 10:
            kept_replies = replies
        else:
            kept_replies = replies[:2] + replies[-8:]

        last_reply_by = ""
        last_reply_text = ""
        if replies:
            last = replies[-1]
            last_reply_by = last.get("user_name", "")
            last_reply_text = (last.get("text", "") or "")[:200]

        merged_threads.append({
            "thread_ts": thread_ts,
            "channel_id": channel_id,
            "channel_name": hist.get("channel_name", ""),
            "topic": topic,
            "parent_user_name": parent_user_name,
            "parent_user_id": parent_user_id,
            "reply_count": reply_count,
            "permalink": make_permalink(channel_id, thread_ts),
            "last_activity": latest_ts,
            "last_activity_date": time.strftime("%Y-%m-%d %H:%M", time.localtime(latest_float)) if latest_float > 0 else "?",
            "last_reply_by": last_reply_by,
            "last_reply_text": last_reply_text,
            "latest_replies": [{
                "user_name": r.get("user_name", ""),
                "user_id": r.get("user_id", r.get("user", "")),
                "text": (r.get("text", "") or "")[:500],
                "ts": r.get("ts", ""),
            } for r in kept_replies],
            "source": "fresh",
        })
    else:
        fetch_fail += 1
        t = hist
        replies = t.get("_replies", [])
        parent = t.get("parent_message", {}) or {}

        latest_ts = thread_ts
        if replies:
            latest_ts = max(r.get("ts", "0") for r in replies)
        latest_float = float(latest_ts) if latest_ts else 0

        if latest_float < stale_cutoff:
            stale_count += 1
            continue

        topic = (parent.get("text", "") or t.get("topic", "") or t.get("parent_text", ""))[:500]
        parent_user_name = parent.get("user_name", t.get("parent_user_name", ""))
        parent_user_id = parent.get("user_id", parent.get("user", t.get("parent_user_id", "")))
        reply_count = t.get("_reply_count", len(replies))

        if len(replies) <= 10:
            kept_replies = replies
        else:
            kept_replies = replies[:2] + replies[-8:]

        last_reply_by = ""
        last_reply_text = ""
        if replies:
            last = replies[-1]
            last_reply_by = last.get("user_name", "")
            last_reply_text = (last.get("text", "") or "")[:200]

        merged_threads.append({
            "thread_ts": thread_ts,
            "channel_id": channel_id,
            "channel_name": t.get("channel_name", ""),
            "topic": topic,
            "parent_user_name": parent_user_name,
            "parent_user_id": parent_user_id,
            "reply_count": reply_count,
            "permalink": make_permalink(channel_id, thread_ts),
            "last_activity": latest_ts,
            "last_activity_date": time.strftime("%Y-%m-%d %H:%M", time.localtime(latest_float)) if latest_float > 0 else "?",
            "last_reply_by": last_reply_by,
            "last_reply_text": last_reply_text,
            "latest_replies": [{
                "user_name": r.get("user_name", ""),
                "user_id": r.get("user_id", r.get("user", "")),
                "text": (r.get("text", "") or "")[:500],
                "ts": r.get("ts", ""),
            } for r in kept_replies],
            "source": "historical",
        })

print(f"  Fetched: {fetch_ok} OK, {fetch_fail} failed (used historical), {stale_count} stale pruned", file=sys.stderr)
print(f"  User map: {len(user_map)} users", file=sys.stderr)

merged_threads.sort(key=lambda x: float(x.get("last_activity", "0")), reverse=True)

mention_list = list(mentions.values())
for m in mention_list:
    if not m.get("permalink"):
        m["permalink"] = make_permalink(m.get("channel_id", ""), m.get("ts", m.get("message_ts", "")))
mention_list.sort(key=lambda x: float(x.get("ts", x.get("message_ts", "0"))), reverse=True)

active_channel_msgs = sorted(
    [m for m in channel_msgs.values() if float(m.get("ts", "0")) >= stale_cutoff],
    key=lambda x: float(x.get("ts", "0")),
    reverse=True
)

result = {
    "threads": merged_threads,
    "mentions": mention_list,
    "channel_messages": active_channel_msgs,
    "user_map": user_map,
    "stats": {
        "active_threads": len(merged_threads),
        "stale_threads": stale_count,
        "fresh_threads": sum(1 for t in merged_threads if t.get("source") == "fresh"),
        "mentions": len(mention_list),
        "active_channel_msgs": len(active_channel_msgs),
    }
}

with open(out_file, "w") as f:
    json.dump(result, f)

s = result["stats"]
print(f"Result: {s['active_threads']} active threads ({s['fresh_threads']} fresh), {s['stale_threads']} stale pruned, {s['mentions']} mentions, {s['active_channel_msgs']} channel msgs", file=sys.stderr)
MAIN_EOF

if [[ ! -s "$ENRICHED_JSON" ]]; then
    log "ERROR: Failed to extract/enrich data"
    exit 1
fi

cp "$ENRICHED_JSON" "$CONSOLIDATE_DIR/enriched.json"

# ── Step 2: Generate links.md (Claude-summarized one-liners) ──────────────
log "Generating links.md via Claude Haiku..."

LINKS_INPUT="/tmp/consolidate_links_input_$$.json"
python3 - "$ENRICHED_JSON" "$LINKS_INPUT" << 'LINKS_PREP_EOF'
import json, sys, re

with open(sys.argv[1]) as f:
    data = json.load(f)

user_map = data.get("user_map", {})

def resolve_users(text):
    def repl(m):
        return f"@{user_map.get(m.group(1), m.group(1))}"
    return re.sub(r'<@([A-Z0-9]+)(?:\|[^>]*)?>', repl, text)

threads = []
for t in data["threads"]:
    topic = resolve_users((t.get("topic", "") or "").replace("\n", " ").strip()[:400])
    last_text = resolve_users((t.get("last_reply_text", "") or "").replace("\n", " ").strip()[:300])
    replies_summary = []
    for r in t.get("latest_replies", [])[-4:]:
        rtxt = resolve_users((r.get("text", "") or "").replace("\n", " ").strip()[:200])
        replies_summary.append(f"@{r.get('user_name','?')}: {rtxt}")

    threads.append({
        "i": len(threads),
        "channel": t.get("channel_name", "?"),
        "topic": topic,
        "reply_count": t.get("reply_count", 0),
        "last_date": t.get("last_activity_date", "?"),
        "last_by": t.get("last_reply_by", ""),
        "last_text": last_text,
        "recent_replies": replies_summary,
        "permalink": t.get("permalink", ""),
    })

with open(sys.argv[2], "w") as f:
    json.dump({"threads": threads, "stats": data["stats"]}, f, indent=1)
print(f"  Prepared {len(threads)} threads for links summarization", file=sys.stderr)
LINKS_PREP_EOF

LINKS_FILE="$CONSOLIDATE_DIR/links.md"

LINKS_PROMPT='You are generating a thread tracker for a manager.

For each thread in the JSON, produce exactly TWO lines:
1. **{summary}** — a meaningful 1-2 line summary of WHAT this thread is about and its current state. Not raw message text. Distill the essence: what decision/task/issue, who is involved, what is the status.
2. > Latest: {1-line status} — what happened most recently, in plain English.

Read the topic, recent_replies, and last_text to understand context before writing.

Output format (Markdown):

# Active Threads — {today date}

_Last run: {current datetime}. Next scheduled: 11:00 PM tonight._
_{N} active threads, {M} stale pruned._

**{Meaningful summary of the thread — what is it about, current state}**
_#{channel} · {N} replies · last: {date} · by @{name}_ [view thread](permalink)
> Latest: {What happened most recently — 1 clear sentence}

**{Next thread...}**
...

---
_Threads with no activity for '"$STALE_DAYS"'+ days are automatically removed._

Rules:
- NEVER copy raw message text as the title. Summarize it meaningfully.
- The bold title should tell the reader what the thread is about without clicking it.
- "Latest" should convey what just happened, not raw text.
- Use @user_name (never user IDs).
- Keep each thread to exactly 3 lines (bold title, meta line, latest quote).
- Most recent threads first (they are already sorted).'

if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY RUN — would generate links.md via Claude Haiku"
else
    LINKS_CLAUDE_INPUT="/tmp/consolidate_links_claude_$$.txt"
    {
        echo "$LINKS_PROMPT"
        echo ""
        echo "---"
        echo "Thread data:"
        echo ""
        cat "$LINKS_INPUT"
    } > "$LINKS_CLAUDE_INPUT"

    LINKS_EXIT=0
    cat "$LINKS_CLAUDE_INPUT" | claude -p \
        --model haiku \
        --tools "" \
        --max-budget-usd 0.50 \
        --no-session-persistence \
        > "$LINKS_FILE" 2>"$CONSOLIDATE_DIR/links_claude_err.log" \
        || LINKS_EXIT=$?
    rm -f "$LINKS_CLAUDE_INPUT" "$LINKS_INPUT"

    if [[ $LINKS_EXIT -ne 0 || ! -s "$LINKS_FILE" ]]; then
        log "WARNING: Claude failed for links.md (exit $LINKS_EXIT). Falling back to raw format."
        [[ -f "$CONSOLIDATE_DIR/links_claude_err.log" ]] && cat "$CONSOLIDATE_DIR/links_claude_err.log"
        python3 - "$ENRICHED_JSON" "$LINKS_FILE" << 'LINKS_FALLBACK'
import json, sys, time, re
with open(sys.argv[1]) as f:
    data = json.load(f)
um = data.get("user_map", {})
def ru(t):
    return re.sub(r'<@([A-Z0-9]+)(?:\|[^>]*)?>', lambda m: f"@{um.get(m.group(1), m.group(1))}", t)
lines = [f"# Active Threads — {time.strftime('%Y-%m-%d')}", "",
    f"_Last run: {time.strftime('%Y-%m-%d %H:%M')}. {data['stats']['active_threads']} active, {data['stats']['stale_threads']} pruned._", ""]
for t in data["threads"]:
    topic = ru((t.get("topic","") or "").replace("\n"," ").strip()[:120])
    ch, la, rc, pl = t.get("channel_name","?"), t.get("last_activity_date","?"), t.get("reply_count",0), t.get("permalink","")
    lb = t.get("last_reply_by","")
    lines.append(f"**{topic}**")
    meta = f"_#{ch} · {rc} replies · last: {la}"
    if lb: meta += f" · by @{lb}"
    meta += f"_ [view thread]({pl})" if pl else "_"
    lines.append(meta)
    lines.append("")
lines += ["---", f"_Threads with no activity for {data.get('stale_days', 30)}+ days are automatically removed._"]
with open(sys.argv[2], "w") as f:
    f.write("\n".join(lines) + "\n")
LINKS_FALLBACK
    else
        rm -f "$CONSOLIDATE_DIR/links_claude_err.log"
        log "links.md generated via Claude."
    fi
fi

# ── Step 3: Generate latest_summary.md via Claude ─────────────────────────
log "Generating latest_summary.md via Claude..."

python3 - "$ENRICHED_JSON" "$SUMMARY_INPUT" << 'PREP_EOF'
import json, sys

with open(sys.argv[1]) as f:
    data = json.load(f)

slim = {
    "threads": [{
        "channel_name": t.get("channel_name", ""),
        "topic": t.get("topic", "")[:400],
        "parent_user_name": t.get("parent_user_name", ""),
        "reply_count": t.get("reply_count", 0),
        "last_activity_date": t.get("last_activity_date", ""),
        "last_reply_by": t.get("last_reply_by", ""),
        "last_reply_text": t.get("last_reply_text", ""),
        "permalink": t.get("permalink", ""),
        "latest_replies": t.get("latest_replies", []),
    } for t in data["threads"]],
    "stats": data["stats"],
}

with open(sys.argv[2], "w") as f:
    json.dump(slim, f, indent=1)
print(f"  Summary input: {len(json.dumps(slim)) / 1024:.0f}KB", file=sys.stderr)
PREP_EOF

SUMMARY_PROMPT="You are summarizing all active Slack threads for a manager (${MY_USER_NAME}, user_id ${MY_USER_ID}).

This is a CONSOLIDATED view of all active threads across the past weeks. Generate a clean, readable Markdown summary.

For each thread:
- Read ALL replies to understand the current state
- Summarize what happened, what was decided, what is still open
- Note who is responsible for next steps
- If the manager (${MY_USER_ID}) replied, note what they committed to

Format:

# Active Threads Summary — {today's date}

## Needs Your Action
Threads where YOU need to do something. Be specific about what.
- **{Topic}** (#{channel}) — {what you need to do}. Last active: {date}. [view thread](permalink)

## In Progress
Active threads being handled by others. Status update only.
- **{Topic}** (#{channel}) — {current state, who is working on it}. Last active: {date}. [view thread](permalink)

## Recently Resolved
Threads that reached a conclusion. Include the outcome.
- **{Topic}** (#{channel}) — {outcome}. [view thread](permalink)

## Watching
Threads you are CC'd on or monitoring. Brief status only.
- **{Topic}** (#{channel}) — {one-liner}. [view thread](permalink)

Rules:
- Read the latest_replies carefully — they contain the current state
- Be specific: PR numbers, dates, names, decisions
- Keep each bullet to 1-2 lines max
- Sort by importance within each section
- Skip empty sections"

SUMMARY_FILE="$CONSOLIDATE_DIR/latest_summary.md"

if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY RUN — would generate latest_summary.md via Claude"
else
    CLAUDE_INPUT="/tmp/consolidate_claude_$$.txt"
    {
        echo "$SUMMARY_PROMPT"
        echo ""
        echo "---"
        echo "Here is the enriched thread data:"
        echo ""
        cat "$SUMMARY_INPUT"
    } > "$CLAUDE_INPUT"

    EXIT_CODE=0
    cat "$CLAUDE_INPUT" | claude -p \
        --model sonnet \
        --tools "" \
        --max-budget-usd 1.00 \
        --no-session-persistence \
        > "$SUMMARY_FILE" 2>"$CONSOLIDATE_DIR/claude_err.log" \
        || EXIT_CODE=$?
    rm -f "$CLAUDE_INPUT"

    if [[ $EXIT_CODE -ne 0 || ! -s "$SUMMARY_FILE" ]]; then
        log "WARNING: Claude failed (exit $EXIT_CODE). latest_summary.md not generated."
        [[ -f "$CONSOLIDATE_DIR/claude_err.log" ]] && cat "$CONSOLIDATE_DIR/claude_err.log"
    else
        rm -f "$CONSOLIDATE_DIR/claude_err.log"
        log "latest_summary.md generated."
    fi
fi

# ── Step 4: Clean Slack mrkdwn from all markdown files ────────────────────
log "Cleaning Slack markup from markdown files..."

python3 "$SCRIPT_DIR/clean_slack_mrkdwn.py" "$ENRICHED_JSON" "$CONSOLIDATE_DIR"

# ── Step 5: Publish living docs ───────────────────────────────────────────
source "$SCRIPT_DIR/publish.sh"

if publish_enabled; then
    log "Publishing living docs (mode: $PUBLISH_MODE)..."
    for pair in \
        "links.md:slack/links-to-track.md" \
        "latest_summary.md:slack/summaries.md"; do
        LOCAL="${pair%%:*}"
        REMOTE="${pair##*:}"
        if [[ -s "$CONSOLIDATE_DIR/$LOCAL" ]]; then
            publish_write "$REMOTE" < "$CONSOLIDATE_DIR/$LOCAL" \
                && log "  Published $LOCAL -> $REMOTE" \
                || log "  WARNING: Failed to publish $LOCAL"
        fi
    done
fi

# ── Step 6: Delete old DM messages (if --delete-old) ──────────────────────
if [[ "$DELETE_OLD" == "1" ]]; then
    log "Waiting 10s for rate limits to cool down before DM cleanup..."
    sleep 10
    log "Deleting summary messages older than ${DELETE_OLDER_THAN_DAYS} days from DM..."

    python3 - "$API_BASE" "$API_KEY" "$DM_CHANNEL" "$DELETE_OLDER_THAN_DAYS" "$DRY_RUN" << 'DELETE_EOF'
import json, ssl, urllib.request, sys, time

api_base, api_key, dm_channel = sys.argv[1], sys.argv[2], sys.argv[3]
older_than_days, dry_run = int(sys.argv[4]), sys.argv[5] == "1"

cutoff = time.time() - (older_than_days * 86400)
cutoff_date = time.strftime("%Y-%m-%d", time.localtime(cutoff))

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

def api_call(method, endpoint, data=None, retries=3):
    url = f"{api_base}{endpoint}"
    for attempt in range(retries):
        if data:
            body = json.dumps(data).encode()
            req = urllib.request.Request(url, data=body, headers={
                "X-API-Key": api_key,
                "Content-Type": "application/json",
            }, method=method)
        else:
            req = urllib.request.Request(url, headers={"X-API-Key": api_key}, method=method)
        try:
            with urllib.request.urlopen(req, context=ctx, timeout=15) as resp:
                return json.loads(resp.read())
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < retries - 1:
                wait = (attempt + 1) * 5
                print(f"  Rate limited, waiting {wait}s (attempt {attempt+1}/{retries})...", file=sys.stderr)
                time.sleep(wait)
                continue
            return {"success": False, "error": str(e)}
        except Exception as e:
            return {"success": False, "error": str(e)}

resp = api_call("GET", f"/api/messages/{dm_channel}/history?latest={cutoff}&count=200")
if not resp.get("success"):
    print(f"  ERROR: Could not fetch DM history: {resp.get('error', 'unknown')}", file=sys.stderr)
    sys.exit(0)

messages = resp.get("data", {}).get("messages", [])
if not messages:
    print(f"  No messages older than {cutoff_date} found.", file=sys.stderr)
    sys.exit(0)

print(f"  Found {len(messages)} messages older than {cutoff_date}", file=sys.stderr)

if dry_run:
    print(f"  DRY RUN — would delete {len(messages)} messages", file=sys.stderr)
    sys.exit(0)

deleted = 0
failed = 0
for msg in messages:
    ts = msg.get("ts", "")
    if not ts:
        continue
    resp = api_call("DELETE", f"/api/messages/{dm_channel}/{ts}")
    if resp.get("success"):
        deleted += 1
    else:
        failed += 1
    time.sleep(0.3)

print(f"  Deleted: {deleted}, Failed: {failed}", file=sys.stderr)
DELETE_EOF

else
    log "Skipping DM cleanup (use --delete-old to remove old messages)"
fi

log "Done. Files in $CONSOLIDATE_DIR/"
log "  - links.md          (thread tracker with summaries)"
log "  - latest_summary.md (Claude-generated status)"

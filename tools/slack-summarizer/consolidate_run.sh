#!/usr/bin/env bash
# Enrich threads → Claude links.md → Claude summary.md → publish → optional DM cleanup
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.env"
DATA_DIR="${DATA_DIR:-$HOME/.slack_summaries_data}"

DRY_RUN=0
DELETE_OLD=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --delete-old) DELETE_OLD=1; shift ;;
        *) shift ;;
    esac
done

ENRICHED="/tmp/consolidate_enriched_$$.json"
LINKS_INPUT="/tmp/consolidate_links_$$.json"
CONSOLIDATE_DIR="$DATA_DIR/consolidated"
mkdir -p "$CONSOLIDATE_DIR"
cleanup() { rm -f "$ENRICHED" "$LINKS_INPUT"; }
trap cleanup EXIT

# 1. Enrich: scan all data + fetch fresh threads
ENRICHED_PATH=$(python3 "$SCRIPT_DIR/enrich_threads.py" "$ENRICHED")
if [[ ! -s "$ENRICHED" ]]; then
    echo "No data to consolidate" >&2
    exit 1
fi
cp "$ENRICHED" "$CONSOLIDATE_DIR/enriched.json"

# 2. Generate links.md via Claude
echo "Generating links.md..." >&2

# Prepare thread data for Claude
python3 -c "
import json, sys, re
with open(sys.argv[1]) as f: data = json.load(f)
um = data.get('user_map', {})
def ru(t): return re.sub(r'<@([A-Z0-9]+)(?:\|[^>]*)?>', lambda m: f\"@{um.get(m.group(1), m.group(1))}\", t)
threads = []
for t in data['threads']:
    topic = ru((t.get('topic','') or '').replace('\n',' ')[:400])
    replies = [f\"@{r.get('user_name','?')}: {ru((r.get('text','') or '').replace(chr(10),' ')[:200])}\" for r in t.get('latest_replies',[])[-4:]]
    threads.append({'i':len(threads),'channel':t.get('channel_name','?'),'topic':topic,'reply_count':t.get('reply_count',0),
        'last_date':t.get('last_activity_date','?'),'last_by':t.get('last_reply_by',''),
        'last_text':ru((t.get('last_reply_text','') or '').replace(chr(10),' ')[:300]),
        'recent_replies':replies,'permalink':t.get('permalink','')})
json.dump({'threads':threads,'stats':data['stats']}, open(sys.argv[2],'w'), indent=1)
print(f'  Prepared {len(threads)} threads', file=sys.stderr)
" "$ENRICHED" "$LINKS_INPUT"

LINKS_FILE="$CONSOLIDATE_DIR/links.md"

if [[ "$DRY_RUN" == "1" ]]; then
    echo "DRY RUN — would generate links.md and latest_summary.md via Claude" >&2
    exit 0
fi

{
    cat <<'LINKS_PROMPT'
You are generating a thread tracker for a manager.

For each thread, produce exactly TWO lines:
1. **{summary}** — a meaningful 1-2 line summary of WHAT this thread is about and its current state.
2. > Latest: {1-line status} — what happened most recently, in plain English.

Output format (Markdown):

# Active Threads — {today date}
_Last run: {current datetime}._

**{Meaningful summary}**
_#{channel} · {N} replies · last: {date} · by @{name}_ [view thread](permalink)
> Latest: {1 clear sentence}

Rules: NEVER copy raw text as title. Summarize meaningfully. Use @user_name. 3 lines per thread. Most recent first.
LINKS_PROMPT
    echo "---"
    cat "$LINKS_INPUT"
} | claude -p --model haiku > "$LINKS_FILE" 2>&1 || {
    echo "Claude failed for links.md, using raw fallback" >&2
    python3 -c "
import json, time, re
with open('$ENRICHED') as f: data = json.load(f)
um = data.get('user_map',{})
def ru(t): return re.sub(r'<@([A-Z0-9]+)>', lambda m: f'@{um.get(m.group(1),m.group(1))}', t)
lines = [f'# Active Threads — {time.strftime(\"%Y-%m-%d\")}','',f'_{data[\"stats\"][\"active_threads\"]} active, {data[\"stats\"][\"stale_threads\"]} pruned._','']
for t in data['threads']:
    lines.append(f'**{ru((t.get(\"topic\",\"\") or \"\")[:120])}**')
    meta = f'_#{t.get(\"channel_name\",\"?\")} · {t.get(\"reply_count\",0)} replies · last: {t.get(\"last_activity_date\",\"?\")}'
    if t.get('last_reply_by'): meta += f' · by @{t[\"last_reply_by\"]}'
    pl = t.get('permalink','')
    meta += f'_ [view thread]({pl})' if pl else '_'
    lines.append(meta); lines.append('')
print('\n'.join(lines))
" > "$LINKS_FILE"
}

# 3. Generate latest_summary.md via Claude
echo "Generating latest_summary.md..." >&2

SUMMARY_FILE="$CONSOLIDATE_DIR/latest_summary.md"
python3 -c "
import json
with open('$ENRICHED') as f: data = json.load(f)
slim = {'threads':[{'channel_name':t.get('channel_name',''),'topic':t.get('topic','')[:400],'parent_user_name':t.get('parent_user_name',''),
    'reply_count':t.get('reply_count',0),'last_activity_date':t.get('last_activity_date',''),'last_reply_by':t.get('last_reply_by',''),
    'last_reply_text':t.get('last_reply_text',''),'permalink':t.get('permalink',''),'latest_replies':t.get('latest_replies',[])} for t in data['threads']],
    'stats':data['stats']}
json.dump(slim, open('/tmp/consolidate_slim_$$.json','w'), indent=1)
"

{
    echo "You are summarizing all active Slack threads for a manager ($MY_SLACK_USER_NAME, user_id $MY_SLACK_USER_ID)."
    echo "Generate a clean Markdown summary with sections: Needs Your Action, In Progress, Recently Resolved, Watching."
    echo "Be specific: PR numbers, dates, names, decisions. Keep bullets to 1-2 lines. Skip empty sections."
    echo "---"
    cat "/tmp/consolidate_slim_$$.json"
} | claude -p --model sonnet > "$SUMMARY_FILE" 2>&1 || echo "Claude failed for latest_summary.md" >&2
rm -f "/tmp/consolidate_slim_$$.json"

# 4. Clean Slack mrkdwn
for f in "$CONSOLIDATE_DIR"/*.md; do
    [[ -f "$f" ]] && python3 "$SCRIPT_DIR/convert_mrkdwn.py" "$f" --user-map "$ENRICHED" > "/tmp/clean_$$.md" && mv "/tmp/clean_$$.md" "$f"
done

# 5. Publish
if python3 -c "from lib import publish_enabled; exit(0 if publish_enabled() else 1)" 2>/dev/null; then
    echo "Publishing..." >&2
    for pair in "links.md:slack/links-to-track.md" "latest_summary.md:slack/summaries.md"; do
        LOCAL="${pair%%:*}"
        REMOTE="${pair##*:}"
        if [[ -s "$CONSOLIDATE_DIR/$LOCAL" ]]; then
            python3 -c "
import sys
from lib import publish_write
content = open(sys.argv[1]).read()
ok = publish_write(sys.argv[2], content)
print(f'  {\"Published\" if ok else \"FAILED\"} {sys.argv[2]}', file=sys.stderr)
" "$CONSOLIDATE_DIR/$LOCAL" "$REMOTE"
        fi
    done
fi

# 6. Delete old DMs
if [[ "$DELETE_OLD" == "1" ]]; then
    echo "Deleting old DM messages (>${DELETE_OLDER_THAN_DAYS:-7} days)..." >&2
    python3 -c "
import time, sys
sys.path.insert(0, '$SCRIPT_DIR')
from lib import load_config, proxy_get, proxy_delete, log
cfg = load_config()
cutoff = time.time() - (cfg['delete_older_than_days'] * 86400)
resp = proxy_get(f'/api/messages/{cfg[\"dm_channel\"]}/history?latest={cutoff}&count=200', cfg)
if not resp.get('success'): sys.exit(0)
msgs = resp.get('data',{}).get('messages',[])
if not msgs: log('No old messages found','cleanup'); sys.exit(0)
log(f'Deleting {len(msgs)} old messages','cleanup')
d,f=0,0
for m in msgs:
    ts=m.get('ts','')
    if not ts: continue
    r=proxy_delete(f'/api/messages/{cfg[\"dm_channel\"]}/{ts}',cfg)
    if r.get('success'): d+=1
    else: f+=1
    time.sleep(0.3)
log(f'Deleted: {d}, Failed: {f}','cleanup')
"
fi

echo "Done. Files in $CONSOLIDATE_DIR/" >&2

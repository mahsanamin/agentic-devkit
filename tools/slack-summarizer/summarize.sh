#!/usr/bin/env bash
# Slim filtered JSON → Claude haiku → send DM → publish living doc
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
set -a; source "$SCRIPT_DIR/config.env"; set +a
DATA_DIR="${DATA_DIR:-$HOME/.slack_summaries_data}"

POLL_FILE="$1"
SLIM_FILE="/tmp/slack_slim_$$.json"
SUMMARY_FILE="$DATA_DIR/summaries/$(date +%Y-%m-%d)/summary_$(date +%H%M%S).md"
CONVERTED="/tmp/slack_converted_$$.md"
EXISTING="/tmp/slack_existing_$$.md"
MERGED="/tmp/slack_merged_$$.md"

cleanup() { rm -f "$SLIM_FILE" "$CONVERTED" "$EXISTING" "$MERGED"; }
trap cleanup EXIT

# 1. Slim JSON
python3 "$SCRIPT_DIR/slim_json.py" "$POLL_FILE" "$SLIM_FILE"

# 2. Claude summarizes
mkdir -p "$(dirname "$SUMMARY_FILE")"
{
    echo "The manager's Slack user_id is $MY_SLACK_USER_ID ($MY_SLACK_USER_NAME). Any message from this user_id is the manager's OWN message."
    echo ""
    tail -n +3 "$SCRIPT_DIR/system_prompt.txt"
    echo ""
    echo "---"
    echo "Here is the Slack poll JSON data. Produce the briefing:"
    echo ""
    cat "$SLIM_FILE"
} | claude -p --model haiku > "$SUMMARY_FILE" 2>"$DATA_DIR/summaries/$(date +%Y-%m-%d)/claude_err_$(date +%H%M%S).log" || {
    echo "Claude failed" >&2
    exit 1
}

# Check for empty or auth failure
if [[ ! -s "$SUMMARY_FILE" ]] || grep -qi "not logged in" "$SUMMARY_FILE" 2>/dev/null; then
    echo "Claude produced empty output or not authenticated" >&2
    rm -f "$SUMMARY_FILE"
    exit 1
fi
rm -f "$DATA_DIR/summaries/$(date +%Y-%m-%d)/claude_err_"*.log 2>/dev/null

# 3. Send to DM
python3 "$SCRIPT_DIR/send_dm.py" "$SUMMARY_FILE"

# 4. Publish living doc (convert mrkdwn → markdown, dedup, merge)
if python3 -c "from lib import publish_enabled; exit(0 if publish_enabled() else 1)" 2>/dev/null; then
    # Convert Slack mrkdwn to Markdown
    python3 "$SCRIPT_DIR/convert_mrkdwn.py" "$SUMMARY_FILE" > "$CONVERTED"

    # Normalize briefing header to a deterministic ISO date the merger can dedup on
    BRIEFING_DATE="$(date '+%Y-%m-%d %H:%M')"
    python3 -c "
import re, sys
path = sys.argv[1]
stamp = sys.argv[2]
text = open(path).read()
text = text.replace('__BRIEFING_DATE__', stamp)
text = re.sub(r'^(\U0001F4F0 \*Briefing\*)(?:[^\n]*)', r'\1 — ' + stamp, text, count=1, flags=re.MULTILINE)
open(path, 'w').write(text)
" "$CONVERTED" "$BRIEFING_DATE"

    # Read existing, merge, write
    python3 -c "from lib import publish_read; print(publish_read('slack/latest.md'), end='')" > "$EXISTING" 2>/dev/null || true
    python3 "$SCRIPT_DIR/merge_briefing.py" "$CONVERTED" "$EXISTING" "$MERGED"

    if [[ -s "$MERGED" ]]; then
        python3 -c "
import sys
from lib import publish_write
content = open(sys.argv[1]).read()
publish_write('slack/latest.md', content)
" "$MERGED" && echo "Published slack/latest.md" >&2
    fi
fi

echo "Summary: $SUMMARY_FILE" >&2

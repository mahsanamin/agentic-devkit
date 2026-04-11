#!/usr/bin/env bash
# Merge 24h data → slim → Claude haiku → optional send
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.env"
DATA_DIR="${DATA_DIR:-$HOME/.slack_summaries_data}"

NO_SEND=0
OUTPUT_PATH=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-send) NO_SEND=1; shift ;;
        --output) OUTPUT_PATH="$2"; shift 2 ;;
        *) shift ;;
    esac
done

COMBINED="/tmp/slack_report_combined_$$.json"
SLIM_FILE="/tmp/slack_report_slim_$$.json"
cleanup() { rm -f "$COMBINED" "$SLIM_FILE"; }
trap cleanup EXIT

# 1. Merge 24h filtered data
MERGED_PATH=$(python3 "$SCRIPT_DIR/merge_report.py" "$COMBINED")
if [[ -z "$MERGED_PATH" || ! -s "$COMBINED" ]]; then
    echo "No data to report" >&2
    exit 0
fi

# 2. Slim for Claude
python3 "$SCRIPT_DIR/slim_json.py" "$COMBINED" "$SLIM_FILE"

# 3. Determine output path
if [[ -n "$OUTPUT_PATH" ]]; then
    [[ "$OUTPUT_PATH" != *.md ]] && OUTPUT_PATH="${OUTPUT_PATH}.md"
    mkdir -p "$(dirname "$OUTPUT_PATH")"
    REPORT_FILE="$OUTPUT_PATH"
else
    REPORT_DIR="$DATA_DIR/summaries/$(date +%Y-%m-%d)"
    mkdir -p "$REPORT_DIR"
    REPORT_FILE="$REPORT_DIR/daily_report.md"
fi

# 4. Claude generates report
{
    cat "$SCRIPT_DIR/report_prompt.txt"
    echo ""
    echo "---"
    echo "Here is the aggregated Slack data. Produce the daily report:"
    echo ""
    cat "$SLIM_FILE"
} | claude -p --model haiku > "$REPORT_FILE" 2>&1

echo "Report: $REPORT_FILE" >&2

# 5. Optional send
if [[ "$NO_SEND" == "0" ]]; then
    python3 "$SCRIPT_DIR/send_dm.py" "$REPORT_FILE"
fi

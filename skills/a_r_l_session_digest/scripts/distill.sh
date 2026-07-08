#!/usr/bin/env bash
# distill.sh <transcript.jsonl> — compress one Claude session transcript into a
# small, summarizer-friendly markdown artifact: the real intent, the arc of user
# asks, files edited, tool usage, notable git/PR actions, and the final notes.
# Deterministic, read-only, no network. Output goes to stdout (a few KB), small
# enough to hand straight to a subagent.
#
# Env knobs: MAX_ASKS (default 12), MAX_FILES (default 40)
set -u

TP="${1:?usage: distill.sh <transcript.jsonl>}"
[ -f "$TP" ] || { echo "transcript not found: $TP" >&2; exit 1; }
JQ_BIN="$(command -v jq || echo /usr/bin/jq)"
MAX_ASKS="${MAX_ASKS:-12}"
MAX_FILES="${MAX_FILES:-40}"

LIB="${CATALOG_LIB:-$HOME/.claude/scripts/session-catalog/catalog-lib.sh}"
# shellcheck source=/dev/null
[ -f "$LIB" ] && . "$LIB"

sid="$(basename "$TP" .jsonl)"
cwd="$("$JQ_BIN" -rR 'fromjson? | select(.cwd) | .cwd' "$TP" 2>/dev/null | head -1)"
[ -z "$cwd" ] && cwd="unknown"
if command -v repo_label >/dev/null 2>&1; then proj="$(repo_label "$cwd")"; else proj="$(basename "$cwd")"; fi
started="$(head -200 "$TP" | "$JQ_BIN" -rR 'fromjson? | select(.timestamp) | .timestamp' 2>/dev/null | head -1)"
ended="$(tail -200 "$TP" | "$JQ_BIN" -rR 'fromjson? | select(.timestamp) | .timestamp' 2>/dev/null | tail -1)"
uturns="$(grep -c '"type":"user"' "$TP" 2>/dev/null || echo 0)"
aturns="$(grep -c '"type":"assistant"' "$TP" 2>/dev/null || echo 0)"

# unwrap a raw user-text line down to its real instruction (or empty to skip)
clean_ask() {
  local c="$1"
  case "$c" in
    *"<command-args>"*)        c="${c#*<command-args>}"; c="${c%%</command-args>*}" ;;
    *"<local-command-stdout>"*) c="${c#*<local-command-stdout>}"; c="${c%%</local-command-stdout>*}"; c="${c#Goal set: }"; c="${c#Loop started: }" ;;
  esac
  c="$(printf '%s' "$c" | sed -E 's/<[^>]+>//g; s/^[[:space:]]+//; s/[[:space:]]+$//')"
  case "$c" in
    ""|goal|loop|compact|clear|resume) return ;;
    "Caveat:"*|"This session is being continued"*|"[Request interrupted"*) return ;;
  esac
  printf '%s' "$c"
}

asks_raw="$("$JQ_BIN" -rR '
  fromjson? | select(.type=="user" and (.isMeta!=true))
  | (.message.content) as $c
  | ( if ($c|type)=="string" then $c
      elif ($c|type)=="array" then ([ $c[]? | select(.type=="text") | .text ] | join(" "))
      else "" end )
  | gsub("[\n\r\t]+";" ") | gsub("  +";" ") | select(length>0)
' "$TP" 2>/dev/null)"

files="$("$JQ_BIN" -rR 'fromjson? | select(.type=="assistant") | .message.content[]?
  | select(.type=="tool_use" and (.name|test("^(Edit|Write|MultiEdit|NotebookEdit)$")))
  | (.input.file_path // .input.notebook_path // empty)' "$TP" 2>/dev/null | sort | uniq -c | sort -rn)"
files_n="$(printf '%s' "$files" | grep -c . 2>/dev/null)"; files_n="${files_n:-0}"

tools="$("$JQ_BIN" -rR 'fromjson? | select(.type=="assistant") | .message.content[]?
  | select(.type=="tool_use") | .name' "$TP" 2>/dev/null | sort | uniq -c | sort -rn | head -12)"

bashcmds="$("$JQ_BIN" -rR 'fromjson? | select(.type=="assistant") | .message.content[]?
  | select(.type=="tool_use" and .name=="Bash") | .input.command' "$TP" 2>/dev/null)"
notable="$(printf '%s\n' "$bashcmds" | grep -oE '(gh pr (create|merge|ready)[^"]*|git commit -m [^"]*|git push[^"]*|git checkout -b [^"]*)' 2>/dev/null | cut -c1-160 | head -15)"

finals="$("$JQ_BIN" -rR 'fromjson? | select(.type=="assistant") | .message.content[]?
  | select(.type=="text") | .text' "$TP" 2>/dev/null | grep -v '^$' | tail -3)"

# ---------------------------------------------------------------- emit
echo "# Session distillation: ${sid}"
echo
echo "- project: ${proj}"
echo "- cwd: ${cwd}"
echo "- started: ${started:-?}"
echo "- last activity: ${ended:-?}"
echo "- userTurns: ${uturns} ; assistantTurns: ${aturns} ; filesEdited: ${files_n}"
echo

echo "## Intent (first real prompt)"
echo
first=""
while IFS= read -r line; do ca="$(clean_ask "$line")"; [ -n "$ca" ] && { first="$ca"; break; }; done <<EOF
$asks_raw
EOF
echo "${first:-(none captured)}"
echo

echo "## User asks (chronological, deduped)"
echo
n=0; prev=""
while IFS= read -r line; do
  ca="$(clean_ask "$line")"; [ -z "$ca" ] && continue
  short="$(printf '%s' "$ca" | cut -c1-220)"
  [ "$short" = "$prev" ] && continue
  prev="$short"; echo "- ${short}"
  n=$((n+1)); [ "$n" -ge "$MAX_ASKS" ] && break
done <<EOF
$asks_raw
EOF
echo

echo "## Files edited (by frequency)"
echo
if [ "$files_n" -gt 0 ]; then printf '%s\n' "$files" | head -"$MAX_FILES" | sed -E 's/^ *([0-9]+) /- \1x /'; else echo "(none)"; fi
echo

echo "## Tool usage"
echo
printf '%s\n' "$tools" | sed -E 's/^ *([0-9]+) /- \1x /'
echo

echo "## Notable git / PR actions"
echo
if [ -n "$notable" ]; then printf '%s\n' "$notable" | sed 's/^/- /'; else echo "(none detected)"; fi
echo

echo "## Final assistant notes (verbatim tail)"
echo
printf '%s\n' "$finals" | cut -c1-700 | sed -E 's/^/> /'

#!/usr/bin/env bash
# compose-entry.sh <transcript.jsonl> <summary.json> [digested-date]
# Emit a complete enriched catalog entry (markdown) to stdout: deterministic
# signals pulled from the transcript + the narrative from the subagent summary
# JSON. Keeps scheduled/autonomous runs consistent instead of hand-composing.
#
# summary.json must have: headline, summary, whatHappened[], codePaths, outcome, tags[]
set -u

TP="${1:?usage: compose-entry.sh <transcript> <summary.json> [date]}"
SUMJSON="${2:?usage: compose-entry.sh <transcript> <summary.json> [date]}"
DIGESTED="${3:-$(date -u +%Y-%m-%d)}"
JQ_BIN="$(command -v jq || echo /usr/bin/jq)"
[ -f "$TP" ] || { echo "transcript not found: $TP" >&2; exit 1; }
[ -f "$SUMJSON" ] || { echo "summary json not found: $SUMJSON" >&2; exit 1; }

LIB="${CATALOG_LIB:-$HOME/.claude/scripts/session-catalog/catalog-lib.sh}"
# shellcheck source=/dev/null
[ -f "$LIB" ] && . "$LIB"

sid="$(basename "$TP" .jsonl)"
cwd="$("$JQ_BIN" -rR 'fromjson? | select(.cwd) | .cwd' "$TP" 2>/dev/null | head -1)"; [ -z "$cwd" ] && cwd="unknown"
if command -v repo_label >/dev/null 2>&1; then proj="$(repo_label "$cwd")"; else proj="$(basename "$cwd")"; proj="$(printf '%s' "$proj" | tr ' /' '__' | tr -cd '[:alnum:]._-')"; fi
[ -z "$proj" ] && proj="unknown"
host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
branch=""
if command -v git >/dev/null 2>&1 && [ -d "$cwd" ]; then
  branch="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  [ "$branch" = "HEAD" ] && branch="detached@$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)"
fi
started="$(head -200 "$TP" | "$JQ_BIN" -rR 'fromjson? | select(.timestamp) | .timestamp' 2>/dev/null | head -1)"
ended="$(tail -300 "$TP" | "$JQ_BIN" -rR 'fromjson? | select(.timestamp) | .timestamp' 2>/dev/null | tail -1)"
started="${started:0:10}"; ended="${ended:0:10}"   # date only, keep it lean
turns="$(grep -c '"type":"user"' "$TP" 2>/dev/null || echo 0)"
files="$("$JQ_BIN" -rR 'fromjson? | select(.type=="assistant") | .message.content[]?
  | select(.type=="tool_use" and (.name|test("^(Edit|Write|MultiEdit|NotebookEdit)$")))
  | (.input.file_path // .input.notebook_path // empty)' "$TP" 2>/dev/null | sort -u)"
files_n="$(printf '%s' "$files" | grep -c . 2>/dev/null)"; files_n="${files_n:-0}"
top_tools="$("$JQ_BIN" -rR 'fromjson? | select(.type=="assistant") | .message.content[]?
  | select(.type=="tool_use") | .name' "$TP" 2>/dev/null | sort | uniq -c | sort -rn | head -6 | awk '{printf "%s(%s) ", $2, $1}' | sed 's/ *$//')"

# first real prompt (unwrap slash-command wrappers)
intent=""
while IFS= read -r cand; do
  [ -z "$cand" ] && continue
  c="$cand"
  case "$c" in
    *"<command-args>"*) c="${c#*<command-args>}"; c="${c%%</command-args>*}" ;;
    *"<local-command-stdout>"*) c="${c#*<local-command-stdout>}"; c="${c%%</local-command-stdout>*}"; c="${c#Goal set: }"; c="${c#Loop started: }" ;;
  esac
  c="$(printf '%s' "$c" | sed -E 's/<[^>]+>//g; s/^[[:space:]]+//; s/[[:space:]]+$//')"
  case "$c" in ""|goal|loop|compact|clear|resume) continue ;; "Caveat:"*|"This session is being continued"*|"[Request interrupted"*) continue ;; esac
  intent="$c"; break
done < <(head -300 "$TP" | "$JQ_BIN" -rR 'fromjson? | select(.type=="user" and (.isMeta!=true)) | (.message.content) as $c | ( if ($c|type)=="string" then $c elif ($c|type)=="array" then ([ $c[]? | select(.type=="text") | .text ] | join(" ")) else "" end ) | gsub("[\n\r\t]+";" ") | gsub("  +";" ") | select(length>0)' 2>/dev/null)
[ -z "$intent" ] && intent="(no prompt captured)"

# summary fields
headline="$("$JQ_BIN" -r '.headline // empty' "$SUMJSON" 2>/dev/null)"; [ -z "$headline" ] && headline="Session ${sid:0:8}"
summary="$("$JQ_BIN" -r '.summary // empty' "$SUMJSON" 2>/dev/null | tr '\n' ' ' | sed -E 's/  +/ /g')"
codePaths="$("$JQ_BIN" -r '.codePaths // empty' "$SUMJSON" 2>/dev/null)"
outcome="$("$JQ_BIN" -r '.outcome // "unknown"' "$SUMJSON" 2>/dev/null)"
outcome_kind="$(printf '%s' "${outcome%%:*}" | tr -d ' ')"
tags="$("$JQ_BIN" -r 'if (.tags|type)=="array" then (.tags|join(", ")) else (.tags // "") end' "$SUMJSON" 2>/dev/null)"

outcome_note="${outcome#*: }"; [ "$outcome_note" = "$outcome" ] && outcome_note=""

# ---------------------------------------------------------------- emit
# Lean entry: tiny frontmatter (so SilverBullet's frontmatter block stays
# small), then the name + summary as the first visible content, then a compact
# fact line and the resume command. No walls of YAML.
echo "---"
echo "project: ${proj}"
echo "outcome: ${outcome_kind:-unknown}"
echo "digested: ${DIGESTED}"
[ -n "$tags" ] && echo "tags: [${tags}]"
echo "---"
echo
echo "# ${headline}"
echo
echo "${summary:-(no summary)}"
echo
echo "\`claude --resume ${sid}\`"
echo
echo "- ${proj}${branch:+ · \`${branch}\`} · ${turns} turns · ${files_n} files · ${started:-?} -> ${ended:-?}"
[ -n "$outcome_note" ] && echo "- outcome: ${outcome_note}"
[ -n "$top_tools" ] && echo "- tools: ${top_tools}"
echo "- dir: \`${cwd}\`"
echo
echo "## What happened"
echo
"$JQ_BIN" -r 'if (.whatHappened|type)=="array" then (.whatHappened[]) else (.whatHappened // empty) end' "$SUMJSON" 2>/dev/null | sed 's/^/- /'
echo
echo "## Code paths"
echo
echo "${codePaths:-(unknown)}"
if [ "$files_n" -gt 0 ]; then
  echo
  echo "## Files edited"
  echo
  printf '%s\n' "$files" | head -20 | sed 's/^/- `/; s/$/`/'
fi

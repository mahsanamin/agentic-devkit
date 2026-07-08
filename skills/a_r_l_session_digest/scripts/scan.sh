#!/usr/bin/env bash
# scan.sh — enumerate Claude Code sessions that are CLOSED (no live process,
# inactive past a short grace) or STALE (transcript untouched past STALE_DAYS),
# skipping ones already digested. Emits one JSON object per line (JSONL) for the
# orchestrator to consume. Deterministic, read-only, no network.
#
# Env knobs (all optional):
#   STALE_DAYS   default 7    untouched longer than this -> stale
#   GRACE_MIN    default 30   a non-live session must be inactive this long to
#                             count as "closed" (avoids grabbing a paused one)
#   MAX          default 30   cap number of candidates emitted (newest first)
#   PROJECT_FILTER (or $1)    only sessions whose cwd/project contains this substring
#   PROJECTS_ROOT default ~/.claude/projects
#   LIVE_DIR      default ~/.claude/sessions
#   STATE_FILE    default ~/.claude/scripts/session-catalog/digested.tsv
set -u

STALE_DAYS="${STALE_DAYS:-7}"
GRACE_MIN="${GRACE_MIN:-30}"
MAX="${MAX:-30}"
MIN_TURNS="${MIN_TURNS:-0}"   # skip sessions with fewer than this many user turns (0 = no filter)
PROJECTS_ROOT="${PROJECTS_ROOT:-$HOME/.claude/projects}"
LIVE_DIR="${LIVE_DIR:-$HOME/.claude/sessions}"
STATE_FILE="${STATE_FILE:-$HOME/.claude/scripts/session-catalog/digested.tsv}"
FILTER="${1:-${PROJECT_FILTER:-}}"
JQ_BIN="$(command -v jq || echo /usr/bin/jq)"

# scope filter + repo label (shared with the hook). Absent -> degrade to
# basename labels and no scope filtering, so this stays portable.
LIB="${CATALOG_LIB:-$HOME/.claude/scripts/session-catalog/catalog-lib.sh}"
# shellcheck source=/dev/null
[ -f "$LIB" ] && . "$LIB"

now_epoch="$(date +%s)"

# epoch mtime, portable across macOS (stat -f) and Linux (stat -c)
mtime_of() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null; }
iso_of()   { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null; }

# --- set of sessionIds whose owning process is still alive -------------------
live_ids=" "
if [ -d "$LIVE_DIR" ]; then
  for f in "$LIVE_DIR"/*.json; do
    [ -f "$f" ] || continue
    row="$("$JQ_BIN" -r '[.sessionId, (.pid|tostring)] | @tsv' "$f" 2>/dev/null)"
    s="${row%%	*}"; p="${row##*	}"
    [ -z "$s" ] && continue
    if [ -n "$p" ] && [ "$p" != "null" ] && kill -0 "$p" 2>/dev/null; then
      live_ids="${live_ids}${s} "
    fi
  done
fi

is_digested() { # sid mtime
  [ -f "$STATE_FILE" ] || return 1
  grep -qF "$1	$2" "$STATE_FILE" 2>/dev/null
}

emit=0
while IFS= read -r tp; do
  [ -z "$tp" ] && continue
  sid="$(basename "$tp" .jsonl)"
  case "$live_ids" in *" $sid "*) continue ;; esac      # skip live sessions

  mtime="$(mtime_of "$tp")"; [ -z "$mtime" ] && continue
  age_sec=$((now_epoch - mtime)); age_min=$((age_sec / 60)); age_days=$((age_sec / 86400))

  closed=0; stale=0
  [ "$age_min" -ge "$GRACE_MIN" ] && closed=1
  [ "$age_days" -ge "$STALE_DAYS" ] && stale=1
  [ "$closed" -eq 0 ] && [ "$stale" -eq 0 ] && continue
  is_digested "$sid" "$mtime" && continue

  if [ "$MIN_TURNS" -gt 0 ]; then
    ut="$(grep -c '"type":"user"' "$tp" 2>/dev/null || echo 0)"
    [ "${ut:-0}" -lt "$MIN_TURNS" ] && continue
  fi

  cwd="$("$JQ_BIN" -rR 'fromjson? | select(.cwd) | .cwd' "$tp" 2>/dev/null | head -1)"
  [ -z "$cwd" ] && cwd="unknown"

  # scope: only catalog sessions under a catalog root (cd_w by default)
  if command -v in_catalog_scope >/dev/null 2>&1; then
    in_catalog_scope "$cwd" || continue
    proj="$(repo_label "$cwd")"
  else
    proj="$(basename "$cwd")"; proj="$(printf '%s' "$proj" | tr ' /' '__' | tr -cd '[:alnum:]._-')"
  fi
  [ -z "$proj" ] && proj="unknown"

  if [ -n "$FILTER" ]; then case "$cwd|$proj" in *"$FILTER"*) ;; *) continue ;; esac; fi

  state="stale-and-closed"
  { [ "$stale" -eq 1 ] && [ "$closed" -eq 0 ]; } && state="stale"
  { [ "$closed" -eq 1 ] && [ "$stale" -eq 0 ]; } && state="closed"

  "$JQ_BIN" -nc \
    --arg sessionId "$sid" --arg project "$proj" --arg cwd "$cwd" \
    --arg transcript "$tp" --arg lastTouched "$(iso_of "$mtime")" \
    --arg mtimeEpoch "$mtime" --argjson ageDays "$age_days" --arg state "$state" \
    '{sessionId:$sessionId, project:$project, cwd:$cwd, transcript:$transcript, lastTouched:$lastTouched, mtimeEpoch:$mtimeEpoch, ageDays:$ageDays, state:$state}'

  emit=$((emit + 1))
  [ "$emit" -ge "$MAX" ] && break
done < <(ls -t "$PROJECTS_ROOT"/*/*.jsonl 2>/dev/null)

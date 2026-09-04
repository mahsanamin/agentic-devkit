#!/bin/bash
# a_s_task_common.sh - shared helpers for the a_c_task_* commands.
#
# This file is a LIBRARY. It is sourced by a_c_task_start / a_c_task_resume /
# a_c_task_list / a_c_task_finish; it is not meant to be run on its own. Every
# function is prefixed a_task_ and is safe to redefine on each source.
#
# It is sourced into the user's (zsh) interactive shell, so the code is written
# to work under both bash and zsh: no ${!arr[@]}, no $BASH_REMATCH, no `read -p`,
# no `set -e` (those leak into / misbehave in the calling shell).
#
# State lives in a tiny registry - one row per ACTIVE task:
#   $A_TASK_HOME/tasks.tsv          (default A_TASK_HOME = ~/.a_tasks)
#   columns (tab-separated): ticket  branch  mode  repo  worktree  created

# Matrix theme: green-on-black "hacker" palette. The variable NAMES are kept
# (RED/GREEN/YELLOW/BLUE/DIM) so every a_c_task_* message re-themes for free;
# only their meaning changes to a shade of green that still reads at a glance:
#   GREEN  bold bright green  - success / highlights (✓, "current =>")
#   YELLOW bright green       - warnings (distinct from success: not bold)
#   BLUE   plain green        - headers / info ("Starting task", "Pick a repo")
#   DIM    dim green          - secondary text, paths, hints
#   RED    reverse green      - errors, shown as a green badge so they still pop
# Colors are emitted only for an interactive terminal (and honour NO_COLOR), so
# piped / scripted output stays clean.
if { [ -t 1 ] || [ -t 2 ]; } && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
    A_T_RED='\033[1;7;32m'; A_T_GREEN='\033[1;92m'; A_T_YELLOW='\033[0;92m'
    A_T_BLUE='\033[0;32m';  A_T_DIM='\033[2;32m';   A_T_NC='\033[0m'
else
    A_T_RED=''; A_T_GREEN=''; A_T_YELLOW=''; A_T_BLUE=''; A_T_DIM=''; A_T_NC=''
fi

# Where this repo's worktree helper scripts (a_g_worktree_init /
# a_g_worktree_remove) live. They ship in this repo's own scripts/ dir and are on
# PATH once the profile is sourced; resolve the dir explicitly (from the workflow
# root the caller already established) so the task commands work even when run by
# absolute path before PATH is set. Override with A_TASK_WT_DIR if they live
# elsewhere.
A_TASK_WT_DIR="${A_TASK_WT_DIR:-${A_C_TASK_BASE:-${A_C_WORKFLOW_DIR:-${MY_WORKFLOW_DIR:-}}}/scripts}"

# Default Jira project key, used when the user types a bare ticket number.
A_TASK_DEFAULT_KEY="${A_TASK_DEFAULT_KEY:-WU}"

# Matrix "digital rain" splash for a_c_task_start. Delegates to the standalone
# bash script scripts/a_s_task_fx, run as its OWN process so the bash-only
# animation can never disturb the caller's (zsh) shell. No-ops unless stdout is
# a TTY; disable with A_T_NO_FX=1. Optional $1 is a label (the ticket) to flash.
a_task_matrix_fx() {
    [ -t 1 ] || return 0
    [ -n "${A_T_NO_FX:-}" ] && return 0
    local base fx
    base="${A_C_TASK_BASE:-${A_C_WORKFLOW_DIR:-${MY_WORKFLOW_DIR:-}}}"
    fx="$base/scripts/a_s_task_fx"
    [ -f "$fx" ] && bash "$fx" "${1:-}"
    return 0
}

# ---------------------------------------------------------------- registry ---

a_task_home() {
    local home="${A_TASK_HOME:-$HOME/.a_tasks}"
    mkdir -p "$home" 2>/dev/null
    printf '%s' "$home"
}

# Ensure the registry exists (with a header) and echo its path.
a_task_registry() {
    local f; f="$(a_task_home)/tasks.tsv"
    if [ ! -f "$f" ]; then
        {
            printf '# a_c_task registry - one active task per row. Managed by a_c_task_*.\n'
            printf '# ticket\tbranch\tmode\trepo\tworktree\tcreated\n'
        } > "$f"
    fi
    printf '%s' "$f"
}

# Echo data rows only (skip comments and blank lines).
a_task_records() {
    grep -v -e '^#' -e '^[[:space:]]*$' "$(a_task_registry)" 2>/dev/null
}

# Return 0 if a row with this branch already exists.
a_task_has_branch() {
    a_task_records | awk -F'\t' -v b="$1" '$2==b{f=1} END{exit !f}'
}

# Append a row. Args: ticket branch mode repo worktree
a_task_record_add() {
    local f created
    f="$(a_task_registry)"
    created="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$created" >> "$f"
}

# Drop every row whose branch (column 2) matches, keep comments.
a_task_record_remove_by_branch() {
    local f tmp
    f="$(a_task_registry)"; tmp="${f}.tmp.$$"
    awk -F'\t' -v b="$1" '/^#/ || $2!=b' "$f" > "$tmp" && mv "$tmp" "$f"
}

# Echo the first record matching a key against ticket (col 1) OR branch (col 2).
a_task_find() {
    a_task_records | awk -F'\t' -v k="$1" '$1==k || $2==k {print; exit}'
}

# -------------------------------------------------------- naming helpers ---

# Slugify free text into a branch-safe segment: lowercase, non-alnum -> single
# dash, trimmed. e.g. "Add  Login Page!" -> "add-login-page"
a_task_slug() {
    printf '%s' "$*" | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

# Normalize a ticket id into "KEY-NUM". Accepts a bare number ("123" -> PROJ-123),
# "PROJ-123" / "wu123" / "WU123", or a pasted Jira URL such as
# https://your-org.atlassian.net/browse/PROJ-1009 (and with ?query/#fragment).
# Echoes "KEY-NUM" or fails (rc 1).
a_task_norm_ticket() {
    local raw defkey cand key num
    raw="$(printf '%s' "$1" | tr -d '[:space:]')"
    [ -z "$raw" ] && return 1
    defkey="$(printf '%s' "${2:-$A_TASK_DEFAULT_KEY}" | tr '[:lower:]' '[:upper:]')"

    # bare number -> default project key
    case "$raw" in
        ''|*[!0-9]*) : ;;
        *) printf '%s-%s' "$defkey" "$raw"; return 0 ;;
    esac

    # Pull an embedded KEY-NUM token out (e.g. from a pasted Jira URL). The LAST
    # match wins, so a host like foo-2.example.com can't shadow .../browse/PROJ-9.
    # If there is no dashed token, treat the whole input as the candidate (so
    # "WU123" without a dash still works via the optional-dash regex below).
    cand="$(printf '%s' "$raw" | grep -oE '[A-Za-z]{1,15}-[0-9]+' | tail -1)"
    [ -z "$cand" ] && cand="$raw"

    # When the pattern does not match, sed leaves the string unchanged, so an
    # extracted part equal to the whole candidate means "no match".
    key="$(printf '%s' "$cand" | sed -E 's/^([A-Za-z]+)-?([0-9]+)$/\1/')"
    num="$(printf '%s' "$cand" | sed -E 's/^([A-Za-z]+)-?([0-9]+)$/\2/')"
    if [ -n "$key" ] && [ -n "$num" ] && [ "$key" != "$cand" ] && [ "$num" != "$cand" ]; then
        printf '%s-%s' "$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')" "$num"
        return 0
    fi
    # Free-form task id for NON-Jira sources (mdnest notes, ad-hoc tasks). Off by
    # default so the interactive Jira prompt still rejects typos and re-asks; a
    # front that legitimately has no Jira key sets A_TASK_FREEFORM_TICKET=1 and we
    # accept a clean slug as the branch id verbatim.
    if [ "${A_TASK_FREEFORM_TICKET:-0}" = "1" ]; then
        local ff
        ff="$(printf '%s' "$raw" | sed -E 's/[^A-Za-z0-9._-]+/-/g; s/^-+//; s/-+$//')"
        [ -n "$ff" ] && { printf '%s' "$ff"; return 0; }
    fi
    return 1
}

# Fetch a Jira issue's summary (title) for <key>, to pre-fill a feature name.
# Reads A_JIRA_EMAIL + A_JIRA_TOKEN (a Jira API token) and A_JIRA_BASE (default
# https://your-org.atlassian.net) from the environment - put them in
# ~/.my_secrets. Echoes the summary on success; returns non-zero SILENTLY when
# unconfigured, offline, or the issue is not found, so the caller just falls
# back to a manual prompt. The token is passed via curl -K - (stdin), never on
# the command line, so it does not leak into `ps`.
a_task_jira_summary() {
    local key="$1" base json summary
    [ -n "$key" ] || return 1
    [ -n "${A_JIRA_EMAIL:-}" ] && [ -n "${A_JIRA_TOKEN:-}" ] || return 1
    command -v curl >/dev/null 2>&1 || return 1
    base="${A_JIRA_BASE:-https://your-org.atlassian.net}"

    json="$(printf 'user = "%s:%s"\n' "$A_JIRA_EMAIL" "$A_JIRA_TOKEN" \
        | curl -fsS --max-time 8 -K - -H 'Accept: application/json' \
            "$base/rest/api/3/issue/$key?fields=summary" 2>/dev/null)" || return 1
    [ -n "$json" ] || return 1

    summary=""
    if command -v jq >/dev/null 2>&1; then
        summary="$(printf '%s' "$json" | jq -r '.fields.summary // empty' 2>/dev/null)"
    fi
    if [ -z "$summary" ] && command -v python3 >/dev/null 2>&1; then
        summary="$(printf '%s' "$json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("fields",{}).get("summary",""))' 2>/dev/null)"
    fi
    if [ -z "$summary" ]; then
        summary="$(printf '%s' "$json" | sed -n 's/.*"summary"[[:space:]]*:[[:space:]]*"\(\([^"\\]\|\\.\)*\)".*/\1/p' | head -1)"
    fi
    [ -n "$summary" ] || return 1
    printf '%s' "$summary"
}

# Fetch a Jira issue's type name (e.g. "Bug", "Story", "Task") for <key>, used to
# choose the branch prefix. Same creds and behavior as a_task_jira_summary:
# returns non-zero SILENTLY when unconfigured, offline, or not found, so the
# caller falls back to the default prefix. Echoes the raw type name on success.
a_task_jira_issuetype() {
    local key="$1" base json itype
    [ -n "$key" ] || return 1
    [ -n "${A_JIRA_EMAIL:-}" ] && [ -n "${A_JIRA_TOKEN:-}" ] || return 1
    command -v curl >/dev/null 2>&1 || return 1
    base="${A_JIRA_BASE:-https://your-org.atlassian.net}"

    json="$(printf 'user = "%s:%s"\n' "$A_JIRA_EMAIL" "$A_JIRA_TOKEN" \
        | curl -fsS --max-time 8 -K - -H 'Accept: application/json' \
            "$base/rest/api/3/issue/$key?fields=issuetype" 2>/dev/null)" || return 1
    [ -n "$json" ] || return 1

    itype=""
    if command -v jq >/dev/null 2>&1; then
        itype="$(printf '%s' "$json" | jq -r '.fields.issuetype.name // empty' 2>/dev/null)"
    fi
    if [ -z "$itype" ] && command -v python3 >/dev/null 2>&1; then
        itype="$(printf '%s' "$json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("fields",{}).get("issuetype",{}).get("name",""))' 2>/dev/null)"
    fi
    if [ -z "$itype" ]; then
        itype="$(printf '%s' "$json" | sed -n 's/.*"issuetype"[^}]*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    fi
    [ -n "$itype" ] || return 1
    printf '%s' "$itype"
}

# Map a Jira issue-type name to a branch prefix. Bugs/defects/incidents get
# "hotfix"; everything else (story, task, improvement, ...) gets "feature".
# Empty or unknown input -> "feature". Case-insensitive.
a_task_branch_type() {
    local t; t="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$t" in
        *bug*|*defect*|*incident*|*hotfix*|*fault*) printf 'hotfix' ;;
        *)                                          printf 'feature' ;;
    esac
}

# Compose a task branch name from a ticket id, a (possibly empty) feature slug,
# and a branch type/prefix. Format: <prefix>/<lowercased-ticket>[-<slug>].
#   a_task_branch_name US-1078 some-name feature -> feature/us-1078-some-name
#   a_task_branch_name US-1078 ""        hotfix  -> hotfix/us-1078
a_task_branch_name() {
    local ticket="$1" slug="$2" prefix="${3:-feature}" lt
    lt="$(printf '%s' "$ticket" | tr '[:upper:]' '[:lower:]')"
    if [ -n "$slug" ]; then printf '%s/%s-%s' "$prefix" "$lt" "$slug"
    else printf '%s/%s' "$prefix" "$lt"; fi
}

# ------------------------------------------------------ repo discovery ---

# Echo up to <count> git-repo dirs directly under <base>, most-recently-ACTIVE
# first. Recency = the last commit's date (what you actually worked on), NOT the
# clone/birth time - a repo cloned long ago but committed to today should rank
# above one freshly cloned and never touched. Repos with no commits fall back to
# directory mtime. One absolute path per line.
a_task_discover_repos() {
    local base="$1" count="${2:-5}" use_bsd=0 d epoch
    [ -d "$base" ] || return 0
    stat -f '%m' "$base" >/dev/null 2>&1 && use_bsd=1
    while IFS= read -r d; do
        [ -e "$d/.git" ] || continue
        epoch="$(git -C "$d" log -1 --format=%ct 2>/dev/null)"
        if [ -z "$epoch" ]; then
            if [ "$use_bsd" = 1 ]; then epoch="$(stat -f '%m' "$d" 2>/dev/null)"
            else epoch="$(stat -c '%Y' "$d" 2>/dev/null)"; fi
        fi
        [ -z "$epoch" ] && epoch=0
        printf '%s\t%s\n' "$epoch" "$d"
    done < <(find "$base" -mindepth 1 -maxdepth 1 -type d 2>/dev/null) \
        | sort -rn | head -n "$count" | cut -f2-
}

# Echo the MAIN repo root of the current directory if inside a git repo (the
# main checkout even when standing in a linked worktree); empty otherwise.
a_task_current_repo() {
    git rev-parse --git-dir >/dev/null 2>&1 || return 0
    local common main_root
    common="$(git rev-parse --git-common-dir 2>/dev/null)" || return 0
    main_root="$(cd "$(dirname "$common")" 2>/dev/null && pwd)" || return 0
    printf '%s' "$main_root"
}

# Echo the ordered picker candidates: the current repo first (if any), then the
# most-recently-active repos under <base>, with the current repo filtered out of
# the recent list so it is never shown twice. One absolute path per line.
a_task_candidate_repos() {
    local base="$1" count="${2:-5}" cur d
    cur="$(a_task_current_repo)"
    [ -n "$cur" ] && printf '%s\n' "$cur"
    a_task_discover_repos "$base" $((count + 1)) | while IFS= read -r d; do
        [ "$d" = "$cur" ] && continue
        printf '%s\n' "$d"
    done | head -n "$count"
}

# Resolve a repo from a user token: a menu number (Nth of the picker list), an
# absolute/~/relative path, an exact dir name under <base>, or a unique
# case-insensitive substring match under <base>. Echoes the absolute path.
a_task_resolve_repo() {
    local arg="$1" base="$2" cand matches n
    [ -z "$arg" ] && return 1

    # menu number -> Nth of the candidate list (current repo + recent)
    case "$arg" in
        ''|*[!0-9]*) : ;;
        *) cand="$(a_task_candidate_repos "$base" 5 | sed -n "${arg}p")"
           [ -n "$cand" ] && { printf '%s' "$cand"; return 0; }
           return 1 ;;
    esac

    case "$arg" in "~"/*) arg="$HOME/${arg#~/}" ;; esac

    [ -d "$arg" ] && { ( cd "$arg" && pwd ); return 0; }
    [ -n "$base" ] && [ -d "$base/$arg" ] && { ( cd "$base/$arg" && pwd ); return 0; }

    if [ -n "$base" ]; then
        matches="$(find "$base" -mindepth 1 -maxdepth 1 -type d -iname "*$arg*" 2>/dev/null \
            | while IFS= read -r d; do [ -e "$d/.git" ] && printf '%s\n' "$d"; done)"
        n="$(printf '%s' "$matches" | grep -c .)"
        if [ "$n" -eq 1 ]; then ( cd "$matches" && pwd ); return 0; fi
        if [ "$n" -gt 1 ]; then
            echo -e "${A_T_YELLOW}Multiple repos match '$arg':${A_T_NC}" >&2
            printf '%s\n' "$matches" | sed 's/^/  /' >&2
            return 1
        fi
    fi
    return 1
}

# Interactive repo picker. Pins the current repo first (marked "current =>"),
# then lists the most-recently-active repos under <base>; accepts a number /
# name / path and sets the global A_TASK_PICKED to the absolute path.
a_task_pick_repo() {
    local base="$1" candidates cur choice repo n line label
    A_TASK_PICKED=""
    cur="$(a_task_current_repo)"
    candidates="$(a_task_candidate_repos "$base" 5)"

    if [ -z "$candidates" ]; then
        echo -e "${A_T_YELLOW}No git repos under ${base:-<\$a_dir_w_repos unset>}, and not inside one.${A_T_NC}" >&2
        printf "Enter a repo path: " >&2; read -r repo
        repo="$(a_task_resolve_repo "$repo" "$base")" \
            || { echo -e "${A_T_RED}Not found.${A_T_NC}" >&2; return 1; }
        A_TASK_PICKED="$repo"; return 0
    fi

    echo -e "${A_T_BLUE}Pick a repo${A_T_NC} ${A_T_DIM}(current pinned first, then most recently worked in)${A_T_NC}" >&2
    n=0
    while IFS= read -r line; do
        n=$((n + 1))
        if [ -n "$cur" ] && [ "$line" = "$cur" ]; then
            label="${A_T_GREEN}current =>${A_T_NC} $(basename "$line")"
        else
            label="$(basename "$line")"
        fi
        printf '  [%d] %b\n' "$n" "$label" >&2
    done <<EOF
$candidates
EOF
    printf "Number, name, or full path [Enter = 1]: " >&2
    read -r choice
    choice="${choice:-1}"          # Enter selects the first (pinned) option
    case "$choice" in
        *[!0-9]*)
            repo="$(a_task_resolve_repo "$choice" "$base")" \
                || { echo -e "${A_T_RED}Could not resolve '$choice'.${A_T_NC}" >&2; return 1; } ;;
        *)
            repo="$(printf '%s\n' "$candidates" | sed -n "${choice}p")"
            [ -z "$repo" ] && { echo -e "${A_T_RED}No option #$choice.${A_T_NC}" >&2; return 1; } ;;
    esac
    A_TASK_PICKED="$repo"
}

# ----------------------------------------------------- worktree state ---

# Echo clean | dirty | missing for a worktree path.
a_task_wt_dirty() {
    [ -d "$1" ] || { printf 'missing'; return; }
    if [ -n "$(git -C "$1" status --porcelain 2>/dev/null)" ]; then printf 'dirty'
    else printf 'clean'; fi
}

# Echo ahead/behind vs upstream: "in sync", "2↑ 0↓", "no upstream", or "-".
a_task_wt_ab() {
    local p="$1" up counts ahead behind
    [ -d "$p" ] || { printf '-'; return; }
    up="$(git -C "$p" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"
    [ -z "$up" ] && { printf 'no upstream'; return; }
    counts="$(git -C "$p" rev-list --left-right --count "$up...HEAD" 2>/dev/null)"
    [ -z "$counts" ] && { printf '-'; return; }
    behind="$(printf '%s' "$counts" | awk '{print $1}')"
    ahead="$(printf '%s' "$counts" | awk '{print $2}')"
    if [ "$ahead" = 0 ] && [ "$behind" = 0 ]; then printf 'in sync'
    else printf '%s↑ %s↓' "$ahead" "$behind"; fi
}

# ------------------------------------------------ claude permission mode ---
# The permission mode a launched Claude session starts in. ONE definition; the
# fronts (jira / mdnest / github) deliberately pass no mode of their own so this
# is the only place it is decided.
#
# Default is "auto": the session keeps moving on its own. The old default,
# acceptEdits, auto-accepted file edits but STILL STOPPED and asked before
# running any command, so an unattended session sat on an invisible approval
# prompt at the first test run and never finished. In auto mode a genuinely
# risky action is refused and the refusal is handed back to the model, so the
# session is told "no" and carries on rather than waiting for a human who is not
# watching.
#
# Override per machine or per run with A_TASK_PERMISSION_MODE, e.g.
#   A_TASK_PERMISSION_MODE=acceptEdits a_c_task_start ...
#
# "auto" is not present in older claude builds, and an unrecognised mode makes
# claude abort at startup, which would break every task on a machine that has
# not updated. So ask the installed binary what it accepts and fall back to the
# previous default rather than failing.
a_task_permission_mode() {
    if [ -n "${A_TASK_PERMISSION_MODE:-}" ]; then
        printf '%s' "$A_TASK_PERMISSION_MODE"
        return 0
    fi
    if command -v claude >/dev/null 2>&1 &&
       claude --help 2>/dev/null | grep -q '"auto"'; then
        printf 'auto'
    else
        printf 'acceptEdits'
    fi
}

# ---------------------------------------------------- zellij integration ---
# Helpers for a_c_task_start's optional -z/--zellij flag: drop the new task into
# a named zellij session (creating the session if it is not running) under a tab
# named for the ticket + a short feature slug. All targeting is done from outside
# the session via `zellij --session <name> action ...`, which works whether or
# not the caller is currently inside zellij. No-op-friendly: callers gate on
# `command -v zellij` and these never touch the caller's own shell.

# Build the zellij tab title for a task: the Jira ticket / PR id alone, e.g.
# "PROJ-123". It is unique and short, so the tab is easy to spot and switch to in
# the tab bar. The feature slug is intentionally NOT shown in the title (it lives
# in the branch / worktree name); a second arg is accepted for backward
# compatibility but ignored, so tabs stay compact and the name is predictable
# (re-running for the same ticket finds the exact tab instead of duplicating it).
a_task_zellij_tab_name() {
    local ticket="$1"
    printf '%s' "$ticket"
}

# Echo the state of zellij session $1: running | exited | absent.
#
# Read the listing with `-n` (no formatting), NOT `-ns`: the short form strips the
# "(EXITED - attach to resurrect)" suffix, which made a DEAD session look alive.
# That mattered because `zellij --session <dead> action ...` prints "Session not
# found" and STILL EXITS 0, so callers reported success having created nothing.
a_task_zellij_state() {
    local line name
    while IFS= read -r line; do
        name="${line%% *}"
        [ "$name" = "$1" ] || continue
        case "$line" in
            *EXITED*) printf 'exited';  return 0 ;;
            *)        printf 'running'; return 0 ;;
        esac
    done < <(zellij list-sessions -n 2>/dev/null)
    printf 'absent'
}

# Return 0 if a zellij session named $1 is ALIVE right now. A session that has
# exited (resurrectable but dead) is deliberately NOT "have": nothing can be
# driven in it until a_c_zellij_tab brings it back.
a_task_zellij_have() {
    [ "$(a_task_zellij_state "$1")" = "running" ]
}

# Return 0 if session $1 already has a tab whose name is exactly $2. Used to keep
# the tab idempotent (re-running for the same task focuses it, never duplicates).
a_task_zellij_tab_exists() {
    local t
    while IFS= read -r t; do
        [ "$t" = "$2" ] && return 0
    done < <(zellij --session "$1" action query-tab-names 2>/dev/null)
    return 1
}

# Print the environment-hygiene preamble every generated launcher needs, on stdout,
# for the caller to write into the launcher script.
#
# WHY THIS EXISTS. A launcher is executed by the zellij SERVER, and that server
# inherits the environment of whatever first created the session. When a routine
# creates it, the routine's environment is then handed to every pane in that
# session, for as long as it lives. Measured on a real session created by tether
# (which runs under `uv run` from launchd):
#
#   TERM         not set at all   (a normal session had xterm-256color)
#   VIRTUAL_ENV  /…/ustaad/.venv  (tether's Python virtualenv, still active)
#   UV, UV_RUN_RECURSION_DEPTH    also inherited
#
# So a Claude session started from a button ran with no terminal type and inside
# tether's virtualenv. A TUI program with no TERM is in a degraded state before it
# starts, and a coding session has no business inheriting the transport's Python
# environment. Fix it at the launcher, which covers every caller (tether, cron,
# launchd) rather than one routine.
#
# a_c_zellij_tab carries a copy of this block for the launcher it builds from
# --cmd; it is standalone by design and does not source this library. Keep the two
# in step.
a_task_emit_env_hygiene() {
    printf '# --- environment hygiene (see a_task_emit_env_hygiene for why) ---\n'
    # Drop a leaked virtualenv from PATH before unsetting the marker.
    printf 'if [ -n "${VIRTUAL_ENV:-}" ]; then\n'
    printf '    PATH="$(printf %%s "$PATH" | tr : "\\n" | grep -vxF "$VIRTUAL_ENV/bin" | paste -sd: -)"\n'
    printf '    export PATH\n'
    printf 'fi\n'
    printf 'unset VIRTUAL_ENV UV UV_RUN_RECURSION_DEPTH PYTHONHOME PYTHONPATH\n'
    # Not `${TERM:-...}`: TERM is often SET to a value a full-screen program cannot
    # use. Observed both "unset" (server started from launchd) and "dumb" (inherited
    # from a non-interactive caller), and dumb is as useless to a TUI as no TERM.
    printf 'case "${TERM:-}" in ""|dumb|unknown) export TERM=xterm-256color ;; esac\n'
    printf 'export LANG="${LANG:-en_US.UTF-8}"\n'
    # Put this toolkit's scripts/ on PATH. Everything in scripts/ (a_c_*, a_g_*,
    # a_s_*) is only reachable by bare name because shell/generic.profile adds
    # that directory, and the profile is an INTERACTIVE-shell thing: not in a
    # login shell, not in a bare one, and above all not in the environment the
    # zellij server hands to a pane. So a launcher, or anything a launcher runs,
    # got "a_c_claude_remote: not found" while the very same command worked when
    # typed by hand. Baked in as a literal at generation time, since the launcher
    # runs later, elsewhere, with none of our variables set.
    printf 'case ":$PATH:" in\n'
    printf '    *:%s:*) ;;\n' "$(a_task_scripts_dir)"
    printf '    *) PATH=%s:"$PATH"; export PATH ;;\n' "$(a_task_scripts_dir)"
    printf 'esac\n'
}

# Absolute path of this toolkit's scripts/ directory. Derived from this library's
# own location, NOT from A_C_WORKFLOW_DIR/MY_WORKFLOW_DIR, so it is still right in
# a context where the profile never ran and those variables are unset, which is
# exactly the context that needs it.
a_task_scripts_dir() {
    local src="${BASH_SOURCE[0]:-${(%):-%x}}"
    printf '%s' "$(cd "$(dirname "$src")" && pwd)"
}

# Write a throwaway launcher script that runs a command (the a_c_claude_remote
# invocation, passed as $2..) and then drops to an interactive shell sitting in
# the worktree $1, so the tab is still usable after Claude exits. Echoes the
# script path. Args after $1 are %q-quoted into the script, so quoting is safe.
# The temp file is left in TMPDIR on purpose: zellij execs it a moment after the
# tab is created, so deleting it eagerly would race the pane's startup.
a_task_zellij_make_launcher() {
    local wt="$1"; shift
    local f
    f="$(mktemp "${TMPDIR:-/tmp}/a_c_task_zj.XXXXXX")" || return 1
    {
        printf '#!/usr/bin/env bash\n'
        printf '# Auto-generated by a_c_task_start to run Claude inside a zellij tab.\n'
        # Keep the trailing interactive shell from hanging on oh-my-zsh's
        # "Would you like to update? [Y/n]" prompt in an unattended tab.
        printf 'export DISABLE_AUTO_UPDATE=true DISABLE_UPDATE_PROMPT=true\n'
        a_task_emit_env_hygiene
        printf 'bash %s\n' "$(printf '%q ' "$@")"
        printf 'cd %q 2>/dev/null\n' "$wt"
        printf 'exec "${SHELL:-/bin/zsh}" -i\n'
    } > "$f" || return 1
    chmod +x "$f"
    printf '%s' "$f"
}

# Ensure a zellij session named $1 exists (creating it detached if not) and that
# it has a tab named $2. With a launcher path in $4 the tab runs that command in
# a single pane (via a temp layout); otherwise it is a plain shell sitting in cwd
# $3. `new-tab` already focuses the tab it creates, so a later attach lands on it
# for free. We deliberately do NOT call `go-to-tab-name` here: that action blocks
# indefinitely on a session with no attached client (the common case when we are
# about to attach, or when the target session is detached) - the caller focuses
# an existing tab only when it is the current, attached session.
#
# RETURN STATUS IS MEANINGFUL and callers must branch on it: 0 = the tab exists
# (and runs the launcher when one was given), 2 = zellij or the opener is missing,
# anything else = a_c_zellij_tab's own failure code (4 = the session would not
# start, 5 = the tab was not created). This used to `return 0` unconditionally,
# which is how a dead target session turned into a cheerful "✓ Tab ready" with no
# tab and no Claude running anywhere.
a_task_zellij_setup() {
    local session="$1" tab="$2" cwd="$3" launcher="${4:-}"
    command -v zellij >/dev/null 2>&1 || return 2
    # Delegate to the one canonical tab opener so the zellij layout (which must
    # include the tab-bar + status-bar plugin panes, or the tab opens with no
    # bars) lives in ONE place: a_c_zellij_tab. It ensures the session, is
    # idempotent on the tab, and never attaches. Focus stays the caller's job
    # (--no-focus), preserving each caller's context-aware focus/attach logic.
    local zt
    zt="$(command -v a_c_zellij_tab 2>/dev/null)"
    [ -n "$zt" ] || zt="${A_C_WORKFLOW_DIR:-${MY_WORKFLOW_DIR:-}}/scripts/a_c_zellij_tab"
    [ -x "$zt" ] || return 2                 # opener missing: caller falls back to a terminal launch
    if [ -n "$launcher" ]; then
        bash "$zt" "$session" "$tab" --cwd "$cwd" --launcher "$launcher" --no-focus
    else
        bash "$zt" "$session" "$tab" --cwd "$cwd" --no-focus
    fi
    return $?                    # pass the opener's verdict up; never fake success
}

# Return 0 only when a REAL terminal a human is looking at is on this process, so
# it is safe to hand that terminal to a full-screen program (`zellij attach`).
#
# `[ -t 0 ] && [ -t 1 ]` IS NOT ENOUGH, and assuming it was cost us a whole round
# of "the button still does nothing". A routine that runs commands through a pty
# (tether does, so shell functions and colors work) passes the isatty test with no
# human anywhere. Attaching there does three bad things at once: it paints the
# entire zellij UI into the routine's captured output as escape-code soup, it
# blocks the launcher script forever so the run never returns, and - worst - zellij
# sizes a session to its smallest client, so the fresh session gets clamped to that
# pty and is unusable when you later attach for real.
#
# The reliable tell is the WINDOW SIZE. os.openpty() and friends leave it unset, so
# `stty size` reports "0 0", while every real terminal reports a usable size.
#
# Do NOT use `tput lines` / `tput cols` here: tput falls back to the terminfo
# default and cheerfully reports 24x80 for a 0x0 pty, which is exactly the wrong
# answer. Measured on this machine: under tether, isatty says yes on both stdin and
# stdout, tput says 24x80, and `stty size` says "0 0".
#
# A_C_NO_ATTACH=1 forces "no" for any caller that already knows it is headless
# (cron, launchd, a routine), so it never has to depend on the heuristic.
a_task_can_attach() {
    [ "${A_C_NO_ATTACH:-0}" = "1" ] && return 1
    [ -t 0 ] && [ -t 1 ] || return 1
    local size rows cols
    size="$(stty size 2>/dev/null)" || return 1
    rows="${size%% *}"; cols="${size##* }"
    case "$rows" in ''|*[!0-9]*) return 1 ;; esac
    case "$cols" in ''|*[!0-9]*) return 1 ;; esac
    # A window too small to show anything is not a human terminal either, and
    # attaching to it would clamp the session just as badly as a 0x0 pty.
    [ "$rows" -ge 5 ] && [ "$cols" -ge 20 ]
}

# Best-effort: switch the attached client of session $1 to tab $2, WITHOUT
# attaching ourselves (so we never add a second client and never resize the
# session - that resize was the old bug from calling `zellij attach` here).
#
# `new-tab` only marks the new tab active in the session's state; an already-
# attached client (you, viewing the session in another terminal/pane) does not
# follow until something focuses it. `go-to-tab-name` does that focus - but it
# BLOCKS FOREVER on a session with no attached client. So we run it in the
# background and reap it after a short grace window: when a client is attached it
# returns near-instantly and you land on the new tab; when none is attached it is
# a harmless no-op (the tab is already active in state, so the next attach still
# lands on it) and we kill the hung call so a routine never stalls. Always 0.
a_task_zellij_focus_tab() {
    local session="$1" tab="$2"
    command -v zellij >/dev/null 2>&1 || return 0
    zellij --session "$session" action go-to-tab-name "$tab" >/dev/null 2>&1 &
    local pid=$! i=0
    while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 15 ]; do
        sleep 0.1; i=$((i + 1))
    done
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    return 0
}

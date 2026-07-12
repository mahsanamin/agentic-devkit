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
A_TASK_DEFAULT_KEY="${A_TASK_DEFAULT_KEY:-PROJ}"

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
# "PROJ-123" / "proj123" / "PROJ123", or a pasted Jira URL such as
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
    # "PROJ123" without a dash still works via the optional-dash regex below).
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

# Return 0 if a zellij session named $1 is currently listed. Matches the first
# whitespace-delimited field so an "(EXITED ...)" suffix can't hide a name.
a_task_zellij_have() {
    local s
    while IFS= read -r s; do
        s="${s%% *}"
        [ "$s" = "$1" ] && return 0
    done < <(zellij list-sessions -ns 2>/dev/null)
    return 1
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
# an existing tab only when it is the current, attached session. Returns 2 if
# zellij is not installed.
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
    return 0
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

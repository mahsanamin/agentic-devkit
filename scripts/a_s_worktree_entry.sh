#!/usr/bin/env bash
#
# a_s_worktree_entry.sh, non-interactive entry point for the sourced worktree helpers.
#
# WHY THIS EXISTS. The worktree helpers are shell FUNCTIONS in sourced/worktree.sh, so
# they only exist in a shell that sourced the profile. An agent's Bash tool does not:
# every call is a fresh non-interactive shell. Three helpers (init, remove, review)
# already had companion scripts and so worked from an agent; the rest did not exist at
# all outside an interactive terminal, while the docs told agents to call them.
#
# This dispatches to the function rather than reimplementing it, so there is still ONE
# implementation of each helper. The function is the owner; this is a door into it.
#
# Usage: a_s_worktree_entry.sh <helper-suffix> [args...]
#   e.g. a_s_worktree_entry.sh list
# Normally invoked through the thin a_g_worktree_<name> scripts beside this file.

# NOT `set -u`. The helpers are written for an interactive shell, where nobody runs
# with nounset, so they test `$1` directly and an unset $1 is normal ("no argument
# given"). Under nounset that read aborts the function before it can print its usage.
set -o pipefail

cmd="${1:-}"; shift || true
[ -n "$cmd" ] || { echo "a_s_worktree_entry.sh: no helper named" >&2; exit 2; }

# Resolve this script's REAL directory. ~/.claude/scripts and ~/.codex/scripts are
# symlinks into the repo, so a plain dirname would look for sourced/ beside the link.
self="${BASH_SOURCE[0]}"
while [ -L "$self" ]; do
  d=$(cd -P "$(dirname "$self")" && pwd); self=$(readlink "$self")
  case "$self" in /*) ;; *) self="$d/$self" ;; esac
done
SCRIPT_DIR=$(cd -P "$(dirname "$self")" && pwd)

LIB="$SCRIPT_DIR/../sourced/worktree.sh"
[ -f "$LIB" ] || { echo "a_s_worktree_entry.sh: cannot find $LIB" >&2; exit 1; }
# The library is written for an interactive shell and may reference MY_WORKFLOW_DIR.
export MY_WORKFLOW_DIR="${MY_WORKFLOW_DIR:-$(cd -P "$SCRIPT_DIR/.." && pwd)}"
# shellcheck disable=SC1090
source "$LIB"

fn="a_g_worktree_$cmd"
command -v "$fn" >/dev/null 2>&1 || { echo "a_s_worktree_entry.sh: no helper '$fn' in $LIB" >&2; exit 1; }

case "$cmd" in
  main|switch)
    # These cd the shell they run in. A subprocess cannot move its caller, so the
    # function's own "Switched to ..." would be false here: this shell moved, the
    # caller did not. Report the destination instead and let the caller cd to it.
    out=$("$fn" "$@" 2>&1); rc=$?
    if [ "$rc" -ne 0 ]; then printf '%s\n' "$out" >&2; exit "$rc"; fi
    dest=$(pwd -P)
    printf '%s\n' "$dest"
    printf 'Not a directory change: this ran in a subprocess, so your shell did not move.\ncd there yourself:  cd %q\n' "$dest" >&2
    ;;
  prune)
    # prune asks for a Y/N before deleting. With no terminal there is nobody to ask,
    # and a read on a closed stdin returns empty, which would silently take a branch
    # of a destructive prompt nobody answered. Refuse and name the read-only helper.
    if [ ! -t 0 ]; then
      echo "Refuse: a_g_worktree_prune deletes worktree state behind a confirmation prompt, and this shell has no terminal to answer it." >&2
      echo "        Run 'a_g_worktree_doctor' for the same findings read-only, or run prune yourself in a terminal." >&2
      exit 2
    fi
    "$fn" "$@"
    ;;
  *)
    "$fn" "$@"
    ;;
esac

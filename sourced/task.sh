#!/bin/bash
# Task workflow helpers.
#
# These are thin wrappers that SOURCE the a_c_task_* scripts so their final
# `cd` (into a new or looked-up worktree) lands in your interactive shell.
# Sourced from generic.profile; the functions shadow the same-named scripts
# that sit on PATH in scripts/.
#
#   a_c_task_start   pick a repo, name a branch from a Jira ticket
#                    (PROJ-123-feature), and create a worktree via
#                    a_g_worktree_init.
#   a_c_task_resume  switch back into an active task's worktree.
#   a_c_task_list    show every active task with live state (read-only).
#   a_c_task_finish  remove a finished task's worktree + branch (via
#                    a_g_worktree_remove) and unregister it.
#
# These scripts live in the agentic-devkit repo. Normally that repo is
# $MY_WORKFLOW_DIR, but when it is loaded ALONGSIDE another agentic-devkit checkout
# (a transitional dual setup), the work-repo path is exported as
# $A_C_WORKFLOW_DIR. Resolve that first, then fall back to MY_WORKFLOW_DIR.
#
# State: a small registry at ${A_TASK_HOME:-~/.a_tasks}/tasks.tsv.

# Each wrapper below resolves the repo path INLINE and calls no shared helper,
# which looks like needless repetition and is not. An agent session (Claude Code,
# Codex) does not source this file: it runs in a snapshot of the interactive
# shell, and that snapshot captured the four public functions below WITHOUT the
# private helper they used to call. The result was the worst possible failure
# shape - the command appeared to exist, then died with
# "command not found: _a_c_task_base" followed by a path with the repo dir
# missing, so the agent concluded the toolkit was absent and improvised raw
# git worktree commands instead. Four self-sufficient functions cannot break
# that way. Do not factor the repeated line back out into a helper.

a_c_task_start() {
    local base="${A_C_WORKFLOW_DIR:-${MY_WORKFLOW_DIR:-}}"
    [ -n "$base" ] || { echo "Error: a_c_task_start: neither A_C_WORKFLOW_DIR nor MY_WORKFLOW_DIR is set; source your shell profile." >&2; return 1; }
    local s="$base/scripts/a_c_task_start"
    [ -f "$s" ] || { echo "Error: a_c_task_start: no script at $s (is $base the agentic-devkit checkout?)" >&2; return 1; }
    source "$s" "$@"
}

a_c_task_resume() {
    local base="${A_C_WORKFLOW_DIR:-${MY_WORKFLOW_DIR:-}}"
    [ -n "$base" ] || { echo "Error: a_c_task_resume: neither A_C_WORKFLOW_DIR nor MY_WORKFLOW_DIR is set; source your shell profile." >&2; return 1; }
    local s="$base/scripts/a_c_task_resume"
    [ -f "$s" ] || { echo "Error: a_c_task_resume: no script at $s (is $base the agentic-devkit checkout?)" >&2; return 1; }
    source "$s" "$@"
}

a_c_task_list() {
    local base="${A_C_WORKFLOW_DIR:-${MY_WORKFLOW_DIR:-}}"
    [ -n "$base" ] || { echo "Error: a_c_task_list: neither A_C_WORKFLOW_DIR nor MY_WORKFLOW_DIR is set; source your shell profile." >&2; return 1; }
    local s="$base/scripts/a_c_task_list"
    [ -f "$s" ] || { echo "Error: a_c_task_list: no script at $s (is $base the agentic-devkit checkout?)" >&2; return 1; }
    source "$s" "$@"
}

a_c_task_finish() {
    local base="${A_C_WORKFLOW_DIR:-${MY_WORKFLOW_DIR:-}}"
    [ -n "$base" ] || { echo "Error: a_c_task_finish: neither A_C_WORKFLOW_DIR nor MY_WORKFLOW_DIR is set; source your shell profile." >&2; return 1; }
    local s="$base/scripts/a_c_task_finish"
    [ -f "$s" ] || { echo "Error: a_c_task_finish: no script at $s (is $base the agentic-devkit checkout?)" >&2; return 1; }
    source "$s" "$@"
}

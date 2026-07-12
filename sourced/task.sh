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
# These scripts live in the my_setup repo. Normally that repo is
# $MY_WORKFLOW_DIR, but when it is loaded ALONGSIDE another my_setup checkout
# (a transitional dual setup), the work-repo path is exported as
# $A_C_WORKFLOW_DIR. Resolve that first, then fall back to MY_WORKFLOW_DIR.
#
# State: a small registry at ${A_TASK_HOME:-~/.a_tasks}/tasks.tsv.

_a_c_task_base() { printf '%s' "${A_C_WORKFLOW_DIR:-$MY_WORKFLOW_DIR}"; }

a_c_task_start() {
    local s; s="$(_a_c_task_base)/scripts/a_c_task_start"
    [ -f "$s" ] || { echo "Error: a_c_task_start not found at $s (set A_C_WORKFLOW_DIR or MY_WORKFLOW_DIR)"; return 1; }
    source "$s" "$@"
}

a_c_task_resume() {
    local s; s="$(_a_c_task_base)/scripts/a_c_task_resume"
    [ -f "$s" ] || { echo "Error: a_c_task_resume not found at $s (set A_C_WORKFLOW_DIR or MY_WORKFLOW_DIR)"; return 1; }
    source "$s" "$@"
}

a_c_task_list() {
    local s; s="$(_a_c_task_base)/scripts/a_c_task_list"
    [ -f "$s" ] || { echo "Error: a_c_task_list not found at $s (set A_C_WORKFLOW_DIR or MY_WORKFLOW_DIR)"; return 1; }
    source "$s" "$@"
}

a_c_task_finish() {
    local s; s="$(_a_c_task_base)/scripts/a_c_task_finish"
    [ -f "$s" ] || { echo "Error: a_c_task_finish not found at $s (set A_C_WORKFLOW_DIR or MY_WORKFLOW_DIR)"; return 1; }
    source "$s" "$@"
}

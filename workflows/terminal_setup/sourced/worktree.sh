#!/bin/bash
# Git Worktree Helper Functions
# Source this file in your .zshrc or .bashrc for enhanced worktree management
#
# Add to your shell config:
#   source /path/to/worktree.sh

# Enhanced worktree init with auto-cd
a_g_worktree_init() {
    local script_path="$MY_WORKFLOW_DIR/scripts/a_g_worktree_init"

    if [ ! -f "$script_path" ]; then
        echo "Error: a_g_worktree_init script not found at $script_path"
        echo "Is MY_WORKFLOW_DIR set correctly? Current: $MY_WORKFLOW_DIR"
        return 1
    fi

    # Validate branch name before sourcing (source runs in current shell,
    # so an exit in the script would kill the terminal)
    if [ -z "$1" ] || [[ "$1" == -* ]]; then
        echo "Usage: a_g_worktree_init <branch-name> [-b|--base <branch>]"
        echo "Example: a_g_worktree_init feature/setup-local-data-seeds"
        return 1
    fi

    # Source the script to allow directory change
    source "$script_path" "$@"
}

# Enhanced worktree remove with auto-context switching
a_g_worktree_remove() {
    local script_path="$MY_WORKFLOW_DIR/scripts/a_g_worktree_remove"

    if [ ! -f "$script_path" ]; then
        echo "Error: a_g_worktree_remove script not found at $script_path"
        echo "Is MY_WORKFLOW_DIR set correctly? Current: $MY_WORKFLOW_DIR"
        return 1
    fi

    # Execute the script (it handles context switching internally)
    bash "$script_path" "$@"
}

# List all worktrees with enhanced formatting
a_g_worktree_list() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        return 1
    fi

    echo "Git Worktrees:"
    echo "─────────────────────────────────────────────────────────────────"
    git worktree list --porcelain | awk '
        /^worktree / { path = substr($0, 10); }
        /^HEAD / { head = substr($0, 6); }
        /^branch / { branch = substr($0, 8); }
        /^$/ {
            if (path != "") {
                printf "%-50s %s\n", path, branch;
                path = ""; branch = ""; head = "";
            }
        }
        END {
            if (path != "") {
                printf "%-50s %s\n", path, branch;
            }
        }
    '
    echo "─────────────────────────────────────────────────────────────────"
}

# Quick switch to a worktree by feature name
a_g_worktree_switch() {
    if [ -z "$1" ]; then
        echo "Usage: a_g_worktree_switch <feature-name>"
        echo "Example: a_g_worktree_switch my-feature"
        return 1
    fi

    local feature_name="$1"
    local git_root main_worktree project_name worktree_path

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        return 1
    fi

    main_worktree=$(git worktree list | head -n 1 | awk '{print $1}')
    project_name=$(basename "$main_worktree")
    worktree_path="$(dirname "$main_worktree")/WorkTrees/$project_name/$feature_name"

    # Try exact name first, then slash-to-dash conversion
    if [ ! -d "$worktree_path" ]; then
        local worktree_dir_name="${feature_name//\//-}"
        worktree_path="$(dirname "$main_worktree")/WorkTrees/$project_name/$worktree_dir_name"
    fi

    if [ -d "$worktree_path" ]; then
        cd "$worktree_path" || return 1
        echo "Switched to worktree: $feature_name"
    else
        echo "Error: Worktree not found"
        echo ""
        echo "Available worktrees:"
        a_g_worktree_list
        return 1
    fi
}

# Conclude a merged worktree (alias to remove --verify)
a_g_worktree_conclude() {
    a_g_worktree_remove --verify "$@"
}

# Update current branch with latest main (fetch + rebase)
a_g_worktree_update() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        return 1
    fi

    local main_branch current_branch has_changes

    # Determine main branch
    if git show-ref --verify --quiet refs/heads/main; then
        main_branch="main"
    elif git show-ref --verify --quiet refs/heads/master; then
        main_branch="master"
    else
        echo "Error: Neither 'main' nor 'master' branch found"
        return 1
    fi

    current_branch=$(git branch --show-current)

    if [ "$current_branch" = "$main_branch" ]; then
        echo "Already on $main_branch, just pulling..."
        git pull origin "$main_branch"
        return $?
    fi

    echo "Current branch: $current_branch"
    echo "Rebasing onto: $main_branch"
    echo ""

    # Check for uncommitted changes
    has_changes=false
    if ! git diff --quiet || ! git diff --cached --quiet; then
        has_changes=true
        echo "Stashing uncommitted changes..."
        git stash push -m "a_g_worktree_update: auto-stash before rebase"
    fi

    # Fetch and rebase
    echo "Fetching origin/$main_branch..."
    git fetch origin "$main_branch"

    echo "Rebasing..."
    if git rebase "origin/$main_branch"; then
        echo ""
        echo "Successfully rebased onto $main_branch"
    else
        echo ""
        echo "Rebase conflicts detected!"
        echo ""
        echo "Options:"
        echo "  1. Resolve conflicts, then: git rebase --continue"
        echo "  2. Abort rebase: git rebase --abort"
        if [ "$has_changes" = true ]; then
            echo ""
            echo "Note: Your uncommitted changes are stashed. Run 'git stash pop' after resolving."
        fi
        return 1
    fi

    # Restore stashed changes
    if [ "$has_changes" = true ]; then
        echo "Restoring stashed changes..."
        if git stash pop; then
            echo "Stashed changes restored"
        else
            echo "Conflict restoring stashed changes. Run 'git stash show' to see them."
        fi
    fi
}

# Return to main repository from any worktree
a_g_worktree_main() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        return 1
    fi

    local main_worktree
    main_worktree=$(git worktree list | head -n 1 | awk '{print $1}')

    cd "$main_worktree" || return 1
    echo "Switched to main repository"
}

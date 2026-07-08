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

# Create a worktree from a remote branch or PR — for reviewing teammate work.
# Companion script handles the heavy lifting; sourced so the auto-cd works.
a_g_worktree_review() {
    local script_path="$MY_WORKFLOW_DIR/scripts/a_g_worktree_review"

    if [ ! -f "$script_path" ]; then
        echo "Error: a_g_worktree_review script not found at $script_path"
        echo "Is MY_WORKFLOW_DIR set correctly? Current: $MY_WORKFLOW_DIR"
        return 1
    fi

    if [ -z "$1" ] || [[ "$1" == -* ]]; then
        echo "Usage: a_g_worktree_review <pr-number-or-branch-name> [-r|--remote <remote>]"
        echo "Example: a_g_worktree_review 356"
        echo "Example: a_g_worktree_review feature/teammate-branch"
        return 1
    fi

    source "$script_path" "$@"
}

# List all worktrees with status, ahead/behind, and dirty/clean indicators.
# Pure read-only — no fetches, no remote calls. Ahead/behind is measured
# against the branch's upstream (origin/{branch}) at last fetch.
a_g_worktree_list() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        return 1
    fi

    local YELLOW='\033[1;33m'
    local GREEN='\033[0;32m'
    local RED='\033[0;31m'
    local BLUE='\033[0;34m'
    local DIM='\033[2m'
    local NC='\033[0m'

    # Collect worktree records from porcelain. Each record ends at a blank line.
    local -a paths=()
    local -a branches=()
    local current_path="" current_branch=""

    while IFS= read -r line; do
        if [[ "$line" == "worktree "* ]]; then
            current_path="${line#worktree }"
        elif [[ "$line" == "branch "* ]]; then
            current_branch="${line#branch }"
            current_branch="${current_branch#refs/heads/}"
        elif [[ "$line" == "detached"* ]]; then
            current_branch="(detached)"
        elif [[ -z "$line" && -n "$current_path" ]]; then
            paths+=("$current_path")
            branches+=("$current_branch")
            current_path=""; current_branch=""
        fi
    done < <(git worktree list --porcelain; echo)

    if [ "${#paths[@]}" -eq 0 ]; then
        echo "No worktrees found."
        return 0
    fi

    printf "${BLUE}%-60s %-32s %-7s %s${NC}\n" "PATH" "BRANCH" "STATE" "vs UPSTREAM"
    echo "─────────────────────────────────────────────────────────────────────────────────────────────────────────"

    for i in "${!paths[@]}"; do
        local p="${paths[$i]}"
        local br="${branches[$i]}"
        local state="clean"
        local state_color="$GREEN"
        local upstream_info="-"

        # Dirty/clean check — porcelain output is empty if clean
        if [ -d "$p" ]; then
            if [ -n "$(git -C "$p" status --porcelain 2>/dev/null)" ]; then
                state="dirty"
                state_color="$YELLOW"
            fi
        else
            state="missing"
            state_color="$RED"
        fi

        # Ahead/behind vs upstream (only if branch has an upstream)
        if [ "$br" != "(detached)" ] && [ -d "$p" ]; then
            local upstream
            upstream=$(git -C "$p" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
            if [ -n "$upstream" ]; then
                local counts
                counts=$(git -C "$p" rev-list --left-right --count "$upstream...HEAD" 2>/dev/null)
                if [ -n "$counts" ]; then
                    local behind ahead
                    behind=$(echo "$counts" | awk '{print $1}')
                    ahead=$(echo "$counts" | awk '{print $2}')
                    if [ "$ahead" = "0" ] && [ "$behind" = "0" ]; then
                        upstream_info="in sync"
                    else
                        upstream_info="${ahead}↑ ${behind}↓"
                    fi
                fi
            else
                upstream_info="${DIM}no upstream${NC}"
            fi
        fi

        printf "%-60s %-32s ${state_color}%-7s${NC} %b\n" "$p" "$br" "$state" "$upstream_info"
    done
    echo "─────────────────────────────────────────────────────────────────────────────────────────────────────────"
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

# Health-check worktrees. Pure read-only — never deletes anything.
# Flags four kinds of trouble:
#   1. orphans      — git worktree list says a path exists, but the dir is gone
#   2. merged       — worktree's branch is already merged into main/master
#   3. dirty        — uncommitted changes (so removal would lose work)
#   4. no upstream  — branch has no tracking remote (probably never pushed)
a_g_worktree_doctor() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        return 1
    fi

    local YELLOW='\033[1;33m'
    local GREEN='\033[0;32m'
    local RED='\033[0;31m'
    local BLUE='\033[0;34m'
    local NC='\033[0m'

    # Determine main/master for merge detection
    local main_branch=""
    if git show-ref --verify --quiet refs/heads/main; then
        main_branch="main"
    elif git show-ref --verify --quiet refs/heads/master; then
        main_branch="master"
    fi

    local -a orphans=() merged=() dirty=() no_upstream=()
    local main_worktree
    main_worktree=$(git worktree list | head -n 1 | awk '{print $1}')

    local current_path="" current_branch=""
    while IFS= read -r line; do
        if [[ "$line" == "worktree "* ]]; then
            current_path="${line#worktree }"
        elif [[ "$line" == "branch "* ]]; then
            current_branch="${line#branch }"
            current_branch="${current_branch#refs/heads/}"
        elif [[ "$line" == "detached"* ]]; then
            current_branch="(detached)"
        elif [[ -z "$line" && -n "$current_path" ]]; then
            # Skip the main worktree itself
            if [ "$current_path" != "$main_worktree" ]; then
                if [ ! -d "$current_path" ]; then
                    orphans+=("$current_path [branch: $current_branch]")
                else
                    # Dirty?
                    if [ -n "$(git -C "$current_path" status --porcelain 2>/dev/null)" ]; then
                        dirty+=("$current_path [branch: $current_branch]")
                    fi
                    # Merged into main/master?
                    if [ -n "$main_branch" ] && [ "$current_branch" != "(detached)" ]; then
                        if git -C "$current_path" merge-base --is-ancestor "refs/heads/$current_branch" "refs/heads/$main_branch" 2>/dev/null; then
                            merged+=("$current_path [branch: $current_branch]")
                        fi
                    fi
                    # Upstream tracking?
                    if [ "$current_branch" != "(detached)" ]; then
                        if ! git -C "$current_path" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
                            no_upstream+=("$current_path [branch: $current_branch]")
                        fi
                    fi
                fi
            fi
            current_path=""; current_branch=""
        fi
    done < <(git worktree list --porcelain; echo)

    local issues=0

    if [ "${#orphans[@]}" -gt 0 ]; then
        issues=$((issues + ${#orphans[@]}))
        echo -e "${RED}Orphans (path missing from disk, git still tracks them):${NC}"
        for o in "${orphans[@]}"; do echo "  • $o"; done
        echo "  Fix: a_g_worktree_prune"
        echo ""
    fi

    if [ "${#merged[@]}" -gt 0 ]; then
        issues=$((issues + ${#merged[@]}))
        echo -e "${YELLOW}Already merged into $main_branch (safe to remove):${NC}"
        for m in "${merged[@]}"; do echo "  • $m"; done
        echo "  Fix: a_g_worktree_remove <name>"
        echo ""
    fi

    if [ "${#dirty[@]}" -gt 0 ]; then
        issues=$((issues + ${#dirty[@]}))
        echo -e "${YELLOW}Dirty (uncommitted changes — removing would lose work):${NC}"
        for d in "${dirty[@]}"; do echo "  • $d"; done
        echo ""
    fi

    if [ "${#no_upstream[@]}" -gt 0 ]; then
        issues=$((issues + ${#no_upstream[@]}))
        echo -e "${BLUE}No upstream (branch was never pushed):${NC}"
        for n in "${no_upstream[@]}"; do echo "  • $n"; done
        echo ""
    fi

    if [ "$issues" -eq 0 ]; then
        echo -e "${GREEN}✓ All worktrees healthy${NC}"
    else
        echo "Summary: $issues issue(s) found across worktrees."
    fi
}

# Wrap 'git worktree prune' with a dry-run preview and confirmation.
# Safe by default — never silently removes anything you didn't agree to.
a_g_worktree_prune() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        return 1
    fi

    local YELLOW='\033[1;33m'
    local GREEN='\033[0;32m'
    local NC='\033[0m'

    echo -e "${YELLOW}Dry run — these worktree entries would be pruned:${NC}"
    local dry_output
    dry_output=$(git worktree prune --dry-run --verbose 2>&1)

    if [ -z "$dry_output" ]; then
        echo -e "${GREEN}✓ Nothing to prune${NC}"
        return 0
    fi
    echo "$dry_output"
    echo ""

    read -r -p "Proceed with prune? [y/N] " REPLY
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        git worktree prune --verbose
        echo -e "${GREEN}✓ Pruned${NC}"
    else
        echo "Cancelled."
    fi
}

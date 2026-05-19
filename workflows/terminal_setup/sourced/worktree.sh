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

# Create a worktree from a GitHub PR number or a remote branch (review checkout)
a_g_worktree_review() {
    local script_path="$MY_WORKFLOW_DIR/scripts/a_g_worktree_review"

    if [ ! -f "$script_path" ]; then
        echo "Error: a_g_worktree_review script not found at $script_path"
        echo "Is MY_WORKFLOW_DIR set correctly? Current: $MY_WORKFLOW_DIR"
        return 1
    fi

    if [ -z "$1" ] || { [[ "$1" == -* ]] && [[ "$1" != "-h" && "$1" != "--help" ]]; }; then
        echo "Usage: a_g_worktree_review <pr-number | branch-name>"
        echo "Examples:"
        echo "  a_g_worktree_review 356"
        echo "  a_g_worktree_review fix/some-bug"
        return 1
    fi

    source "$script_path" "$@"
}

# List worktrees with status indicators (clean/dirty + ahead/behind upstream).
# All locals declared up-front with values — zsh prints `name=value` for any
# `local name` (no =) when TYPESET_SILENT is unset, which is the zsh default.
a_g_worktree_list() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        return 1
    fi

    local wt_path="" wt_branch="" wt_status="" ab=""
    local ahead="" behind="" name="" line=""
    local main_path="" main_basename=""

    main_path=$(git worktree list | head -n 1 | awk '{print $1}')
    main_basename=$(basename "$main_path")

    printf "%-42s %-50s %-7s %s\n" "WORKTREE" "BRANCH" "STATUS" "A/B"
    echo "──────────────────────────────────────────────────────────────────────────────────────────────────────"

    while IFS= read -r line; do
        if [[ "$line" == "worktree "* ]]; then
            wt_path="${line#worktree }"
            wt_branch=""
        elif [[ "$line" == "branch "* ]]; then
            wt_branch="${line#branch }"
            wt_branch="${wt_branch#refs/heads/}"
        elif [[ "$line" == "detached" ]]; then
            wt_branch="(detached)"
        elif [[ -z "$line" && -n "$wt_path" ]]; then
            wt_status="clean"
            ab="-/-"
            ahead=""
            behind=""
            if [ -d "$wt_path" ]; then
                if [ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]; then
                    wt_status="dirty"
                fi
                ahead=$(git -C "$wt_path" rev-list --count '@{u}..HEAD' 2>/dev/null)
                behind=$(git -C "$wt_path" rev-list --count 'HEAD..@{u}' 2>/dev/null)
                if [ -n "$ahead" ] && [ -n "$behind" ]; then
                    ab="↑${ahead} ↓${behind}"
                fi
            else
                wt_status="missing"
            fi
            if [ "$wt_path" = "$main_path" ]; then
                name="$(basename "$wt_path") (main)"
            else
                name=$(basename "$wt_path")
            fi
            printf "%-42s %-50s %-7s %s\n" "$name" "${wt_branch:-(unknown)}" "$wt_status" "$ab"
            wt_path=""
            wt_branch=""
        fi
    done < <(git worktree list --porcelain; echo)
    echo "──────────────────────────────────────────────────────────────────────────────────────────────────────"
    echo "Main: $main_path"
    echo "Use 'a_g_worktree_switch <name>' to cd into one."
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

# Prune stale worktree registrations + orphan directories under WorkTrees/
a_g_worktree_prune() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        return 1
    fi

    local main_worktree="" project_name="" worktrees_root=""
    main_worktree=$(git worktree list | head -n 1 | awk '{print $1}')
    project_name=$(basename "$main_worktree")
    worktrees_root="$(dirname "$main_worktree")/WorkTrees/$project_name"

    local dry=""
    dry=$(git worktree prune --dry-run --verbose 2>&1)
    echo "Stale worktree registrations (dir missing but git still tracks them):"
    if [ -z "$dry" ]; then
        echo "  (none)"
    else
        echo "$dry" | sed 's/^/  /'
    fi
    echo ""

    local -a orphans=()
    local registered_paths="" clean=""
    if [ -d "$worktrees_root" ]; then
        registered_paths=$(git worktree list --porcelain | awk '/^worktree / {print substr($0, 10)}')
        for dir in "$worktrees_root"/*/; do
            [ -d "$dir" ] || continue
            clean="${dir%/}"
            if ! printf '%s\n' "$registered_paths" | grep -qxF "$clean"; then
                orphans+=("$clean")
            fi
        done
    fi

    echo "Orphan directories in $worktrees_root (not registered as worktrees):"
    if [ ${#orphans[@]} -eq 0 ]; then
        echo "  (none)"
    else
        printf '  %s\n' "${orphans[@]}"
    fi
    echo ""

    if [ -z "$dry" ] && [ ${#orphans[@]} -eq 0 ]; then
        echo "Nothing to prune."
        return 0
    fi

    read -r -p "Run 'git worktree prune' and remove orphan dirs? [y/N] " REPLY
    if [[ ! "$REPLY" =~ ^[Yy] ]]; then
        echo "Cancelled."
        return 0
    fi

    git worktree prune --verbose
    for o in "${orphans[@]}"; do
        rm -rf "$o" && echo "Removed orphan: $o"
    done
    echo "Done."
}

# Worktree health report: stale registrations, dirty trees, merged branches,
# branches with no upstream. Read-only; only reports, never acts.
a_g_worktree_doctor() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        return 1
    fi

    local main_branch=""
    if git show-ref --verify --quiet refs/heads/main; then
        main_branch="main"
    elif git show-ref --verify --quiet refs/heads/master; then
        main_branch="master"
    fi

    echo "Worktree health report"
    echo "──────────────────────"
    echo ""

    local issues=0

    # 1. Stale registrations
    local prune_out=""
    prune_out=$(git worktree prune --dry-run --verbose 2>&1)
    if [ -n "$prune_out" ]; then
        echo "⚠ Registered worktrees with missing directories:"
        echo "$prune_out" | sed 's/^/    /'
        echo "  Fix: a_g_worktree_prune"
        echo ""
        issues=$((issues + 1))
    fi

    # Walk worktrees once, collecting buckets
    local -a dirty=() merged=() no_upstream=()
    local wt_path="" wt_branch=""
    while IFS= read -r line; do
        if [[ "$line" == "worktree "* ]]; then
            wt_path="${line#worktree }"
            wt_branch=""
        elif [[ "$line" == "branch "* ]]; then
            wt_branch="${line#branch }"
            wt_branch="${wt_branch#refs/heads/}"
        elif [[ -z "$line" && -n "$wt_path" ]]; then
            if [ -d "$wt_path" ]; then
                if [ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]; then
                    dirty+=("$wt_path [${wt_branch:-detached}]")
                fi
                if [ -n "$wt_branch" ] && [ "$wt_branch" != "$main_branch" ]; then
                    if [ -n "$main_branch" ] && git merge-base --is-ancestor "$wt_branch" "$main_branch" 2>/dev/null; then
                        merged+=("$wt_path [$wt_branch]")
                    fi
                    if ! git -C "$wt_path" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
                        no_upstream+=("$wt_path [$wt_branch]")
                    fi
                fi
            fi
            wt_path=""
            wt_branch=""
        fi
    done < <(git worktree list --porcelain; echo)

    if [ ${#dirty[@]} -gt 0 ]; then
        echo "⚠ Dirty worktrees (uncommitted changes):"
        printf '    %s\n' "${dirty[@]}"
        echo ""
        issues=$((issues + 1))
    fi

    if [ ${#merged[@]} -gt 0 ]; then
        echo "ℹ Branches fully merged into $main_branch (safe to remove):"
        printf '    %s\n' "${merged[@]}"
        echo "  Fix: a_g_worktree_conclude <name>"
        echo ""
        issues=$((issues + 1))
    fi

    if [ ${#no_upstream[@]} -gt 0 ]; then
        echo "ℹ Branches with no upstream (not pushed yet):"
        printf '    %s\n' "${no_upstream[@]}"
        echo ""
        issues=$((issues + 1))
    fi

    if [ $issues -eq 0 ]; then
        echo "✓ All worktrees healthy"
    else
        echo "Found $issues issue group(s) above."
    fi
}

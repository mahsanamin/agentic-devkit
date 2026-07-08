#!/bin/bash
# Git Helper Functions
# Only commands that combine multiple steps or add safety.
# Thin wrappers over basic git belong in your muscle memory, not a script.

# Pull with rebase, then push current branch
# Handles: no-tracking detection, rebase-before-push, auto -u
a_g_push() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        return 1
    fi

    local current_branch
    current_branch=$(git branch --show-current)

    if [ -z "$current_branch" ]; then
        echo "Error: Not on any branch (detached HEAD?)"
        return 1
    fi

    echo "Branch: $current_branch"
    echo ""

    # Check if remote tracking exists
    if git config "branch.$current_branch.remote" > /dev/null 2>&1; then
        echo "Pulling latest..."
        if ! git pull --rebase origin "$current_branch"; then
            echo ""
            echo "Pull failed. Resolve conflicts first."
            return 1
        fi
        echo ""
    fi

    echo "Pushing..."
    git push -u origin "$current_branch"

    echo ""
    echo "Done"
}

# Stage all, commit, pull-rebase, push - the full workflow in one command
a_g_ship() {
    if [ -z "$1" ]; then
        echo "Usage: a_g_ship <message>"
        echo "Example: a_g_ship 'Fix login bug'"
        return 1
    fi

    git add -A
    git commit -m "$1"
    a_g_push
}

# Smart checkout: detects main vs master, checks out and pulls
a_g_main() {
    local main_branch

    if git show-ref --verify --quiet refs/heads/main; then
        main_branch="main"
    elif git show-ref --verify --quiet refs/heads/master; then
        main_branch="master"
    else
        echo "Error: Neither 'main' nor 'master' branch found"
        return 1
    fi

    git checkout "$main_branch"
    git pull origin "$main_branch"
}

# Print the origin remote URL (useful when jumping between many repos)
a_g_origin_url() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        return 1
    fi

    local url
    url=$(git remote get-url origin 2>/dev/null)
    if [ -z "$url" ]; then
        echo "Error: No 'origin' remote configured"
        return 1
    fi
    echo "$url"
}

# Discard all local changes - with confirmation because it's destructive
a_g_reset() {
    echo "This will discard ALL local changes!"
    read -p "Are you sure? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git reset --hard HEAD
        git clean -fd
        echo "All local changes discarded"
    else
        echo "Cancelled"
    fi
}

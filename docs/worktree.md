# Git Worktree Management Tools

Enhanced scripts for managing git worktrees with automatic directory switching and improved error handling.

## Files

- `a_g_worktree_init` - Create new worktrees
- `a_g_worktree_remove` - Remove worktrees
- `worktree.sh` - Shell functions wrapper (auto-sourced via generic.profile)

## Quick Start

### Option 1: Use Shell Functions (Recommended)

If you've followed the main setup (configs.profile sources generic.profile), these are already available.

Otherwise, add to your `~/.zshrc` or `~/.bashrc`:

```bash
source /path/to/worktree.sh
```

Now you get:
- **Auto-cd** after creating worktrees
- Enhanced commands with better UX
- Additional helper functions

### Option 2: Use Scripts Directly

Simply call the scripts:
```bash
a_g_worktree_init my-feature    # Creates but doesn't cd
source a_g_worktree_init my-feature  # Creates and cds (bash/zsh)
```

## Commands

### Create a Worktree

```bash
# Using functions (auto-cd enabled)
a_g_worktree_init feature/auth-improvements

# You can use any branch name you want (no automatic prefix)
a_g_worktree_init bugfix/login-issue
a_g_worktree_init my-custom-branch

# Using functions with custom base branch
a_g_worktree_init feature/new-api --base develop

# Using script directly (manual cd required)
./a_g_worktree_init feature/my-feature
cd /path/to/WorkTrees/project/feature-my-feature
```

Creates:
- Branch: Whatever name you provide (e.g., `feature/auth-improvements`)
- Directory: Slashes converted to dashes (e.g., `feature-auth-improvements`)
- Path: `../WorkTrees/<project-name>/feature-auth-improvements`

**Note**: Slashes in branch names are converted to dashes for directory names to avoid nested folders.

### Remove a Worktree

```bash
# Default: warns if unpushed commits
a_g_worktree_remove feature/auth-improvements

# Also accepts dash format
a_g_worktree_remove feature-auth-improvements

# Verify merged into main before removing (safe)
a_g_worktree_remove feature/auth -v

# Force remove, skip all checks
a_g_worktree_remove feature/auth -f
```

### List Worktrees

```bash
a_g_worktree_list
```

### Switch Between Worktrees

```bash
a_g_worktree_switch my-feature
a_g_worktree_main    # Return to main repository
```

### Update Branch with Latest Main

```bash
a_g_worktree_update  # Fetches main, rebases, auto-stashes uncommitted changes
```

### Conclude a Merged Worktree

```bash
a_g_worktree_conclude feature/my-feature  # Alias for remove --verify
```

## Safety Features

- **Unpushed code warning**: Warns before deleting worktrees with unpushed commits
- **Merge verification**: `--verify` mode checks multiple ways (including squash merges)
- **Ticket verification**: Extracts ticket numbers from commits, checks if they appear in main
- **Protected branches**: Never deletes main, master, staging, develop, prod, production
- **Auto-stash**: `a_g_worktree_update` stashes uncommitted changes before rebase

## Directory Structure

```
repos/
├── my-project/                     # Main repository
└── WorkTrees/
    └── my-project/
        ├── feature-auth/           # Worktree for branch feature/auth
        ├── bugfix-login/           # Worktree for branch bugfix/login
        └── my-custom-branch/       # Worktree for branch my-custom-branch
```

## Troubleshooting

### Auto-cd doesn't work
Make sure you're using the shell functions (sourced via generic.profile), or source the script: `source a_g_worktree_init my-feature`

### "Worktree not found" error
The script shows available worktrees. Use the exact name from when you created it. Both slash and dash formats are accepted.

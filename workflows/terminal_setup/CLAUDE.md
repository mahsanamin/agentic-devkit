# my-workflow

Modular shell workflow system for developers. Git workflows, worktree management, branch cleanup, process utilities, and multi-org shell profiles.

## Setup Guide (for Claude)

When a user asks to set up my-workflow, walk them through these steps:

### 1. Create their personal config

```bash
mkdir -p ~/my_settings
cp shell/configs.profile.sample ~/my_settings/configs.profile
```

Then ask them for:
- **Personal repos path** (e.g., `~/repos/personal`)
- **Work repos path** (e.g., `~/repos/work`)
- **Where they cloned this repo** (becomes `MY_WORKFLOW_DIR`)
- **Machine type**: `m1` (Apple Silicon) or `i7` (Intel)
- **Org name** (optional - for loading org-specific profile)

Update `~/my_settings/configs.profile` with their answers.

### 2. Add to their shell

Append to `~/.zshrc` (or `~/.bashrc`):

```bash
source ~/my_settings/configs.profile
```

### 3. (Optional) Create org profile

If they have an org name, copy the sample:

```bash
cp shell/org.machine.profile.sample shell/<org>.<machine>.profile
```

Help them add SSH aliases, directory shortcuts, DB connections, etc.

### 4. Reload

```bash
source ~/.zshrc
```

## Project Structure

```
my-workflow/
├── shell/                         # Shell profile system
│   ├── configs.profile.sample     # User copies to ~/my_settings/configs.profile
│   ├── generic.profile            # Core profile (sources everything)
│   └── org.machine.profile.sample # Template for org-specific profiles
├── sourced/                       # Functions sourced into shell
│   ├── git.sh                     # Git workflows (ship, push, main, reset)
│   ├── worktree.sh                # Git worktree helpers
│   └── process.sh                 # Process management
├── scripts/                       # Standalone scripts (auto-added to PATH)
│   ├── a_g_worktree_init          # Create git worktrees
│   ├── a_g_worktree_remove        # Remove git worktrees (merge verification)
│   ├── a_g_branch_delete          # Smart branch deletion (squash-merge aware)
│   ├── a_g_branch_cleanup         # Bulk merged branch cleanup
│   ├── a_uninstall_app.sh         # macOS app uninstaller
│   ├── a_c_mcp_add                # Claude MCP server setup
│   └── a_time_range.sh            # Date range utility
├── tools/                         # Standalone tools (self-contained, own configs)
│   └── slack-summarizer/          # Automated Slack briefing system (see its CLAUDE.md)
└── docs/
    ├── worktree.md                # Worktree usage guide
    └── mac.md                     # macOS tips
```

## Key Architecture

- `MY_WORKFLOW_DIR` is the single root variable. Set in user's `configs.profile`. Everything derives from it.
- `generic.profile` is the loader: sources `sourced/*.sh`, adds `scripts/` to PATH, loads org profile.
- Org profiles follow the pattern `shell/<org>.<machine>.profile` and auto-load based on `a_company_name` + `a_machine_type`.
- `sourced/` files run in the current shell (can cd, export). `scripts/` run as subprocesses.

## Naming Conventions

- `a_` prefix = personal utility
- `a_g_` prefix = git-related
- `a_c_` prefix = claude/AI tool
- Scripts go in `scripts/`, functions go in `sourced/`
- All scripts use `#!/bin/bash`

## Commands

### Git Workflows (sourced/git.sh)

| Command | What it does |
|---------|-------------|
| `a_g_ship <msg>` | Stage all + commit + pull-rebase + push |
| `a_g_push` | Pull-rebase then push (handles no-tracking) |
| `a_g_main` | Smart main/master checkout + pull |
| `a_g_reset` | Hard reset + clean (with confirmation) |

### Git Worktree (sourced/worktree.sh + scripts)

| Command | What it does |
|---------|-------------|
| `a_g_worktree_init <branch> [-b base]` | Create worktree, auto-cd, copy dotfiles |
| `a_g_worktree_remove <name> [-v\|-f]` | Remove worktree (-v verifies merged, -f force) |
| `a_g_worktree_conclude <name>` | Alias: remove --verify |
| `a_g_worktree_list` | Formatted worktree listing |
| `a_g_worktree_switch <name>` | cd to worktree by name |
| `a_g_worktree_main` | cd back to main repo |
| `a_g_worktree_update` | Rebase onto main (auto-stash) |

### Branch Management (scripts)

| Command | What it does |
|---------|-------------|
| `a_g_branch_delete <branch>` | Delete with merge verification (squash-aware) |
| `a_g_branch_cleanup [-n\|-f\|-r]` | Bulk delete merged branches |

### Process (sourced/process.sh)

| Command | What it does |
|---------|-------------|
| `a_processList <name>` | List processes by name |
| `a_processKill <name>` | Kill processes by name |
| `a_process_kill_on_port <port>` | Kill process on port |
| `a_restart_login` | Restart macOS login window |

### Utilities (scripts)

| Command | What it does |
|---------|-------------|
| `a_uninstall_app.sh <app> [--delete]` | Uninstall macOS app + leftovers (dry run default) |
| `a_c_mcp_add` | Interactive Claude MCP server setup |
| `a_time_range.sh <start> <end>` | Print each date in range |

## Adding New Commands

1. Decide: does it need current shell context (cd, export)? -> `sourced/`. Otherwise -> `scripts/`.
2. Pick a prefix: `a_` (utility), `a_g_` (git), `a_c_` (claude/AI).
3. For new sourced categories, create `sourced/<name>.sh` and add a `source` line in `generic.profile`.
4. Scripts in `scripts/` are auto-added to PATH. No extra config needed.

## Sensitive Files (Never Commit)

- `~/my_settings/configs.profile`
- `~/.aws_keys`, `~/.my_secrets`
- Any org profile with real credentials
- `.claude/settings.local.json`

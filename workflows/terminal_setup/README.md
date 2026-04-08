# my-workflow

A modular collection of shell shortcuts, git helpers, and developer workflow scripts. Fork it, customize it, make it yours.

## What You Get

- **Git workflows** - `a_g_ship` (commit+push), `a_g_push` (pull-rebase+push), `a_g_main` (smart checkout)
- **Git worktree management** - Create, switch, remove worktrees with safety checks
- **Branch management** - Smart branch deletion that handles squash merges
- **Process utilities** - Kill by name, kill by port
- **macOS app uninstaller** - Remove apps + leftover Library files
- **Claude MCP setup** - Interactive tool to add MCP servers
- **Multi-org support** - Separate profiles per organization/machine

## Setup

### 1. Clone the repo

```bash
git clone <this-repo-url> /path/to/my-workflow
```

### 2. Create your config

```bash
mkdir -p ~/my_settings
cp /path/to/my-workflow/shell/configs.profile.sample ~/my_settings/configs.profile
```

Edit `~/my_settings/configs.profile` and set your paths:

```bash
export a_machine_type='m1'           # 'm1' or 'i7'
export a_company_name=''             # your org name, or leave empty
export a_dir_p_repos='/path/to/personal/repos'
export a_dir_w_repos='/path/to/work/repos'
export MY_WORKFLOW_DIR="${a_dir_p_repos}/my-workflow"
```

### 3. Source it from your shell

Add to `~/.zshrc` (or `~/.bashrc`):

```bash
source ~/my_settings/configs.profile
```

Reload:

```bash
source ~/.zshrc
```

### 4. (Optional) Add an org-specific profile

```bash
cp /path/to/my-workflow/shell/org.machine.profile.sample \
   /path/to/my-workflow/shell/mycompany.m1.profile
```

Set `a_company_name='mycompany'` in your configs.profile. The org profile auto-loads and is where you put SSH aliases, directory shortcuts, database connections, etc.

## Directory Aliases

Out of the box:

| Alias   | Goes to                |
|---------|------------------------|
| `cd_p`  | Personal repos dir     |
| `cd_w`  | Work repos dir         |
| `cd_wf` | This workflow repo     |

Add more in your org profile (e.g., `cd_api`, `cd_web`, `cd_infra`).

## Command Reference

### Git Workflows

| Command | Description |
|---------|-------------|
| `a_g_ship <msg>` | Stage + commit + pull-rebase + push (all-in-one) |
| `a_g_push` | Pull (rebase) then push current branch |
| `a_g_main` | Smart checkout main/master and pull latest |
| `a_g_reset` | Discard all local changes (confirms first) |

### Git Worktree

| Command | Description |
|---------|-------------|
| `a_g_worktree_init <branch> [-b base]` | Create worktree for a branch |
| `a_g_worktree_remove <name> [-v\|-f]` | Remove worktree (warns unpushed, -v verifies merged) |
| `a_g_worktree_conclude <name>` | Remove after verifying merged (alias for remove -v) |
| `a_g_worktree_list` | List all worktrees |
| `a_g_worktree_switch <name>` | Switch to a worktree |
| `a_g_worktree_main` | Return to main repo |
| `a_g_worktree_update` | Rebase current branch onto latest main |

See [docs/worktree.md](docs/worktree.md) for full documentation.

### Git Branch Management

| Command | Description |
|---------|-------------|
| `a_g_branch_delete <branch>` | Delete branch after verifying merged (handles squash merges) |
| `a_g_branch_delete <branch> -f` | Force delete, skip verification |
| `a_g_branch_cleanup` | Delete all local branches confirmed merged |
| `a_g_branch_cleanup -n` | Dry run - preview what would be deleted |
| `a_g_branch_cleanup -r` | Also delete remote branches |

### Process Management

| Command | Description |
|---------|-------------|
| `a_processList <name>` | List processes by name |
| `a_processKill <name>` | Kill processes by name |
| `a_process_kill_on_port <port>` | Kill process on a port |
| `a_restart_login` | Restart macOS login window |

### Other Utilities

| Command | Description |
|---------|-------------|
| `a_uninstall_app.sh <app> [--delete]` | Uninstall macOS app + leftovers (dry run by default) |
| `a_c_mcp_add` | Interactively add MCP servers to Claude |
| `a_time_range.sh <start> <end>` | Print date range (YYYY-MM-DD) |

## Project Structure

```
my-workflow/
├── shell/                         # Shell profile system
│   ├── configs.profile.sample     # Copy to ~/my_settings/configs.profile
│   ├── generic.profile            # Core profile (auto-loaded)
│   └── org.machine.profile.sample # Template for org-specific profiles
├── sourced/                       # Functions sourced into your shell
│   ├── git.sh                     # Git workflow commands
│   ├── worktree.sh                # Worktree helper functions
│   └── process.sh                 # Process management
├── scripts/                       # Standalone scripts (auto-added to PATH)
│   ├── a_g_worktree_init          # Create git worktrees
│   ├── a_g_worktree_remove        # Remove git worktrees
│   ├── a_g_branch_delete          # Smart branch deletion
│   ├── a_g_branch_cleanup         # Bulk merged branch cleanup
│   ├── a_uninstall_app.sh         # macOS app uninstaller
│   ├── a_c_mcp_add                # Claude MCP server setup
│   └── a_time_range.sh            # Date range utility
├── tools/                         # Standalone tools (self-contained)
│   └── slack-summarizer/          # Automated Slack briefing system
└── docs/                          # Documentation
    ├── worktree.md                # Worktree guide
    └── mac.md                     # macOS tips
```

## How It Works

```
~/.zshrc
  └── sources ~/my_settings/configs.profile  (your personal config)
        ├── sets MY_WORKFLOW_DIR, a_dir_p_repos, a_dir_w_repos
        └── sources shell/generic.profile
              ├── loads sourced/*.sh (git, worktree, process functions)
              ├── adds scripts/ to PATH
              ├── sets up cd_p, cd_w, cd_wf aliases
              └── loads shell/<org>.<machine>.profile (if configured)
```

## Customization

### Adding new commands

1. **Shell function** (needs current shell context, e.g., cd, export): Add to a file in `sourced/`
2. **Standalone script** (runs as subprocess): Add to `scripts/` - auto-available on PATH

### Naming convention

| Prefix | Meaning |
|--------|---------|
| `a_` | Personal utility command |
| `a_g_` | Git-related command |
| `a_c_` | Claude/AI tool command |

### Forking for your team

1. Fork this repo
2. Add your org profile in `shell/`
3. Customize `generic.profile` if needed
4. Each team member clones and creates their own `configs.profile`

## Tools

### [Slack Summarizer](tools/slack-summarizer/)

Automated Slack briefing system. Polls your Slack workspace via a local proxy, detects new messages using timestamp watermarks, generates AI summaries with Claude Haiku, and sends them to your DM.

**Features:** 10-minute polling, daily reports, nightly thread consolidation, watermark-based dedup, squash-merge-aware.

**Dependencies:**
- Python 3 (stdlib only, no pip)
- [Claude CLI](https://github.com/anthropics/claude-code) (`claude`) — for AI summarization
- A local Slack proxy (wraps Slack API, not included)
- [mdnest](https://github.com/nichochar/mdnest) — *optional*, for cloud-based persistent docs

**Publishing modes** (where living docs are stored):
| Mode | Description | Extra deps |
|------|-------------|------------|
| `local` | Writes to a local directory (default) | None |
| `mdnest` | Publishes via mdnest CLI | mdnest |
| `none` | Skip publishing | None |

See [tools/slack-summarizer/setup.md](tools/slack-summarizer/setup.md) for full setup instructions.

## Sensitive Files (Never Commit)

- `~/my_settings/configs.profile` - your personal paths
- `~/.aws_keys` - AWS credentials
- `~/.my_secrets` - other secrets
- Any `shell/<org>.<machine>.profile` with real credentials
- `tools/slack-summarizer/config.env` - Slack API keys, channel IDs

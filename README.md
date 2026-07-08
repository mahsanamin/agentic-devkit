# my_setup

A modular collection of shell shortcuts, git helpers, and developer workflow scripts. Fork it, customize it, make it yours.

## What You Get

- **Git workflows** - `a_g_ship` (commit+push), `a_g_push` (pull-rebase+push), `a_g_main` (smart checkout)
- **Git worktree management** - Create, switch, remove worktrees with safety checks
- **Branch management** - Smart branch deletion that handles squash merges
- **Process utilities** - Kill by name, kill by port
- **macOS app uninstaller** - Remove apps + leftover Library files
- **Claude MCP setup** - Interactive tool to add MCP servers
- **Claude skills** - Version-controlled skills, symlinked into `~/.claude/skills` so the source stays in sync
- **Multi-org support** - Separate profiles per organization/machine

## Setup

### Fast path

From a fresh clone, `install.sh` is the whole install: it wires the shell (creates `~/my_settings/configs.profile` from the sample with `MY_WORKFLOW_DIR` pointed at this checkout, appends the source line to `~/.zshrc`/`~/.bashrc`) and symlinks every skill + agent into `~/.claude/`. It is idempotent, so re-run it after a `git pull` to pick up new skills/agents.

```bash
git clone <this-repo-url> /path/to/my_setup
cd /path/to/my_setup
./install.sh          # wire shell + link all skills/agents (--link-only skips the shell step, -n dry-runs)
source ~/.zshrc
```

Then edit `~/my_settings/configs.profile` to fill in your repo paths and machine type. The manual steps below are only needed if you want to customize instead of using `install.sh`.

### 1. Clone the repo

```bash
git clone <this-repo-url> /path/to/my_setup
```

### 2. Create your config

```bash
mkdir -p ~/my_settings
cp /path/to/my_setup/shell/configs.profile.sample ~/my_settings/configs.profile
```

Edit `~/my_settings/configs.profile` and set your paths:

```bash
export a_machine_type='m1'           # 'm1' or 'i7'
export a_company_name=''             # your org name, or leave empty
export a_dir_p_repos='/path/to/personal/repos'
export a_dir_w_repos='/path/to/work/repos'
export MY_WORKFLOW_DIR="${a_dir_p_repos}/my_setup"
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
cp /path/to/my_setup/shell/org.machine.profile.sample \
   /path/to/my_setup/shell/mycompany.m1.profile
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
| `a_c_process_list <name>` | List processes by name |
| `a_c_process_kill <name>` | Kill processes by name |
| `a_c_process_kill_on_port <port>` | Kill process on a port |
| `a_c_restart_login` | Restart macOS login window |

### Other Utilities

| Command | Description |
|---------|-------------|
| `a_c_uninstall_app.sh <app> [--delete]` | Uninstall macOS app + leftovers (dry run by default) |
| `a_c_mcp_add` | Interactively add MCP servers to Claude |
| `a_c_skills <install\|uninstall\|status\|list>` | Symlink version-controlled skills into `~/.claude/skills` |
| `a_c_agents <install\|uninstall\|status\|list>` | Symlink version-controlled subagents into `~/.claude/agents` |
| `a_c_claude_remote <dir> [prompt]` | Launch `claude` in `<dir>` with Remote Control enabled (`--remote-control`), optionally seeded with a prompt |
| `a_c_review_pr <pr-url\|owner/repo#N> [-p auto\|draft] [-y] [-k] [-z session\|--no-zellij] [-n]` | Review a GitHub PR end-to-end from any terminal: resolve the repo to your local clone (`a_s_resolve_repo`), make a worktree on the PR head branch, launch Claude in auto mode running the `a_sk_l_review_pr` review, then tear the worktree + local branch down (remote untouched). When zellij is installed it runs in its own switchable tab `<repo>-Pr-<N>` in a `pr-reviews` session (created if absent) rather than taking over the terminal; `--no-zellij` to opt out. Idempotent: a repeat call for the same PR switches you to the existing review; `--fresh` to redo |
| `a_c_jira_task_start <ticket-url\|PROJ-123\|123> -r <repo> [feature] [-b base] [-z session] [-p kickoff] [-y] [--fresh] [-n]` | Start a task from a Jira ticket (number or URL) in one command. `-r <repo>` is REQUIRED (a Jira URL, unlike a PR URL, does not identify the repo). Worktree via `a_c_task_start`, then launch Claude in auto mode running `/aa-task-flow`. Source front over the generic `a_c_task_start` engine (a GitHub-issue front would be a sibling). Idempotent: a repeat call for the same ticket resumes the existing task; `--fresh` to recreate |
| `a_c_idea_start <idea-name> "<prompt>" [-t tab] [-z session\|--no-zellij] [-s] [-n]` | Spin up a fresh idea scratch dir (`<cd_w>/ideas/<idea-name>`, override with `$A_C_IDEAS_DIR`) and launch Claude there in **full auto** (`--dangerously-skip-permissions`, since it is your own empty greenfield sandbox) + Remote Control, inside an `ideas` zellij session (override with `-z`/`$A_C_IDEAS_ZELLIJ_SESSION`) under a tab named for the idea (override with `-t`). Reuses `a_c_claude_remote` + the `a_task_zellij_*` helpers; `-s`/`--safe` steps down to the gentler acceptEdits posture, `-n` to dry-run |
| `a_c_zellij_fix [session] [-d\|-r\|--no-refocus] [-l]` | Repair a script-created zellij session. Fixes both (1) TINY SIZE: detaches all clients (kills only `zellij attach` client procs, never the `--server`, so running Claude/shells survive) then re-attaches you at full size; and (2) BACKSPACE-NAVIGATES-TABS: walks every tab and moves keyboard focus onto the shell pane (off the tab-bar plugin). `-r`/`--refocus-only` does JUST the focus fix on an already-attached session (safe from anywhere), `--no-refocus` does size only, `-d` detaches only, `-l` lists sessions + attached client PIDs. Run the size fix from a terminal OUTSIDE the target session. Session defaults to `$ZELLIJ_SESSION_NAME` |
| `a_s_resolve_repo <pr-url\|owner/repo>` | Resolve a PR/repo reference to your LOCAL clone path (cache → `cd_w` scan → clone), never duplicating an existing clone |
| `a_s_time_range.sh <start> <end>` | Print date range (YYYY-MM-DD) |

## Project Structure

```
my_setup/
├── install.sh                     # One-shot bootstrap: wire the shell + link all skills/agents
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
│   ├── a_c_uninstall_app.sh       # macOS app uninstaller
│   ├── a_c_mcp_add                # Claude MCP server setup
│   ├── a_c_skills                 # Symlink Claude skills into ~/.claude/skills
│   ├── a_c_agents                 # Symlink Claude subagents into ~/.claude/agents
│   ├── a_c_claude_remote          # Launch claude in a dir with Remote Control on
│   └── a_s_time_range.sh          # Date range utility
├── skills/                        # Version-controlled Claude Code skills
│   ├── README.md                  # Skills + symlink-install guide
│   └── <skill>/SKILL.md           # One dir per skill (symlinked when installed)
├── agents/                        # Version-controlled Claude Code subagents
│   ├── README.md                  # Agent catalog + conventions
│   └── <name>.md                  # One file per subagent (symlinked when installed)
├── rules/                         # Shared rule files imported into CLAUDE.md
├── tools/                         # Standalone tools (self-contained)
│   ├── slack-summarizer/          # Automated Slack briefing system
│   └── mdcf/                      # Markdown <-> Confluence CLI
└── docs/                          # Documentation
    ├── worktree.md                # Worktree guide
    ├── task.md                    # Ticket -> worktree task flow
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

## Skills

[Claude Code skills](skills/) live in `skills/`, under version control. The `a_c_skills` command symlinks each one into `~/.claude/skills/`, so editing a skill here (or `git pull`ing an update) changes the live skill with no reinstall.

```bash
a_c_skills install   # symlink every repo skill into ~/.claude/skills
a_c_skills status    # show link state for each skill
```

See [skills/README.md](skills/README.md) for the full guide and the list of bundled skills.

## Agents

[Claude Code subagents](agents/) live in `agents/`, one `.md` per agent, also under version control. `a_c_agents` symlinks each into `~/.claude/agents/` the same way `a_c_skills` does. They are a project-agnostic library: each defers to the conventions of whatever project spawns it. See [agents/README.md](agents/README.md) for the catalog.

```bash
a_c_agents install   # symlink every repo agent into ~/.claude/agents
a_c_agents status    # show link state for each agent
```

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

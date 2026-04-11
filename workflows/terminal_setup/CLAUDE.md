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

## Key Architecture

- `MY_WORKFLOW_DIR` is the single root variable. Set in user's `configs.profile`. Everything derives from it.
- `generic.profile` sources `sourced/*.sh`, adds `scripts/` to PATH, loads org profile.
- `sourced/` files run in current shell (can cd, export). `scripts/` run as subprocesses.

## Adding New Commands

1. Needs current shell context (cd, export)? -> `sourced/`. Otherwise -> `scripts/`.
2. Pick a prefix: `a_` (utility), `a_g_` (git), `a_c_` (claude/AI).
3. New category? Create `sourced/<name>.sh` and add a `source` line in `generic.profile`.
4. Scripts in `scripts/` are auto-added to PATH.

## Sensitive Files (Never Commit)

- `~/my_settings/configs.profile`
- `~/.aws_keys`, `~/.my_secrets`
- Any org profile with real credentials
- `.claude/settings.local.json`

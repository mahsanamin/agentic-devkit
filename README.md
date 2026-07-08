# agentic-devkit

**Your whole dev setup in one git repo: a powerful terminal + git workflow, plus a version-controlled library of AI coding agents that stay in sync on every machine.**

## The problem

Shell shortcuts, git helpers, and now your AI coding agents and skills pile up as copy-pasted files scattered across machines. They drift. You improve something on your laptop and your desktop never gets it. A new machine means hunting down all the pieces again.

## The fix

agentic-devkit keeps all of it in one git repo and symlinks the AI parts straight into your Claude Code setup, so:

- **Edit once, live everywhere.** The live skills/agents in `~/.claude/` are symlinks back into this repo.
- **`git pull` updates your whole setup**, no reinstall.
- **One command** sets up a fresh machine end to end.

## What's inside

- **Terminal + git workflow** - git worktree management, squash-merge-aware branch cleanup, one-shot commit+push, process/port killers, macOS helpers.
- **AI skills** - reusable Claude Code skills for the repetitive parts: commit, open a PR, review a PR, raise test coverage, turn a rough idea into a clean automation prompt.
- **AI subagents** - a project-agnostic library of 30+ specialized agents (code review, debugging, refactoring, testing, incident triage, and a full autonomous build pipeline). Each adapts to whatever project it runs in.
- **Standalone tools** - a Markdown to Confluence CLI, a Slack briefing system, and more.

## Quick start

```bash
git clone <this-repo-url> ~/agentic-devkit
cd ~/agentic-devkit
./install.sh        # wires your shell + links every skill/agent into ~/.claude
source ~/.zshrc
```

That is the whole install. Re-run `./install.sh` after any `git pull` to pick up new skills/agents. Then edit `~/my_settings/configs.profile` to point at your repo paths.

## How it works

One variable, `MY_WORKFLOW_DIR`, is the root. Everything derives from it, and the AI pieces are symlinks so this repo stays the single source of truth.

```
~/.zshrc -> ~/my_settings/configs.profile -> shell/generic.profile
   loads sourced/*.sh (git, worktree, process) + puts scripts/ on PATH
   ~/.claude/skills/*  and  ~/.claude/agents/*  ->  symlinks into this repo
```

## Learn more

- `skills/README.md` - the skill catalog
- `agents/README.md` - the subagent catalog
- `docs/worktree.md`, `docs/task.md`, `docs/mac.md` - deep dives
- `CLAUDE.md` - the full model and naming conventions

## Never commit these (all gitignored by default)

`~/my_settings/configs.profile`, `~/.aws_keys`, `~/.my_secrets`, any `shell/<org>.<machine>.profile`, and `tools/*/config.env`.

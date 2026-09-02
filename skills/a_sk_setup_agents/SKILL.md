---
name: a_sk_setup_agents
description: Set up or update this agentic-devkit for Claude Code, Codex, and Gemini/AGY on the current machine. Use for "set up my agentic devkit", "install my agent skills", "make my AI setup work in Codex and Gemini", "sync all coding agents", or after pulling this repo on a new machine. Inspects first, uses the idempotent installer, preserves existing guidance, verifies symlinks, and never changes provider credentials.
---

# Set up the multi-agent devkit

Use the repository's own scripts; do not reproduce their filesystem logic by hand.

## Procedure

1. Read `README.md` and `docs/multi-agent.md` from `MY_WORKFLOW_DIR` (or the current repository if that variable is not set).
2. Inspect without changing anything:
   - `git status --short --branch`
   - `./install.sh --dry-run`
   - whether `~/.claude`, `~/.codex`, `~/.gemini`, and `~/.agents/skills` already exist
3. Explain any divergent real skill directory or existing provider instruction file that the installer will preserve or back up.
4. Run `./install.sh` unless the user named a single provider; then use `--provider claude`, `codex`, `agy`, or `gemini-cli`. `--provider gemini` selects both Google clients.
5. Source the shell profile only when needed for the current shell. Never edit provider authentication, API keys, or login state.
6. Verify:
   - repo skills resolve through `~/.claude/skills` when Claude was selected
   - repo skills resolve through `~/.agents/skills` when Codex or Gemini was selected
   - Claude subagents resolve through `~/.claude/agents`
   - Codex subagents are valid generated TOML in `~/.codex/agents`
   - AGY subagents have `subagent: true` in `~/.gemini/config/agents`
   - `a_c_agent_memory check --provider <selection>` succeeds after guidance has been adopted
   - `a_c_workflow_doctor` reports no setup errors
7. Tell the user to start a fresh agent session. Give the provider-native check from `docs/multi-agent.md`.

## Safety boundaries

- Do not replace divergent files without the installer's backup behavior.
- Do not copy skills; keep repository-backed symlinks.
- Do not edit generated provider agents; change the canonical file under `agents/` and reinstall.
- If global guidance has not been adopted yet, show `a_c_agent_memory diff` before building it.

---
name: a_sk_setup_agents
description: Set up or update this agentic-devkit and its configured overlays for Claude Code, Codex, and Gemini/AGY on the current machine. Use for "set up my agentic devkit", provider setup, installing agent skills, syncing coding agents, or after pulling the repos on a new machine. Setup is cross-provider by default regardless of which agent runs it; it preserves existing guidance and never changes provider credentials.
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
4. Run `./install.sh` with no provider filter. The agent executing the setup does not define its
   scope: Claude must also install and verify Codex, Codex must also install and verify Claude,
   and either must include configured Google clients and overlays. Use `--provider` only when the
   user explicitly says to leave the other providers untouched; merely naming the agent they are
   currently using is not a request to narrow setup.
5. Source the shell profile only when needed for the current shell. Never edit provider authentication, API keys, or login state.
6. Verify:
   - repo and configured-overlay skills resolve through `~/.claude/skills` and `~/.agents/skills`
   - Claude subagents resolve through `~/.claude/agents`
   - Codex subagents are valid generated TOML in `~/.codex/agents`
   - AGY subagents have `subagent: true` in `~/.gemini/config/agents`
   - `a_c_agent_memory check --provider all` succeeds after guidance has been adopted
   - each global file identifies its own runtime provider and never claims to be another one
   - `a_c_workflow_doctor` reports no setup errors
7. Tell the user to start a fresh agent session. Give the provider-native check from `docs/multi-agent.md`.

## Safety boundaries

- Do not replace divergent files without the installer's backup behavior.
- Do not copy skills; keep repository-backed symlinks.
- Do not edit generated provider agents; change the canonical file under `agents/` and reinstall.
- A setup request authorizes adopting managed global guidance because handwritten content is
  preserved. Show the diff first when a divergent provider file will be incorporated.
- Treat `AGENTS.md` as repository guidance source of truth. `CLAUDE.md` and `GEMINI.md` are bridge
  files only; do not let provider-specific copies drift.

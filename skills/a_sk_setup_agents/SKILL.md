---
name: a_sk_setup_agents
description: Set up or update this agentic-devkit, its configured overlays, and the organisation root repo it reads, for Claude Code, Codex, and Gemini/AGY on the current machine. Use for "set up my agentic devkit", provider setup, installing agent skills, syncing coding agents, or after pulling the repos on a new machine. Setup is cross-provider by default regardless of which agent runs it; it preserves existing guidance and never changes provider credentials.
---

# Set up the multi-agent devkit

Use the repository's own scripts; do not reproduce their filesystem logic by hand.

## Phase 0: the root repo, if there is one

A root repo owns the paths and the rules for an organisation, and this devkit reads its
`root.config`. Read `docs/root-repo.md` for the contract. Skip this phase only when the user has
no root repo and does not want one; everything below still works standalone.

1. Establish `A_ROOT_DIR`. If the user has a root repo that is not cloned here, clone it first:
   it names every other repo, so nothing else can be resolved until it exists. If they have none
   and want one, `a_c_root_init <dir> --org "<name>"` creates it from the starter template.
2. Read its `root.config`. For every `*_DIR` role that is not on this machine, clone it from the
   matching `*_REMOTE` into exactly the path the key names. Skip empty values: empty means "not
   wanted here". Ask before cloning anything the config does not name, and ask which roles this
   machine should not have. Set each clone's git identity as you go; there is deliberately no
   global one, so a fresh clone commits under the wrong name.
3. Create `root.local.config` with the keys that differ on this machine. `MACHINE_NAME` always,
   and `ROOT_BASE_DIR` when the layout differs, since every other path derives from it. Never
   edit `root.config` for one machine's sake.
4. Verify every `*_DIR` resolves or is deliberately empty. Show the user that list.
5. Wire the shell with the four line handoff from `docs/root-repo.md`, backing up any existing
   profile with a timestamp first. The logic belongs in `shell/bootstrap.profile`; do not copy
   its contents into the user's home.
6. **Check what the shell sources after that file.** Anything redefining the same alias or
   variable later silently wins, and it is slow to diagnose because every variable still reads
   correctly while the alias is wrong. List what you find before removing a line from a file you
   did not write.
7. Give this machine an identity file at `machine/<MACHINE_NAME>.md` in the overlay whose content
   it matches. Company facts go in the org overlay, never in an overlay flagged
   `*_NO_ORG_CONTENT`.

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
7. If guidance was adopted from a hand written file, prove nothing was lost: take every
   distinctive term from the backup and show which file now carries it. Anything with no new home
   is a real loss. Fix it before calling the setup done.
8. Tell the user to start a fresh agent session. Give the provider-native check from `docs/multi-agent.md`.

## Safety boundaries

- Do not replace divergent files without the installer's backup behavior.
- Do not copy skills; keep repository-backed symlinks.
- Do not edit generated provider agents; change the canonical file under `agents/` and reinstall.
- A setup request authorizes adopting managed global guidance because handwritten content is
  preserved. Show the diff first when a divergent provider file will be incorporated.
- Treat `AGENTS.md` as repository guidance source of truth. `CLAUDE.md` and `GEMINI.md` are bridge
  files only; do not let provider-specific copies drift.

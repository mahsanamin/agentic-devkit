# Claude, Codex, and Gemini/AGY compatibility

This devkit uses shared sources where the tools have a real common format and small adapters where they do not. The goal is one maintained workflow, not three copies that drift.

## Compatibility map

| Capability | Source in this repo | Claude Code | Codex | Gemini CLI / AGY |
|---|---|---|---|---|
| Repository guidance | `AGENTS.md` | `CLAUDE.md` imports it | native | `GEMINI.md` imports it |
| Global guidance | `memory/` + optional overlay | `~/.claude/CLAUDE.md` | `~/.codex/AGENTS.md` | `~/.gemini/GEMINI.md` |
| Reusable workflows | `skills/*/SKILL.md` | `~/.claude/skills` | `~/.agents/skills` | Gemini CLI: `~/.agents/skills`; Antigravity: `~/.gemini/config/skills` and `~/.gemini/antigravity-cli/skills` |
| Custom subagents | `agents/*.md` | supported | not installed | not installed |
| Shell commands | `scripts/` + `sourced/` | shared through the shell | shared through the shell | shared through the shell |

`AGENTS.md` is the canonical repository file because Codex reads it natively and it is the broadest cross-tool convention. The two one-line bridge files are deliberately not independent instruction files:

```text
CLAUDE.md -> @AGENTS.md
GEMINI.md -> @AGENTS.md
```

This avoids symlinks in a repository checkout, which are awkward on Windows, while keeping one editable source.

## Why skills are shared but subagents are not

All three tools support the open Agent Skills shape: a directory containing `SKILL.md` with `name` and `description` frontmatter. Codex and Gemini CLI discover user skills from `~/.agents/skills`, while Claude uses `~/.claude/skills`. Antigravity has separate global IDE and `agy` CLI paths. `install.sh` links the same source directories into every applicable location. Skills marked `providers: claude` are deliberately filtered out of the shared locations.

Custom subagent definitions are different. The files in `agents/` contain Claude tool names and Claude model selectors such as `opus`. Installing those unchanged into another provider would look successful while producing broken or misleading behavior. Cross-provider procedures therefore belong in `skills/`; `agents/` remains an honest Claude adapter until there is a stable shared subagent schema.

## Install and update

Install all providers:

```bash
./install.sh
source ~/.zshrc
```

Install only one provider:

```bash
./install.sh --provider claude
./install.sh --provider codex
./install.sh --provider gemini
./install.sh --provider agy      # alias for the Gemini/Google adapter
```

The provider selector also controls which global guidance file is rebuilt. Existing hand-written content outside the devkit's managed markers is preserved.

Inspect or rebuild guidance independently:

```bash
a_c_agent_memory status
a_c_agent_memory diff
a_c_agent_memory build
a_c_agent_memory build --provider codex
```

The older `a_c_claude_memory` command remains available for backwards compatibility and operates on one Claude-style target file. New automation should use `a_c_agent_memory`.

## Provider-native verification

After installation, start a fresh session because instruction discovery normally happens at session startup.

- Claude Code: run `/memory` and confirm the global `CLAUDE.md`; invoke a shared skill with `/a_sk_<name>`.
- Codex: ask it to summarize active instructions; invoke a skill with `$a_sk_<name>`.
- Gemini CLI: run `/memory show` and `/skills list`; use `/skills reload` after changing a skill in a running session.

## Sources used for this design

- [Claude Code extension overview](https://code.claude.com/docs/en/features-overview)
- [OpenAI: custom instructions with AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [OpenAI: build skills](https://learn.chatgpt.com/docs/build-skills)
- [Gemini CLI: GEMINI.md context files](https://geminicli.com/docs/cli/gemini-md/)
- [Gemini CLI: Agent Skills discovery](https://geminicli.com/docs/cli/using-agent-skills/)
- [Google Antigravity: global skill locations](https://antigravity.google/docs/skills/)
- [Google Antigravity CLI migration paths](https://antigravity.google/docs/gcli-migration)
- [Inventive HQ comparison supplied with this change](https://inventivehq.com/blog/claude-md-vs-agents-md-vs-gemini-md)

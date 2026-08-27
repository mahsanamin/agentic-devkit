# Claude, Codex, and AGY/Gemini compatibility

This devkit maintains one canonical workflow and emits provider-native assets where schemas
differ. Claude, Codex, and AGY are first-class targets; Gemini CLI is supported as an additional
Google target.

## Compatibility map

| Capability | Canonical source | Claude Code | Codex | AGY / Antigravity | Gemini CLI |
|---|---|---|---|---|---|
| Repository guidance | `AGENTS.md` | `CLAUDE.md` imports it | native | `GEMINI.md` imports it | `GEMINI.md` imports it |
| Global guidance | `memory/` + overlay | `~/.claude/CLAUDE.md` | `~/.codex/AGENTS.md` | `~/.gemini/GEMINI.md` | `~/.gemini/GEMINI.md` |
| Skills | `skills/*/SKILL.md` | `~/.claude/skills` | `~/.agents/skills` | `~/.gemini/config/skills` + open alias | `~/.agents/skills` |
| Subagents | `agents/*.md` | direct Markdown links | generated `.toml` | generated `.md` | generated `.md` |
| Shell commands | `scripts/` + `sourced/` | shared shell | shared shell | shared shell | shared shell |

`AGENTS.md` is the canonical repository file. The bridge files contain only imports:

```text
CLAUDE.md -> @AGENTS.md
GEMINI.md -> @AGENTS.md
```

## Canonical agents and provider adapters

Every agent is authored once under `agents/<name>.md`. Its body is the provider-neutral role and
procedure. The frontmatter expresses a workload tier and capabilities in the existing canonical
vocabulary. `scripts/a_s_render_agent` converts that source during installation:

| Canonical tier | Claude | Codex default | AGY default | Gemini CLI default |
|---|---|---|---|---|
| `haiku` | Haiku | `gpt-5.6-luna`, low | `flash` | `gemini-3.5-flash-lite` |
| `sonnet` | Sonnet | `gpt-5.6-terra`, medium | `flash` | `gemini-3.6-flash` |
| `opus` | Opus | `gpt-5.6`, high | `pro` | `gemini-3.1-pro-preview` |

These are workload and cost-tier mappings, not model-equivalence claims. Codex mappings can be
overridden with `CODEX_AGENT_MODEL_HAIKU`, `CODEX_AGENT_MODEL_SONNET`, and
`CODEX_AGENT_MODEL_OPUS`; equivalent `*_EFFORT_*` variables control reasoning effort. AGY uses
its stable `flash` and `pro` routing tiers.

Claude tool names in canonical frontmatter are translated to documented AGY names such as
`Read` to `view_file`, `Bash` to `run_command`, and `Edit` to `replace_file_content`. Codex
agents inherit available tools and receive a safety boundary derived from required capabilities.
Provider-only or MCP tools are resolved by the active provider environment.

Generated files contain a managed marker. Reinstalling refreshes stale adapters. The installer
never silently overwrites an unmanaged agent: it skips the collision, or with `--force`, backs
the existing file up before replacing it. Edit only the canonical `agents/*.md` source.

## Install and update

```bash
./install.sh                    # every provider
./install.sh --provider claude
./install.sh --provider codex
./install.sh --provider agy
./install.sh --provider gemini-cli
./install.sh --provider gemini # both Google clients
```

Granular agent management uses the same provider names:

```bash
a_c_agents --provider codex status
a_c_agents --provider codex install a_sag_code_reviewer
a_c_agents --provider agy uninstall a_sag_code_reviewer
```

The provider selector also controls global guidance rebuilding. Existing handwritten content
outside the devkit's managed markers is preserved.

## Provider-native verification

Start a fresh session after installation.

- Claude Code: run `/agents`; invoke a shared skill with `/a_sk_<name>`.
- Codex: run `/agent`; confirm `a_sag_*` custom agents are available and invoke one explicitly.
- AGY: run `/agents`; confirm the custom agents are listed and can be delegated through
  `invoke_subagent`.
- Gemini CLI: run `/agents`, `/memory show`, and `/skills list`.

Automated coverage in `tests/test_multi_agent_install.sh` renders the whole library, parses every
Codex TOML file, checks model and tool mappings, verifies provider paths, and repeats installation
to prove idempotency.

## Primary references

- [Claude Code extension overview](https://code.claude.com/docs/en/features-overview)
- [OpenAI Codex subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- [OpenAI AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [Google Antigravity subagents](https://antigravity.google/docs/subagents)
- [Gemini CLI subagents](https://geminicli.com/docs/core/subagents/)
- [Gemini CLI Agent Skills](https://geminicli.com/docs/cli/skills/)
- [Inventive HQ comparison supplied with this change](https://inventivehq.com/blog/claude-md-vs-agents-md-vs-gemini-md)

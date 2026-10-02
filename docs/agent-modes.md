# Machine interaction modes

Use `agentic` for everyday autonomous development, `interactive` when you want
to review permission escalations, and `auto` for unattended tasks with access
configured in advance. All modes tell agents to carry forward task authorization
and avoid asking about routine implementation choices.

The feature is opt-in. An ordinary install without `A_AGENT_MODE` or
`--agent-mode` leaves provider permissions unchanged.

```sh
./install.sh --agent-mode agentic --dry-run
./install.sh --agent-mode agentic
a_c_agent_mode status --project /path/to/project
```

To keep that choice across installer runs, set `export A_AGENT_MODE=agentic` in
your root repo's **local** `root.local.config`, or in `~/my_settings/configs.profile`
for a standalone machine. The installer flag overrides that machine selection
for the installation. The installer does not write the selection back to those
files. `--provider codex` scopes installation to one provider.

## Provider behavior

| Mode | Codex | Claude Code | Gemini CLI |
|---|---|---|---|
| `interactive` | Workspace sandbox, user reviews escalations, network disabled | `default` | `default` |
| `agentic` | Workspace sandbox, automatic approval review, network enabled | `auto` classifier | `auto_edit`; shell/tool prompts remain |
| `auto` | Workspace sandbox, network enabled, `never` asks for approval | `dontAsk` | Unsupported; unchanged |

AGY/Antigravity has no adapter here: the command reports it as unsupported and
leaves its settings unchanged. A multi-provider install reports unsupported
mappings and applies the supported ones; requesting an unsupported provider/mode
alone exits with an error. No mode enables unrestricted access, YOLO, or permission
bypass. Codex and Claude automatic-review modes require a CLI that advertises the
capability; account or managed-policy restrictions can still prevent its use.

**`auto` cannot escalate.** An action needing approval is denied, even when it
would have been reasonable for a human to approve it. The agent must report the
blocker and unfinished work. Use `agentic` when automatic review is needed to
complete work beyond the sandbox. These defaults do not grant authorization for
unrelated messages, merges, deployments, or destructive work.

## Scope and session overrides

The installer merges only the mode's keys into user settings:

- Codex: `$CODEX_HOME/config.toml`, defaulting to `~/.codex/config.toml`.
- Claude: `$CLAUDE_CONFIG_DIR/settings.json`, defaulting to `~/.claude/settings.json`.
- Gemini CLI: `~/.gemini/settings.json`.

It also maintains a separate interaction-guidance block in each supported
provider's global instructions, outside the memory builder's managed block.
Existing models, MCP definitions, hooks, trust entries, permission lists and other
settings survive. Changed files get private sibling `*.before-mode-*` backups;
identical reinstalls create no backups. Malformed files and symlink destinations
are refused. TOML comments outside changed assignments are preserved. Inline tables
mixing mode keys with unrelated keys may need conversion to normal TOML tables.

Add only the extra writable directories a Codex task needs. Existing writable
roots are preserved, and the installer never infers broad paths from a machine:

```sh
a_c_agent_mode install --provider codex --mode agentic --writable-root "$HOME/.gradle"
```

Project settings, CLI flags, managed requirements, and active-session permissions
can override these defaults. `status` prints user permission values and candidate
project override files without dumping unrelated settings or credentials; it does
not claim to know the effective running session. No configuration file alters an
already-running session. Restart the client to load changed defaults.

For a single CLI session, `run` passes native mode flags without editing files:

```sh
a_c_agent_mode run --provider codex --mode agentic --project /path/to/project
a_c_agent_mode run --provider codex --mode auto --project /path/to/project -- exec 'Run the unit tests and report failures'
a_c_agent_mode run --provider claude --mode interactive
a_c_agent_mode run --provider claude --mode auto -- -p 'Run the unit tests and report failures'
```

Arguments after `--` pass through unchanged, so explicit provider arguments can
override the mode. `--dry-run` prints the command. The `auto` launcher requires a
headless task. Install once to get the shared interaction guidance; `run` itself
only controls execution permissions. Authentication or initial trust setup must
be completed before scheduling unattended work.

Existing Claude task launchers honor `A_AGENT_MODE` through their shared permission
resolver. `A_TASK_PERMISSION_MODE` and explicit launcher permission flags still
take precedence. With no machine mode selected, their existing fallback is unchanged.

## Sources and verification

Canonical mode mappings live in `config/agent-modes/modes.json`; common interaction
instructions live in `config/agent-modes/guidance.md`.

- [Codex configuration precedence](https://developers.openai.com/codex/config-basic)
- [Codex approval behavior](https://developers.openai.com/codex/agent-approvals-security)
- [Claude permission modes](https://code.claude.com/docs/en/permissions)
- [Gemini CLI configuration](https://geminicli.com/docs/reference/configuration/)

Run `python3 -m unittest discover -s tests -p 'test_agent_modes.py'` (Python 3.11+).
Tests use temporary provider homes and mock CLI capabilities; they do not invoke
models or change live machine permissions.

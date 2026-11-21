# Changelog

One entry per release. The newest is at the top.

## v1.2.1 (2026-11-21)

- a_c_task_start: a ticket is optional, and Jira is not assumed (fixes #5)

## v1.2.0 (2026-11-21)

- Keep a private checkout path and a machine name out of public files
- Slack agents: use the user's local time, not a fixed zone
- fix(scripts): a_c_claude_profile keeps API-key auth out of profiles
- feat(scripts): per-profile usage view, session tools follow CLAUDE_CONFIG_DIR
- feat(scripts): a_c_claude_profile for extra Claude commands sharing ~/.claude
- rules: judge "is it done" against the ticket's Done when and scope, not a brief
- rules: re-check a status right before you report it
- answer-style: say done or nothing plainly, follow-ups only as tickets
- core-rules: give full URLs for referenced links
- Stop spawning read-only agents with worktree isolation
- Add a_c_keyring_unlock: stop a locked GNOME keyring from hanging tools on a headless machine
- a_c_zellij_tab: --close-on-exit and --pid-file
- Fix settings dry-run to read the on-disk registry
- Add pending blog and issue tools with safer approvals
- a_c_claude_settings: install missing marketplaces and plugins on apply
- a_c_claude_settings: layered Claude Code settings, applied by install.sh
- a_c_claude_remote: honour the newer bypass acceptance setting
- launchd: daily full disk cleanup replaces the Docker-only job
- a_c_docker_cleanup: time out the daemon check instead of hanging
- AGENTS.md: git work in this repo needs no caution; document OpenCode targets
- Add a_c_claude_loose: loosen Claude settings.json with backup and undo
- commit-and-push: in own repos pull with a plain merge, no rebase
- commit-and-push: never hand over a heredoc, keep handed-over commands short
- Add OpenCode as an install provider
- a_sk_message_writer: no invented contrasts, no unasked ownership notes
- Message writer lessons, and committing past an attribution hook in own repos
- Add a_sag_stale_ticket_investigator: check whether worked tickets with no PR are actually finished
- a_sag_ticket_pr_matcher: the PR must be in the repo of the system the ticket names
- Add a_sag_ticket_pr_matcher: match leftover tickets to the PRs that delivered them
- Docs: describe the single rendered guidance file and the Claude import
- Render global guidance once and let Claude import it
- Jira and Confluence agents try the acli CLI before MCP
- agents: add a_sag_slack_reader and a_sag_slack_writer, route Slack reads to the reader
- doctor: suggest one combined pull for all stale repos, then a single install
- a_c_uninstall: find a tool by name, confirm, move it and its leftovers to the Trash
- task launch: support explicit Claude and Codex providers
- a_c_tailscale_fix: restore a dropped route into the Tailscale tunnel
- prompt: match the machine name case-insensitively
- doctor/install: find repos that were moved and repoint the config
- doctor: route asset and guidance repairs through install
- doctor: match recovery commands to overlay roles
- doctor: simplify overlay setup prompts
- doctor: ask which overlay role to restore
- install.sh: verify shell wiring and guide repository recovery
- answer-style: GitHub replies are short and in simple English
- Memory: point at an mdnest-served brain when it is not cloned locally
- Doctor: tell the user exactly how to fix a missing overlay
- install.sh: a failing overlay no longer stops the install
- Doctor: say why each link is wrong, and fix the safe cases
- install.sh: give overlay installers this checkout's commands
- install.sh: config backups are readable by the owner only
- install.sh: point the machine config at the checkout it runs from
- Public default branch stays main; PRs still target develop
- Contributors work through forks; the machine move is maintainer-only

## v1.1.0 (2026-10-11)

- CI: pass PR-controlled values through env, not into the shell
- Public repo takes PRs into develop; releases go through a release PR

## v1.0.0 (2026-10-11)

- Versioned releases and a move script for the private working copy
- a_c_claude_memory: a block whose source moved is not a dropped block

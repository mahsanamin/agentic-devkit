---
name: a_sk_setup_claude
providers: claude
description: Compatibility route for older requests that explicitly name Claude setup. Whole-machine setup, devkit installation, updates, new-machine onboarding, skills, agents, overlays, and global guidance belong to a_sk_setup_agents so Claude and Codex remain peers. Use this route directly only when the user explicitly requires Claude-only scope and says to leave other providers untouched.
---

# Route Claude setup into the shared setup

For any ordinary setup, install, update, repair, or new-machine request, read and follow
`../a_sk_setup_agents/SKILL.md`. Do not infer Claude-only scope merely because Claude received the
request or the user said “set up Claude.” The default outcome includes Claude Code, Codex,
Gemini/AGY, configured overlays, and provider-correct global guidance.

Use a Claude-only install only when the user explicitly says the other providers must remain
untouched. In that case, follow the shared setup procedure with `--provider claude`, verify
`~/.claude/CLAUDE.md`, skills, and agents, and report that Codex and Gemini were intentionally
skipped.

For cleanup of unmanaged or conflicting files specifically inside `~/.claude`, use
`a_sk_tame_claude`; cleanup is distinct from cross-provider setup.

Never hand-copy skills or agents and never edit generated global guidance directly.

# File templates

Exact structure for the four tracker files. Keep the shape stable across runs so diffs are clean and the merge rules in SKILL.md work. Dates are ISO (YYYY-MM-DD), from the real environment date. No em or en dashes anywhere.

---

## terms.md

```markdown
# Claude Terms and Features I Track

> Living inventory, maintained by the a_r_l_claude_watch skill. Last updated: YYYY-MM-DD.
> Status: 🟢 using now · 🟡 evaluating or adopting · ⚪ not yet · 🔴 tried and dropped

## Part A: My stack (using now)

| Feature / technique | What it is | Where I use it | Status |
|---|---|---|---|
| Skills | Reusable, model-invocable workflow packages | aa-framework, my_setup, global ~/.claude | 🟢 |
| /goals (Stop-hook goals) | Persist a goal that blocks stopping until met | daily in Claude Code | 🟢 |
| Subagents / custom agents | Delegated, parallel task runners | aa-code-reviewer, aa-test-runner, Explore | 🟢 |
| Git worktrees + aa_g_worktree_* | Isolated working copies per branch/PR | aa-framework helpers | 🟢 |
| ... | ... | ... | 🟢 |

## Part B: Watchlist (new or unused, ranked by fit)

| Feature | What it is | Why it fits me | Status | First seen |
|---|---|---|---|---|
| <feature> | <one line> | <tied to something real in my stack> | 🟡 | YYYY-MM-DD |
| <feature> | <one line> | <why> | ⚪ | YYYY-MM-DD |
```

Notes:
- Part A is built from `probe.sh` output plus a read of the aa-framework and global config. Do not invent entries. The probe already filters the obvious noise, but stay alert: `*-workspace` directories are eval artifacts, not skills, and plugin internals are not features. List the real plugin names (from `installed_plugins.json`), real skills, real routines.
- Part B items must carry a concrete, personal "why it fits me" referencing how he actually works, not a generic benefit.
- When a Part B item starts showing up in the probe, move it to Part A and flip to 🟢.

---

## news.md

```markdown
# Claude News

> Notable Claude and Anthropic news, newest first. Maintained by a_r_l_claude_watch.
> Each entry ends with why it matters to me specifically.

## YYYY-MM

### YYYY-MM-DD: <headline>
- **What:** <one or two lines>
- **Source:** <url>
- **Relevance to me:** <one line, or "low" if it is just for completeness>

## Archive (older than ~3 months)

<entries moved down here, same format, not deleted>
```

Notes:
- Key entries by (date, headline) to dedupe. Prepend new months/entries so newest stays on top.
- Keep "Relevance to me" honest. If something is industry news with no bearing on his work, mark it low rather than inflating it.

---

## best_practices.md

```markdown
# Claude Best Practices and Strategy

> How I get the most out of Claude, and how I stay current. Maintained by a_r_l_claude_watch.

## Adopt next (ranked)

1. **<feature or practice>:** what it is, and a concrete first step for my setup.
2. ...

## Practices I follow

- <durable habit, e.g. "orchestrate multi-step work with aa-task-flow + subagents">
- ...

## How I stay updated (the monitoring system)

- **Sources watched:** Claude Code changelog, docs release notes, Anthropic news, claude-code-guide agent (see the skill's references/sources.md).
- **Cadence:** weekly, via a scheduled a_r_l_claude_watch run.
- **How to run manually:** invoke a_r_l_claude_watch, or say "what's new with Claude / update my Claude tracker".
- **Where it lives:** StayUptoDate/Claude/ in mdnest.
```

Note: the list uses a hyphen only as the numbered-bullet glyph. Never put an em or en dash inside a sentence; use a colon or parentheses (as the example above does).

---

## _state.md

```markdown
# _state (bookkeeping for a_r_l_claude_watch, do not hand-edit)

```json
{
  "resolved_base": "@srv-ahsan-mini/mahsan_brain/StayUptoDate/Claude",
  "last_run": "YYYY-MM-DD",
  "claude_code_version_seen": "x.y.z",
  "claude_code_version_installed": "x.y.z",
  "aa_framework_version_seen": "x.y.z",
  "sources_checked": ["claude-code-guide", "docs release-notes", "anthropic news"],
  "last_change_summary": "one line on what changed this run"
}
```
```

Note: that is a fenced json block inside the markdown file. Read it back next run to get the watermark.

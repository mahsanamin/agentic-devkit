# Catalog formats

Templates for what `a_r_l_session_digest` writes. Keep these stable so entries stay consistent run to run. No em dashes anywhere.

## Enriched session entry (lean)

Path: `<base>/<project>/<sessionId>.md`

Frontmatter is deliberately tiny: in SilverBullet the frontmatter renders as a grey block, so a big YAML wall looks ugly. Keep it to a handful of query-useful keys and let the name + summary be the first visible thing. Composed by `compose-entry.sh`.

```markdown
---
project: my-service
outcome: investigation
digested: 2026-06-22
tags: [PROJ-980, checkout-flow, aa-ticket-creator]
---

# Traced premature ORDER_CONFIRMED state, filed PROJ-980

Two to three sentences: what was attempted and what actually happened or landed. Written from the distillation, not invented.

`claude --resume 654d3c46-2c05-4d1f-afda-8baa7a1d17d9`

- my-service · `main` · 48 turns · 3 files · 2026-06-19 -> 2026-06-22
- outcome: short note, with PR link or branch if there was one
- tools: Edit(12) Bash(9) Read(7) ...
- dir: `$HOME/repos/my-service`

## What happened

- Concrete step one.
- Concrete step two.

## Code paths

`path/to/file.kt` and what changed, or "no code changes; Jira ops / research / docs".

## Files edited

- `path/to/file.kt`
```

Rules:
- Frontmatter keys: `project`, `outcome`, `digested`, `tags` only. Dates are date-only (not full ISO). The session id lives in the filename and the resume line; cwd/branch/host/transcript live in the body, not frontmatter.
- `outcome` is one of: `completed`, `partial`, `abandoned`, `investigation`, `ops-admin`, `unknown`.
- Keep the H1 equal to the subagent `headline`. The summary paragraph comes right after the H1 (no `## Summary` heading needed).

## `_index.md` line format

Newest first. One line per digested session:

```markdown
# ClaudeSessions index (newest first, N sessions)

Scope: only sessions under cd_w ($HOME/repos).

- `2026-06-22` **my-service** Traced premature ORDER_CONFIRMED state, filed PROJ-980 (`investigation`) `claude --resume 654d3c46`
- `2026-06-22` **my-web** Reconciled PROJ-694 epic tickets to Done (`ops-admin`) `claude --resume 4af00683`
```

## `_state.md` shape

Machine bookkeeping, not for humans.

```markdown
# session-digest state

last_run: 2026-06-22
digested_this_run: 12
total_digested: 47
last_summary: 12 sessions digested across my-service and web; 18 candidates remain (max cap).
```

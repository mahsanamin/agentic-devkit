---
name: a_r_l_claude_watch
description: Keep Ahsan current on Claude. Researches what is new and what is coming across Claude Code, the Claude apps, the API, models, and Anthropic announcements, then reconciles it against the toolkit he already uses (aa-framework skills/agents/rules, his global ~/.claude config, the my_setup repo, /goals, worktrees, hooks, MCP, scheduled routines) and maintains a living tracker in mdnest at StayUptoDate/Claude/ (terms.md, news.md, best_practices.md). Use this whenever he asks what is new with Claude, what he should start using, to update or refresh his Claude tracker or "StayUptoDate" notes, to catch up on Claude Code releases or the changelog, to inventory which Claude features he actually uses, or when a scheduled "claude watch" run fires. Trigger even when he does not name the files: "what's new in Claude", "am I missing any Claude features", "update my Claude notes", "catch me up on Claude Code", "anything new I should adopt", "is /goals-style stuff still the latest", all count.
---

# a_r_l_claude_watch

Keep Ahsan from falling behind on Claude. Every run does the same thing: find what changed, compare it to what he already uses, decide what is worth adopting, and write it down where he will see it. The output is a living tracker in mdnest, not a chat answer that evaporates.

The reason this is a skill and not a background crawler: fetching release notes is the easy, cheap part. The part that earns its keep is judgment, reconciling new features against *his* stack and saying "you do X heavily, so start using Y." That cannot be precomputed, so it runs fresh each time. Continuous coverage comes from scheduling this skill (see Scheduling), not from a daemon.

## What you maintain

Base location in mdnest: the user's PERSONAL brain at `@srv-ahsan-mini/mahsan_brain/StayUptoDate/Claude/` (server `brain.i.mahsanamin.com`). This is the path he pastes as `mdnest://@srv-ahsan-mini/mahsan_brain/StayUptoDate/Claude`. Critical: this personal brain (`mahsan_brain`) is a DIFFERENT server from the work brain (`@work/my_brain` on `work-brain.example.com`). Do not confuse them; the tracker belongs in the personal brain only. Confirm the alias at runtime (step 0), since alias names can differ per machine.

Four files live there:

| File | Role |
|---|---|
| `terms.md` | Living inventory. Part A: the Claude features and techniques he uses now. Part B: a ranked watchlist of things he does not use yet but should consider. This is the heart of the tracker. |
| `news.md` | Dated log of notable Claude / Anthropic news, newest first, each with a one-line "why this matters to him". |
| `best_practices.md` | Strategies worth adopting given his stack, plus the description of the monitoring system itself (sources, cadence, how to run this skill). |
| `_state.md` | Machine bookkeeping (last run date, versions seen, sources checked). Not for humans. You read it to compute "what changed since last time" and rewrite it at the end. |

Exact structure for each file is in `references/file-templates.md`. Read it before writing any file so the format stays consistent run to run.

## The run loop

Do these in order. Steps 2 and 3 can overlap (kick off research while the probe runs).

### 0. Resolve the mdnest base path

Start from the known-good answer and confirm it, rather than parsing blindly. The base is `@srv-ahsan-mini/mahsan_brain/StayUptoDate/Claude` (server `brain.i.mahsanamin.com`, the personal brain). If a prior run left a `resolved_base` in `_state.md`, prefer that. Confirm with `mdnest list @srv-ahsan-mini`, which should return the `mahsan_brain` namespace. Do NOT write to the work brain `@work/my_brain`: it is a different server and the wrong home for this tracker.

Only if `@srv-ahsan-mini` is not configured locally, fall back to `mdnest servers -v`. Run it in full and do not truncate the output (the list can be longer than the first rows suggest, which is exactly how a past run wrote to the wrong brain). Find the alias whose URL is `brain.i.mahsanamin.com` with the `mahsan_brain` namespace. Watch out: the VERSION column wraps onto a second line, so a single server's row spans two lines. Match the namespace to its alias, not to a line.

The base is then `<alias>/<namespace>/StayUptoDate/Claude`. If `StayUptoDate/Claude` does not exist yet, this is a first run (see Bootstrap). Record the resolved base in `_state.md` so later runs can sanity-check it.

### 1. Read current state

Read all four files if they exist (`mdnest read <base>/terms.md`, etc.). `_state.md` gives you the watermark: `claude_code_version_seen` and `last_run`. Everything you research in step 3 is framed as "what is new since that watermark." If the files do not exist, go to Bootstrap.

### 2. Probe the local toolkit and latest versions

Run the bundled probe (read-only, no network writes, no mdnest):

```bash
bash <skill-dir>/scripts/probe.sh
```

It prints a markdown report: installed vs latest Claude Code version, aa-framework version, and the current lists of aa-framework skills/agents/rules, global `~/.claude` skills, my_setup skills, installed plugins, and scheduled routines. This is the deterministic source of truth for "what he uses", so terms.md Part A is built from this, not from memory. If the probe fails (offline, paths moved), fall back to reading the directories yourself, but say so in your report.

### 3. Research what is new

Your training cutoff is months behind today, so never populate versions, release notes, or news from memory. Verify against live sources. Use `references/sources.md` for the canonical list. In short:

- For Claude Code, the API, and the SDK, prefer the `claude-code-guide` agent (it is purpose-built and has web access). Ask it specifically: "what shipped in Claude Code since version `<watermark>`, and what is announced as coming?"
- For release notes and the changelog, WebFetch the canonical docs and GitHub pages in `references/sources.md`.
- For broader announcements (models, app features, pricing), run a few targeted WebSearch queries scoped to recent months.

Anchor on the watermark and today's date so you collect deltas, not the whole history again.

### 4. Reconcile into the files

This is the judgment step. For each new feature or change you found, ask: does he already use this (in the probe output)? If yes, make sure terms.md Part A reflects it. If no, does it fit how he works? If it fits, add it to the watchlist (Part B) with a concrete "why it fits you" tied to something real in his stack (for example: "you orchestrate with aa-task-flow subagents, so X would let you...").

Apply the merge rules below. Then refresh `best_practices.md` "Adopt next" so its top items match the highest-fit watchlist entries, and append any genuinely notable news to `news.md`.

### 4.5. Self-verify and fix

Before you trust the output, check it adversarially. This skill's failure modes are subtle: a feature half-remembered from stale training, a wrong version-to-feature mapping, probe noise listed as a feature, a model recommended that was actually pulled. Read `references/verify.md` and run its rubric. If subagents are available, spawn one verifier agent, hand it the rubric and the file paths, and tell it to assume there are mistakes; otherwise run the checklist inline with the same skepticism. Fix every high and medium finding (a contradicted fact is high), re-check those, and only then continue. Do not spin on low-severity nits.

### 5. Write `_state.md`

Update `last_run` (today's date, real, from the environment), `claude_code_version_seen` (latest you confirmed), `aa_framework_version_seen`, `sources_checked`, and a one-line `last_change_summary`. This is what makes the next run incremental instead of redundant.

### 6. Report to the user

In chat, give a tight summary: the 1 to 3 things actually worth his attention this run, what you added to the watchlist, and what you recommend adopting first. Link the tracker. Do not paste the whole files back; the value is the short "here is what changed and what to do about it."

## Merge rules (never clobber)

These files accumulate over time and may carry his own edits. Treat every write as a merge, not an overwrite.

- **terms.md**: key entries by feature name. Update the row if it exists, add it if new. Never drop an existing row just because this run did not re-mention it. If a watchlist item now shows up in the probe, move it from Part B to Part A and mark it 🟢 using.
- **news.md**: key entries by (date, headline). Skip anything already logged. Prepend new items so newest stays on top. Move entries older than about three months under the Archive heading rather than deleting them.
- **best_practices.md**: this one is more curated, so it is fine to rewrite the "Adopt next" list each run, but preserve any "Practices I follow" notes and the "How I stay updated" section unless something genuinely changed.
- Respect status markers a human set (for example a 🔴 "tried, dropped"). Do not re-recommend something he explicitly dropped without a clear new reason, and if you do, note why.

## First run (bootstrap)

When `StayUptoDate/Claude/` does not exist, you are seeding the tracker. This run is heavier and that is expected, since the user explicitly wants his current Claude techniques captured.

1. Create the folder by writing the files; `mdnest append <path> - < tmpfile` makes parent folders on the fly (see the mdnest note in Guardrails).
2. Build terms.md Part A from a thorough pass over the probe output plus a read of the aa-framework (`skills/`, `agents/`, `rules/`, the top of `CHANGELOG.md`) and the global `~/.claude` setup. Capture the real vocabulary he works in: skills, subagents/agents, slash commands like `/goals`, session forks, worktrees and the `aa_g_worktree_*` helpers, hooks (PreToolUse guards, Stop-hook goals), MCP servers, scheduled routines, memory, plan mode. Cross-check `references/file-templates.md` for the shape.
3. Seed the watchlist with current Claude features he is not yet using, researched live in step 3.
4. Seed news.md with the most notable items from roughly the last quarter.
5. Write best_practices.md including the "How I stay updated" section so the system documents itself.
6. Write `_state.md`.

## Scheduling (how this becomes "always watching")

Recommend running this weekly as a routine rather than relying on the user to remember. Offer to set it up with the `/schedule` skill, something like a Monday-morning run with the prompt "run a_r_l_claude_watch: check for new Claude updates since last run and refresh my StayUptoDate/Claude tracker." Because the run is incremental off `_state.md`, a weekly cadence stays cheap. Mention this once; do not nag if he declines.

## Guardrails

- **Live sources over memory, always.** A confident-sounding version number or feature from training data is the main failure mode here. If you cannot verify something live, mark it clearly as unconfirmed rather than stating it.
- **Prefer primary sources.** Ground version and feature claims in the official changelog (`code.claude.com/docs/en/changelog.md`) and `anthropic.com` / `docs.claude.com`. A third-party blog or aggregator is acceptable only when no primary source exists, and then label that entry "(third-party, unconfirmed)". A primary source can also override a stale changelog: a model can read as GA in the changelog but be suspended on the Anthropic news page, so for model availability and other high-stakes claims, check the news page too.
- **No em dashes or en dashes anywhere** in the files or your messages (a standing user preference). Use commas, periods, colons, or parentheses.
- **mdnest writes (avoid the `-` footgun)**: `mdnest create <path> [content]` takes content as a literal positional arg and does NOT read stdin, so `mdnest create <path> -` stores a literal dash. Only `write`, `append`, and `prepend` accept `-` for stdin. So for any multi-line file: write the full content to a local temp file, then pipe it in. New file: `mdnest append <path> - < tmpfile` (append creates the file and parent folders if missing). Existing file: `mdnest write <path> - < tmpfile`. Always read first, merge in memory, write the whole file, then read it back to confirm. On read-back the remote byte count should be within one byte of local (mdnest may normalize the trailing newline), so treat an exact match or local-plus-one as success and anything else as a real mismatch. Diagrams in the files use Mermaid, not ASCII.
- Keep the chat report short. The tracker is the artifact; the report is just the pointer to what changed.

## Reference files

- `references/sources.md`: canonical sources to check each run, which to fetch how, and the watchlist of source URLs.
- `references/file-templates.md`: exact structure for terms.md, news.md, best_practices.md, _state.md.
- `references/verify.md`: the adversarial self-verify rubric for step 4.5.

## Run logging (visibility)

When this run finishes (success, partial, nothing-to-do, or failure), call the **a_sag_routine_logger** sub-agent once (Agent tool, `subagent_type: a_sag_routine_logger`) with `routine=<this skill's name from the frontmatter above>`, a `status`, and a one-line `summary` of what the run did. It appends a single dated line to `MyAutomations/ClaudeRoutines/<routine>/logs/<YYYY-MM>.md`, so the last run and what it did are visible at a glance. Keep the summary to ONE line. Logging is best-effort: if the mdnest CLI is unavailable (e.g. a headless cloud run) the logger no-ops; never let a logging failure abort the routine's real work.

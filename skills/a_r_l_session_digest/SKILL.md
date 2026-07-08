---
name: a_r_l_session_digest
description: Collect Claude Code sessions that are now closed or have gone untouched for over a week, summarize what each one actually did (intent, what happened, code paths touched, outcome), and write a readable digest into Ahsan's session catalog in mdnest (@work/my_brain/ClaudeSessions) plus a rolled-up index. The per-session hook only captures thin live entries; this routine turns the closed/idle ones into real summaries so the catalog is browsable instead of raw. Use whenever he asks to digest, summarize, collect, or clean up his Claude sessions, to catch up on what past sessions were about, to backfill summaries for old sessions, to refresh the ClaudeSessions catalog or index, or when a scheduled "session digest" run fires. Triggers even without the exact name: "summarize my closed sessions", "what were my sessions about this week", "collect the stale Claude sessions", "make my session catalog useful", "digest sessions older than N days" all count. Parameterized: stale_days, max, project filter.
---

# a_r_l_session_digest

A per-session hook (`~/.claude/scripts/session-catalog/mirror-session.sh`) drops a thin entry into mdnest the moment any session starts or ends: project, branch, intent, files edited, tools, and a `claude --resume` line. That keeps the catalog current but shallow. This routine is the second half: it finds sessions that are **closed or idle**, reads what they actually did, and writes a real **summary** into each entry, so the catalog answers "what was this session, and did it land?" rather than dumping raw metadata.

The split is deliberate. The hook must be instant and bash-only (it runs on every session), so it cannot summarize. Summarizing needs to read the transcript and exercise judgment, which is batch work that belongs here and is too expensive to do per session or to keep in the main context. So this routine distills each transcript to a small artifact with a script, then hands that to a subagent to summarize. Continuous coverage comes from scheduling this skill, not from a daemon.

## What you maintain

Base location in mdnest: the **work brain** at `@work/my_brain/ClaudeSessions` (server `work-brain.example.com`). This is the same catalog the hook writes to. Note this is a DIFFERENT server from the personal brain `@srv-ahsan-mini/mahsan_brain` that other trackers use; the session catalog lives in the work brain only.

```
ClaudeSessions/
  <project>/<sessionId>.md   # one entry per session (hook creates thin, this enriches)
  _index.md                  # rolling list of digested sessions, newest first
  _state.md                  # machine bookkeeping: last run, counts, watermark
```

Local bookkeeping (not in mdnest):
- `~/.claude/scripts/session-catalog/digested.tsv` — `sessionId<TAB>mtimeEpoch` lines. The dedup ledger: a session is re-digested only if its transcript changed since last time.

## Parameters (fill from the invocation, else use defaults)

| Param | Default | Meaning |
|---|---|---|
| `stale_days` | 7 | transcript untouched longer than this counts as stale |
| `max` | 30 | cap sessions digested this run (newest first); re-run to chew through a backlog |
| `project` | (none) | substring filter on cwd/project, e.g. `my-service` |
| `dest` | `@work/my_brain/ClaudeSessions` | catalog base |

A scheduled invocation looks like: `run a_r_l_session_digest with stale_days=7 max=30`.

## The run loop

### 0. Resolve and verify the catalog base

Default base is `@work/my_brain/ClaudeSessions`. Confirm `@work` is reachable: `mdnest list @work` should return `["my_brain"]`. If it returns `401 invalid API token`, STOP and tell Ahsan to re-auth with `mdnest login @work https://work-brain.example.com <token>` (the catalog cannot be written until then). Only fall back to `mdnest servers -v` if `@work` is not configured at all.

### 1. Read state

`mdnest read <base>/_state.md` for the last run date and counts (best-effort; absent on first run). The real dedup ledger is the local `digested.tsv`, which `scan.sh` consults directly, so you do not need to read every entry back.

### 2. Scan for candidates

```bash
STALE_DAYS=<stale_days> MAX=<max> MIN_TURNS=2 bash <skill-dir>/scripts/scan.sh <project-filter>
```

It prints JSONL, one candidate per line: `{sessionId, project, cwd, transcript, lastTouched, mtimeEpoch, ageDays, state}` where `state` is `closed`, `stale`, or `stale-and-closed`. It already excludes live sessions and anything in `digested.tsv` with an unchanged mtime.

**Scope + labels (shared with the hook).** `scan.sh` sources `~/.claude/scripts/session-catalog/catalog-lib.sh`, which defines `CATALOG_ROOTS` (default `$HOME/repos`, i.e. `cd_w`). Only sessions whose cwd is at/under a catalog root are emitted, so random `$HOME`/scratch sessions never reach the catalog. `project` is the real repo name (worktrees under `.../Repos/WorkTrees/<repo>/<branch>` fold back to `<repo>`), not the cwd basename. `MIN_TURNS` (default 0) skips sessions with fewer than that many user turns; use `MIN_TURNS=2` for backfills so empty/aborted sessions do not each consume a subagent. To widen scope, export `CATALOG_ROOTS="/path/a:/path/b"`. If it prints nothing, the catalog is up to date: report that and stop (cheap no-op, the point of the ledger).

### 3. Distill + summarize each candidate (fan out)

For each candidate, the work is independent, so parallelize with subagents (batch ~5-8 at a time to stay within limits; cap total at `max`). Per candidate:

1. Distill the transcript to a small artifact:
   ```bash
   bash <skill-dir>/scripts/distill.sh "<transcript>"
   ```
   This is a few KB: intent, the arc of user asks, files edited, tool usage, notable git/PR actions, and the final notes. **Do not read the raw transcript into your own context** (they run to megabytes); the distillation is the input.
2. Hand the distillation to a subagent and have it return a structured summary. Require this exact shape (use a schema if the tooling supports it):
   - `headline` — one line, <=80 chars, what this session was about. Lead with the concrete subject (ticket like PROJ-123, feature, bug, or file/area). NO filler like "Session about", "Worked on", "Discussion of". For a thin/empty session, name it as such (e.g. "orientation stub, no work done").
   - `summary` — 2 to 4 sentences: what was attempted and what actually happened / landed.
   - `whatHappened` — 3 to 6 short bullets of the concrete steps.
   - `codePaths` — the key files or areas changed, or "no code changes" plus what kind of work it was (Jira ops, research, Datadog, docs, etc.).
   - `outcome` — one of `completed | partial | abandoned | investigation | ops-admin | unknown`, with a short note (PR link or branch if there was one).
   - `tags` — a few keywords (tickets like PROJ-980, area names).
   Instruct the subagent: summarize only from the distillation, do not invent, and if the distillation is thin say so rather than guessing.

### 4. Write each entry (merge, never blind-overwrite)

Save the subagent's JSON to a temp file, then compose the entry deterministically:

```bash
bash <skill-dir>/scripts/compose-entry.sh "<transcript>" "<summary.json>" "<today>" > entry.md
```

`compose-entry.sh` pulls the factual signals (branch, files, dates, turns, tools, intent) straight from the transcript and fills the narrative (`## Summary`, `## What happened`, `## Code paths`, `## Outcome`) from the summary JSON, matching `references/entry-template.md`. Then write it:

- mdnest write footgun: `mdnest create <path> [content]` takes content as a literal arg and does NOT read stdin. For multi-line content, write to a local temp file and pipe: existing file `mdnest write <path> - < tmp`; new file `mdnest append <path> - < tmp` (append creates the file and parent folders). Read it back and confirm the byte count is within one of local.
- If the hook already created a thin entry, this overwrites it with the rich version (keep the hook's `cwd`, `startedAt`, `transcript`, `resume` facts; they are also in the distillation).

After a successful write, append `"<sessionId>\t<mtimeEpoch>"` to `~/.claude/scripts/session-catalog/digested.tsv` so the next run skips it.

### 5. Update the index

Prepend a one-line entry per newly digested session to `<base>/_index.md` (newest first): date, project, headline, and the resume command. Keep it a flat skimmable list (see `references/entry-template.md` for the line format). Do not duplicate lines for sessions already listed.

### 6. Write `_state.md` and report

Update `_state.md`: `last_run` (today, real date from the environment), `digested_this_run`, `total_digested` (line count of `digested.tsv`), and a one-line `last_summary`. Then give Ahsan a tight chat report: how many sessions digested, the 2 to 3 most notable (with their headline and outcome), how many candidates remain (if `scan.sh` was capped by `max`), and the index link. Do not paste full entries back.

## Guardrails

- **Never digest a live session.** `scan.sh` already excludes sessions whose process is alive; do not bypass it.
- **Dedup is the whole point of cheap re-runs.** Always append to `digested.tsv` after a write, and never re-summarize an unchanged transcript.
- **Distillation in, not raw transcripts.** Transcripts are huge; only the distilled artifact (and subagents) should ever hold their content. This keeps the run affordable.
- **Cost scales with `max`.** Each candidate is one subagent. For a first run against a large backlog, expect `max` subagents; raise `max` deliberately, and tell Ahsan how many candidates remain so he knows to re-run or schedule.
- **mdnest writes**: pass content as a positional arg via `create <path> "$content"` (else `write`), reading the file with the bash builtin `content="$(<entry.md)"`. Do NOT use `create <path> -` (stores a literal dash). work brain `@work` only, never the personal brain.
- **Run the write loop in a clean shell.** The interactive profile (sourced on every shell) munges `PATH` after the first `mdnest` call, so a loop that calls `mdnest` then any external command (`cat`, `jq`, `wc`) fails with "command not found" from the second iteration on. Put the compose+write loop in a script and run it with `bash --noprofile --norc <script>`, set `PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin` at the top, and use absolute binaries (`/usr/bin/jq`, `/usr/local/bin/mdnest`). This is the single most common way this routine breaks.
- **No em dashes or en dashes** anywhere in entries or your messages (standing preference). Use commas, periods, colons, parentheses. Diagrams in Mermaid, not ASCII.
- **Do not delete transcripts.** This routine reads and summarizes; it never removes local session files. (If Ahsan later wants archival/pruning, that is a separate, explicitly-confirmed step.)

## Scheduling (how this becomes "always tidy")

This is a LOCAL routine (it reads `~/.claude/projects` transcripts and uses the `mdnest` CLI), so it must run on the local machine. Do NOT use `/schedule`: that creates cloud agents which cannot see local transcripts or run mdnest, so a cloud routine would fail every run. Schedule it locally instead.

Current setup (installed 2026-06-22): a macOS LaunchAgent `com.ahsan.claude.session-digest` (`~/Library/LaunchAgents/com.ahsan.claude.session-digest.plist`) runs daily at 03:23 local via `~/.claude/scripts/session-catalog/run-digest.sh`, which calls `claude -p "run a_r_l_session_digest with stale_days=7 max=40" --dangerously-skip-permissions` and logs to `~/.claude/scripts/session-catalog/digest-cron.log`. Because of the `digested.tsv` ledger the run is incremental: the first run clears the backlog (capped by `max`), later runs only touch newly closed/idle sessions, so a daily cadence stays cheap. To change cadence edit the plist's `StartCalendarInterval` and reload; to disable, `launchctl bootout gui/$(id -u)/com.ahsan.claude.session-digest` and remove the plist.

## Reference files

- `references/entry-template.md`: the exact enriched entry format, the `_index.md` line format, and the `_state.md` shape.

## Install

Symlinked into `~/.claude/skills/` by the repo installer: `a_c_skills install a_r_l_session_digest`.

## Run logging (visibility)

When this run finishes (success, partial, nothing-to-do, or failure), call the **a_sag_routine_logger** sub-agent once (Agent tool, `subagent_type: a_sag_routine_logger`) with `routine=<this skill's name from the frontmatter above>`, a `status`, and a one-line `summary` of what the run did. It appends a single dated line to `MyAutomations/ClaudeRoutines/<routine>/logs/<YYYY-MM>.md`, so the last run and what it did are visible at a glance. Keep the summary to ONE line. Logging is best-effort: if the mdnest CLI is unavailable (e.g. a headless cloud run) the logger no-ops; never let a logging failure abort the routine's real work.

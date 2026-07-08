---
name: a_r_l_ai_watch
description: Keep Ahsan current on the broader AI field, not Claude specifically (Claude has its own tracker, a_r_l_claude_watch). Collects and curates general AI news, research advancements, new tools and technology, and emerging terminology into a segregated tracker in mdnest at StayUptoDate/GloballyAI/ (news.md, advancements.md, technology.md, terms.md). Built to run unattended on a local 24/7 machine multiple times a day: it works off a timestamp watermark, dedupes against what it already logged, and no-ops cheaply when nothing is new. Use whenever he asks what is new in AI, for AI news or advancements, new AI models, tools, or products, new AI terms or jargon, to update or refresh his GloballyAI or "globally AI" tracker, or when a scheduled "AI watch" routine fires. Trigger even without the file names: "what's happening in AI", "any big AI news today", "new models or tools this week", "what does <new AI term> mean", "catch me up on the AI field" all count.
---

# a_r_l_ai_watch

Keep Ahsan current on the AI field as a whole. Each run pulls the latest happenings, decides what is genuinely worth keeping, sorts each item into the right file, and writes it down, newest first. The output is a living, segregated tracker in mdnest. This is the wide-angle companion to `a_r_l_claude_watch`: that one is deep on Claude and his own toolkit, this one is the broad landscape (OpenAI, Google, Meta, open models, research labs, startups, tooling, policy).

This skill is designed to run unattended on his local 24/7 machine, possibly several times a day. So two things matter on every run: it must be cheap when little has changed, and it must never duplicate what it already logged. Both come from the watermark and dedup discipline below. Treat them as load-bearing, not optional.

## What you maintain

Base location: `@srv-ahsan-mini/mahsan_brain/StayUptoDate/GloballyAI/` (his personal brain, server `brain.i.mahsanamin.com`, the path he pastes as `mdnest://@srv-ahsan-mini/mahsan_brain/StayUptoDate/GloballyAI`). This is the SAME personal brain as the Claude tracker but a different folder. Do not confuse `mahsan_brain` (personal) with the work brain `@work/my_brain`; the tracker belongs in the personal brain only. Resolve the alias at runtime (step 0).

Four content files, segregated by kind, plus bookkeeping:

| File | Holds | Shape |
|---|---|---|
| `news.md` | Time-sensitive happenings: launches, funding, partnerships, policy, company moves, notable drama. The "what happened". | Dated log, newest first |
| `advancements.md` | Capability and research progress: new SOTA models, benchmark jumps, papers, novel methods, scaling results. The "what got better or newly possible". | Dated log, newest first |
| `technology.md` | Concrete tools, products, frameworks, infra, APIs, hardware a builder could actually use. The "what I could build with". | Dated log, newest first |
| `terms.md` | New terminology and concepts entering the field, each defined plainly. The "what does this word mean". | Glossary table, append by term |
| `_state.md` | Bookkeeping: `last_run` timestamp, `seen_keys` for dedup, summary. Not for humans. | JSON in a fenced block |

Routing rule when an item could fit more than one file: put it in ONE file, the most specific. A new model release that beats benchmarks goes to advancements; the same model getting a public API goes to technology; a funding round or lawsuit goes to news; a new word like "test-time compute" goes to terms. Exact structure for each file is in `references/file-templates.md`; read it before writing.

Anthropic and Claude items: a high-level Anthropic headline can appear in news for field completeness, but anything about Claude features, the API, or his own tooling belongs in the Claude tracker, not here. Do not duplicate.

## The run loop

### 0. Resolve the base path

The base is `@srv-ahsan-mini/mahsan_brain/StayUptoDate/GloballyAI`. Prefer the `resolved_base` recorded in `_state.md` if present. Confirm with `mdnest list @srv-ahsan-mini` (it should return the `mahsan_brain` namespace). If `@srv-ahsan-mini` is not configured locally, run `mdnest servers -v` IN FULL (do not truncate, the list can be longer than the first rows suggest) and find the alias whose URL is `brain.i.mahsanamin.com` with namespace `mahsan_brain`. The VERSION column wraps across two lines, so match the namespace to its alias, not to a line. If the four files do not exist yet, this is a first run (see Bootstrap).

### 1. Read state and the watermark

Read `_state.md`. It gives you `last_run` (an ISO timestamp, not just a date) and `seen_keys` (recently logged item keys). Everything this run collects is framed as "newer than `last_run`". Also skim the top of each content file so you know what is already there. If files do not exist, go to Bootstrap.

### 2. Stamp the run time

Get the current UTC timestamp now, from the environment, not memory: `date -u +%Y-%m-%dT%H:%M:%SZ`. You will write this as the new `last_run` at the end, and use it for today's date heading.

### 3. Gather candidates (cheap firehose first, then editorial)

Run the bundled fetcher for the deterministic, high-volume sources (Hacker News + arXiv), scoped to the watermark:

```bash
python3 <skill-dir>/scripts/fetch_feeds.py --since "<last_run>"
```

It prints a deduped, timestamped digest of candidate items with stable keys (`hn:<id>`, `arxiv:<id>`). These are leads, not final entries; many will be noise. Then supplement with a few targeted WebSearch queries for the editorial layer the fetcher cannot see (major lab and company announcements, product launches, funding, policy). See `references/sources.md` for the source list and query patterns. Keep it bounded: a handful of searches, scoped to recent days.

### 4. Dedup hard

For each candidate, build its key (the source key from the fetcher, or a normalized URL, or `title|outlet`). Drop it if the key is in `seen_keys` OR if it already appears in the relevant file. This is what makes running five times a day safe: only genuinely new items survive. If nothing survives, that is a valid and common outcome; skip to step 7 and write only the `last_run` bump (no content writes, no noise).

### 5. Curate and route

From the survivors, keep what is actually significant (a real advance, a usable tool, a meaningful headline, a term worth knowing), not every link. Route each kept item into exactly one file per the routing rule, write a one-line "why it matters" or definition, and place it newest-first under today's date heading (or as a new glossary row for terms). Apply the merge rules below.

### 6. Self-verify

Read `references/verify.md` and run its rubric. If subagents are available, spawn a verifier and have it check the output adversarially; otherwise check inline. Fix high and medium findings (a wrong attribution or a dead/incorrect source is high), then continue.

### 7. Update `_state.md`

Set `last_run` to the timestamp from step 2. Append the new item keys to `seen_keys` and trim to the most recent ~500. Write a one-line `last_change_summary` (for example "added 3: 2 advancements, 1 tool" or "no new items"). This is what makes the next run incremental.

### 8. Report (brief, routine-friendly)

One or two lines: how many items you added and to which files, plus the single most interesting thing if any. When run as an unattended routine the report is mostly for the log, so when nothing changed, say exactly that in one line. Do not paste file contents.

## Merge rules (never clobber)

- **Dated logs (news, advancements, technology)**: key by (date, headline) and by URL. Prepend new items so newest stays on top, under the right date heading. Never rewrite or drop existing entries. Move entries older than about two months under an Archive heading rather than deleting.
- **terms.md**: key by term. Add a row if the term is new; leave existing rows alone. Never re-add a term already present.
- Respect anything a human edited or annotated. If you would re-surface something marked resolved or dismissed, do not, unless there is a clear new development, and then note it.

## First run (bootstrap)

When `StayUptoDate/GloballyAI/` does not exist, seed all four files. This run is heavier. Use `--since` of roughly the last 2 to 4 weeks so the tracker starts with real recent content rather than empty. Cap it: aim for a useful handful per file (around 5 to 10 strong items each), not an exhaustive dump. Create the files (see the mdnest note in Guardrails), then write `_state.md` with the bootstrap timestamp and the seen_keys you logged.

## Scheduling (local, frequent)

This is meant to run as a LOCAL routine on his always-on machine, not in the cloud. Recommend a schedule as frequent as hourly or as light as once a day; either is fine because the run is incremental and no-ops cheaply when nothing is new. Offer to set it up with the `/schedule` skill (local execution) or his existing local routine mechanism, with a prompt like "run a_r_l_ai_watch: collect new AI news, advancements, tools, and terms since last run into my GloballyAI tracker". Mention it once.

## Guardrails

- **Live sources over memory, always.** Your training is months stale. Never log a version, date, or claim from memory. Verify it live, and if you cannot, either drop it or label it clearly unconfirmed.
- **Prefer primary sources.** A lab or company's own blog, the paper, the product page, or a major outlet beats an aggregator or a random blog. When the only source is weak, label the entry "(unconfirmed)" and hedge the relevance. Treat Hacker News and similar as a discovery layer: follow the link to the primary source before logging.
- **Do not embellish.** An entry states only what its cited source actually says. Do not add benchmark names, numbers, valuations, or head-to-head comparisons from memory or inference; if the source does not say it, leave it out. When several entries come from one announcement, cite the same working primary source on each; never reuse a stub or dead URL.
- **No em dashes or en dashes anywhere** in the files or your messages (a standing user preference). Use commas, periods, colons, or parentheses. Diagrams use Mermaid, not ASCII.
- **mdnest writes (avoid the `-` footgun)**: `mdnest create <path> [content]` takes content as a literal arg and does NOT read stdin, so `create <path> -` stores a literal dash. Only `write`, `append`, and `prepend` read `-`. So write full content to a local temp file, then pipe it: new file `mdnest append <path> - < tmpfile` (creates file and parent folders), existing file `mdnest write <path> - < tmpfile`. Read back to confirm; remote bytes should be within one of local (trailing-newline normalization).
- **Stay cheap.** This runs often. Bound your searches, lean on the fetcher and the watermark, and do not re-research history every run.

## Reference files

- `references/sources.md`: source list (firehose vs editorial) and WebSearch query patterns.
- `references/file-templates.md`: exact structure for news.md, advancements.md, technology.md, terms.md, _state.md.
- `references/verify.md`: the adversarial self-verify rubric for step 6.

## Run logging (visibility)

When this run finishes (success, partial, nothing-to-do, or failure), call the **a_sag_routine_logger** sub-agent once (Agent tool, `subagent_type: a_sag_routine_logger`) with `routine=<this skill's name from the frontmatter above>`, a `status`, and a one-line `summary` of what the run did. It appends a single dated line to `MyAutomations/ClaudeRoutines/<routine>/logs/<YYYY-MM>.md`, so the last run and what it did are visible at a glance. Keep the summary to ONE line. Logging is best-effort: if the mdnest CLI is unavailable (e.g. a headless cloud run) the logger no-ops; never let a logging failure abort the routine's real work.

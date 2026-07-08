---
name: a_r_l_olx_hunter
description: Scan OLX (or any classifieds / marketplace site) for a wanted item under budget and save the matches. Local routine: it browses the site, searches for the item, filters by budget and constraints (model not too old, must-have features), captures new listings since last run, and writes findings to a results directory. Use when asked to hunt for a deal, watch OLX or a marketplace for an item, check OLX/used listings for X under a budget, or when a scheduled "OLX hunt" / "marketplace hunt" routine fires. Parameterized: pass site (defaults to OLX), query, max_budget, must_haves, and save_dir. Invoke as `run a_r_l_olx_hunter on query="<item>" max_budget=<n> save_dir=<path>` (add site=<url> for a non-OLX site). Triggers even without the exact name: "watch OLX for a used amplifier under 100k", "find me a deal on X", "check the marketplace for Y".
---

# a_r_l_olx_hunter

Browse a marketplace, find listings that match what I want under my budget, and save them. Built to run unattended on a schedule (e.g. daily): it reports only genuinely matching, fresh listings and no-ops quietly when nothing new fits.

## Inputs (fill in the blanks)

| Input | Meaning | Example |
|-------|---------|---------|
| `site` | Marketplace to search (defaults to OLX; pass another classifieds URL to override). | `https://www.olx.com.pk/` |
| `query` | The item I want. | "AV amplifier with streaming support" |
| `max_budget` | Upper price limit (in the site's currency). | `100000` |
| `must_haves` | Required features / qualities. | supports streaming; model not too old |
| `nice_to_haves` | Also surface useful or similar finds. | similar AVRs, soundbars worth a look |
| `save_dir` | Results directory (the "res dir"). | the path I give you |
| `freshness` | Only report listings newer than the last run. | since previous run's watermark |

## Procedure

1. **Search.** Open `site`, search for `query`. Use the site's own filters for price (`<= max_budget`) and category where available; do not rely on filters alone, also read the listings.
2. **Match.** Keep a listing only if it plausibly satisfies `query` + `must_haves` and is within `max_budget`. Reject items that are too old / outdated for the model if `must_haves` says "not too old". While searching, also note anything under `nice_to_haves` (useful or similar), clearly separated from exact matches.
3. **Dedupe / freshness.** Skip listings already saved on a previous run (track by listing URL or id in `save_dir`). Only surface new ones, so a daily run does not repeat yesterday's finds.
4. **Capture.** For each kept listing record: title, price, location, listing date/age, condition, the feature evidence (why it matches), a short note on value, and the direct URL. Save into `save_dir` (e.g. a dated markdown file), exact matches first, then nice-to-haves.

## Rules

- Run autonomously; never ask questions. Read-only browsing — never message a seller, place a bid, make a payment, or submit any form. If the site blocks automated access or requires a login you cannot complete unattended, stop and say so in the report.
- Be honest about fit: if a listing is borderline (price slightly over, age unclear, feature unconfirmed), mark it as a "maybe" rather than a confident match.
- If nothing new fits, say so briefly and write nothing noisy.

## Report

End with: how many listings scanned, exact matches found (with prices + URLs), nice-to-have/similar finds, anything held as a "maybe", and where in `save_dir` you wrote the results.

## Run logging (visibility)

When this run finishes (success, partial, nothing-to-do, or failure), call the **a_sag_routine_logger** sub-agent once (Agent tool, `subagent_type: a_sag_routine_logger`) with `routine=<this skill's name from the frontmatter above>`, a `status`, and a one-line `summary` of what the run did. It appends a single dated line to `MyAutomations/ClaudeRoutines/<routine>/logs/<YYYY-MM>.md`, so the last run and what it did are visible at a glance. Keep the summary to ONE line. Logging is best-effort: if the mdnest CLI is unavailable (e.g. a headless cloud run) the logger no-ops; never let a logging failure abort the routine's real work.

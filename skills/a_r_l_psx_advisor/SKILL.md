---
name: a_r_l_psx_advisor
description: Pull the LIVE state of the Pakistan Stock Exchange (PSX) and turn a free-cash amount into a concrete, ready-to-place buy plan with EXACT share units, then keep Ahsan's mdnest PSX tracker updated and print the summary in chat. Local routine (uses the mdnest CLI): each run fetches today's KSE-100 level + macro + global drivers + sector winds, gets current prices for a fundamentally strong, liquid, Shariah-leaning candidate universe, picks ~6-8 names fitting the current circumstances, sizes them to whole shares for the given cash (commission reserved, leftover minimized) via a deterministic script, writes a dated report plus latest.md to mdnest at StayUptoDate/PSX, and reports back. Built to run unattended on his 24/7 local machine or on demand. Use whenever he asks where to invest his PSX cash, what to buy on the PSX today, the current PSX / KSE-100 condition, to refresh his PSX tracker, or when a scheduled "PSX" routine fires. Parameterized: cash (PKR), mdnest_path, shariah lean, risk tilt, optional current holdings. Invoke as `run a_r_l_psx_advisor for cash=200000`. Triggers even without the exact name: "what should I buy on the PSX with 200k", "PSX update", "where do I put my Pakistan stock money today", "rebuild my PSX buy plan", "is the Karachi market a buy right now" all count.
---

# a_r_l_psx_advisor

Each run answers one question end to end: **"Given my free cash and today's market, exactly which PSX symbols and how many units of each should I buy, and why?"** It fetches live data, decides, sizes to whole shares, writes the report to mdnest, and prints a to-the-point summary here. It never asks the user what to do, fill the defaults and proceed.

This is research and decision support, **not licensed financial advice**. Every report says so. The job is to be honest, current, and concrete, not to guarantee returns.

Designed to run unattended (on demand or scheduled). So: be cheap, bounded, and never present stale prices as live. If you size a position on a symbol, you must have a same-day live quote for it (re-fetch if unsure).

## Inputs (fill in the blanks; all optional, sane defaults)

| Input | Meaning | Default |
|-------|---------|---------|
| `cash` | Free cash to deploy, in PKR. | `200000` |
| `mdnest_path` | Base folder for the tracker. | `@srv-ahsan-mini/mahsan_brain/StayUptoDate/PSX` |
| `shariah` | Lean Shariah-compliant (halal) names. | `yes` (lean halal; allow 1-2 strong conventional names only if clearly better and flag them) |
| `risk` | Tilt. `income` = dividends/defensives; `growth` = more cyclicals/IT; `balanced` = both. | `balanced`, auto-adjusted by where the index sits (see method) |
| `holdings` | Current holdings to factor in (rebalance vs fresh buy). | none (treat as a fresh deployment) |
| `names` | How many positions. | `6-8` |

## The run loop

### 0. Resolve the mdnest base path
The base is `mdnest_path` (default `@srv-ahsan-mini/mahsan_brain/StayUptoDate/PSX`). Confirm `@srv-ahsan-mini` is configured: `mdnest list @srv-ahsan-mini` should return the `mahsan_brain` namespace. If the alias is missing, run `mdnest servers -v` IN FULL (do not truncate) and find the alias whose URL is `personal-brain.example.com` with namespace `mahsan_brain`. This is his personal brain, do not confuse `mahsan_brain` with the work brain `@work/my_brain`.

### 1. Stamp the run and read prior state
Get the date now from the environment, not memory: `date -u +%Y-%m-%dT%H:%M:%SZ` (and a human date for the report heading). Try to read `mdnest read <base>/_state.md` and the previous `latest.md`. If present, note the last run's date and KSE-100 level so you can show the move since last run. If nothing exists yet, this is a first run, proceed and bootstrap the files.

### 2. Gather LIVE market data (dispatch the a_sag_crawler agent)
Make a fresh cache dir under the scratchpad (e.g. `<scratchpad>/psx_cache`). Dispatch the **`a_sag_crawler`** agent (the project's polite, cache-first web-research agent) for two parallel jobs, writing into that cache:

1. **Market + context:** today's KSE-100 level, points/% change, volume, breadth, sentiment; 1-week and 1-month trend and distance from the all-time high; macro (SBP policy rate, latest CPI, PKR/USD, IMF program status, FX reserves, current account); global drivers (crude oil level + direction, US Fed stance, regional geopolitics); and which sectors are in/out of favor per recent broker commentary. Every figure dated and sourced.
2. **Prices + fundamentals:** current price (dated), dividend yield, P/E, one-line outlook, and Shariah flag for the candidate universe in `references/universe.md`. Flag any symbol whose price could not be fetched live.

Seed sites and the candidate universe are in `references/universe.md`. Read it before dispatching.

### 3. Decide the picks
Read `references/method.md` and apply it: map the current circumstances (where the index sits vs its high, rate trajectory, oil direction, sector winds) to a sector tilt, honor the `shariah` lean and `risk` input, and choose `names` fundamentally strong, liquid symbols with a clear one-line reason each. Prefer a diversified mix across sectors; avoid loading two names that rise and fall together. If `holdings` were given, plan around them (top up, trim, or fill gaps) instead of duplicating.

### 4. Confirm live quotes for the chosen names
For every symbol you are about to size, you must have a **same-day** price. If any chosen name lacked a live quote in step 2, dispatch a small focused `a_sag_crawler` to fetch just those quotes (try `dps.psx.com.pk/company/<SYM>` and `sarmaaya.pk`). Do not size on a stale price, either get a live one or swap the name out.

### 5. Size to exact units (deterministic, not by hand)
Assign each pick a target weight (sums need not be exact, the script normalizes). Build the JSON and run the sizer, never compute units by hand:

```bash
echo '{"cash": <cash>, "commission_pct": 0.6, "picks": [
  {"symbol":"HUBC","price":234.49,"weight":0.18,"why":"..."}, ...
]}' | python3 <skill-dir>/scripts/size_portfolio.py
```

It returns a markdown table (Symbol, Price, **Units**, Cost, actual Weight), the total invested, and the leftover (a ~0.6% reserve for brokerage commission + fees + slippage, so the user never overdraws). Use its numbers verbatim.

### 6. Write the report to mdnest
Compose the report from `references/method.md` § Report format. Write TWO things under `<base>`:
- **`<YYYY-MM-DD>-buy-report.md`** — the dated snapshot for history. New file, so use `mdnest append <base>/<date>-buy-report.md -` reading the content on stdin (the `create`-from-stdin bug means new-file writes go through `append`).
- **`latest.md`** — the always-current view. It already exists after the first run, so overwrite with `mdnest write <base>/latest.md -` on stdin.
Then update `<base>/_state.md` (overwrite with `mdnest write`): a fenced JSON block with `last_run` (the stamped UTC time), `kse100_level`, and the list of `{symbol, units}` chosen, so the next run can show the delta.

Verify each write returned `{"status":"ok"}` and read back the first lines of `latest.md` to confirm it landed.

### 7. Report in chat
Print the to-the-point summary (see `references/method.md` § Report format): a one-line market read, the buy table with units, the total + leftover, 2-3 caveats, and the mdnest path you wrote. Keep it tight, this is the "I don't have to ask again" payload.

## Bootstrap (first run, no files yet)
Same loop, but in step 6 create `latest.md` with `mdnest append` (new file) too, and create `_state.md`. Mention in the chat report that the tracker was initialized.

## Rules
- **Autonomous. Never ask questions.** Defaults above cover everything; proceed and note the assumptions in the report.
- **Live prices only.** Date every price. If you size a position, you have a same-day quote for it. Flag anything you could not verify and exclude it from sizing.
- **Not financial advice.** Every report carries the disclaimer. State risks honestly (market near highs, single-stock risk, commodity exposure).
- **Read-only.** Research and report only. Never place a trade, log into a broker, or submit any form.
- **Cheap and bounded.** A handful of crawler calls; reuse the cache; no-op gracefully if the market is closed (still produce a plan off the latest close, and say it is the last close).
- **mdnest discipline:** new files via `append` on stdin; overwrite existing via `write` on stdin; confirm `status: ok`; never paste long content as a shell argument (use stdin).
- **No em dashes** anywhere in the output (Ahsan's global preference).

## Run logging (visibility)

When this run finishes (success, partial, nothing-to-do, or failure), call the **a_sag_routine_logger** sub-agent once (Agent tool, `subagent_type: a_sag_routine_logger`) with `routine=<this skill's name from the frontmatter above>`, a `status`, and a one-line `summary` of what the run did. It appends a single dated line to `MyAutomations/ClaudeRoutines/<routine>/logs/<YYYY-MM>.md`, so the last run and what it did are visible at a glance. Keep the summary to ONE line. Logging is best-effort: if the mdnest CLI is unavailable (e.g. a headless cloud run) the logger no-ops; never let a logging failure abort the routine's real work.

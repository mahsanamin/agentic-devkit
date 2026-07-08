# Slack Summarizer

Automated Slack briefing system. Polls your workspace, detects new messages, generates AI-powered summaries, and sends them to your DM.

## How It Works

```
Cron (every 10 min)
  └── summarizer sendSummary
        ├── slack_poll.py ── cheap HTTP calls to Slack proxy (no AI tokens)
        │     └── New messages? Writes filtered JSON
        └── summarize.sh
              ├── slim_json.py: 159KB raw → 72KB slim
              ├── claude -p --model haiku: generates briefing (~$0.01-0.03)
              ├── send_dm.py: sends to your Slack DM
              └── publish: writes slack/latest.md (local or mdnest)
```

Nothing new? `slack_poll.py` exits immediately — zero AI cost. 80-90% of polls are free.

## Why a Proxy Instead of MCP?

Data fetching is separated from AI by design:

- **Polling is free.** Simple HTTP calls — no LLM tokens burned.
- **LLM only sees what's new.** Pre-filtering shrinks payloads 10x before Claude touches them.
- **No MCP round-trip overhead.** One HTTP call vs. multi-turn tool-use conversations.
- **Separation of concerns.** Proxy handles auth/data. Claude handles intelligence. Either can be swapped.

See [docs/proxy-api-contract.md](docs/proxy-api-contract.md) for the full proxy API spec.

## Quick Start

```bash
cd tools/slack-summarizer

# 1. Create config
cp config.env.sample config.env

# 2. Edit config.env — you need:
#    SLACK_PROXY_URL        → your Slack proxy endpoint
#    SLACK_PROXY_API_KEY    → proxy API key (ask your team lead)
#    MY_SLACK_USER_ID       → Slack profile → ... → Copy member ID
#    MY_SLACK_USER_NAME     → your display name
#    SLACK_WORKSPACE_URL    → https://yourcompany.slack.com
#    SLACK_DM_CHANNEL       → open DM with yourself → click name → Channel ID

# 3. Validate proxy + auth
./summarizer check

# 4. Discover channels (auto-lists all with IDs)
./summarizer list-channels
# Copy channels you want into config.env CHANNELS=() array

# 5. Validate everything
./summarizer check

# 6. First run — briefing arrives in your Slack DM
./summarizer sendSummary
```

See [setup.md](setup.md) for detailed step-by-step instructions with screenshots.

**Using Claude Code?** Just run `claude` in this directory — the CLAUDE.md will guide it through interactive setup.

## Commands

| Command | Description |
|---------|-------------|
| `./summarizer check` | Validate config, proxy, channels, Claude auth |
| `./summarizer list-channels` | Fetch available channels from proxy |
| `./summarizer sendSummary` | Poll + filter + summarize + send DM |
| `./summarizer createReport` | Aggregate 24h data into daily report |
| `./summarizer createReport --no-send` | Generate report without sending |
| `./summarizer consolidate` | Nightly: refresh threads, generate living docs |
| `./summarizer consolidate --delete-old` | Also delete old DM messages |

## Architecture

Python handles data processing (HTTP, JSON, dedup). Bash only pipes data into `claude -p`.

| Python modules | What they do |
|---|---|
| `lib.py` | Shared: config, proxy HTTP, permalinks, user map, publishing |
| `slack_poll.py` | Poll proxy, filter new messages, update watermarks |
| `fetch_inbox.py` | Read-only "about me" fetcher: mentions + threads I'm in → one clean JSON doc (powers the `a_c_slack_inbox` script; feeds a reply-drafting routine) |
| `slim_json.py` | Pre-filter JSON for Claude (truncate, limit replies) |
| `send_dm.py` | Send summary to Slack DM |
| `convert_mrkdwn.py` | Slack mrkdwn → Markdown |
| `merge_briefing.py` | Dedup + merge briefings into living doc |
| `merge_report.py` | Merge 24h data for daily report |
| `enrich_threads.py` | Scan history, fetch fresh thread state |
| `check.py` | Validate config + connectivity |
| `list_channels.py` | Discover channels from proxy |

| Bash scripts | What they do |
|---|---|
| `summarizer` | CLI entry point, routes commands, sets up PATH/auth |
| `summarize.sh` | slim → claude -p → send DM → publish |
| `report.sh` | merge → slim → claude -p → optional send |
| `consolidate_run.sh` | enrich → claude links → claude summary → publish |
| `cron_runner.sh` | PATH wrapper for crontab |

## My Slack inbox (read-only, for a reply assistant)

Separate from the summarizer's briefing flow, `fetch_inbox.py` pulls just the
"about me" surface — every message where you're **@mentioned** plus every
**thread you're in** (started, tagged, or replied to) — and emits one clean JSON
doc. Unlike `slack_poll.py` it keeps no watermark: it returns the full current
view, sorted newest-first, with a `needs_reply` flag per thread (true when the
last message in the thread isn't yours). That's the input a reply-drafting
routine reads to decide what to answer.

It's exposed as a script on PATH, `a_c_slack_inbox` (in the repo's `scripts/`),
which just sources this tool's `config.env` and runs `fetch_inbox.py`:

```bash
a_c_slack_inbox                     # full "about me" view, pretty JSON
a_c_slack_inbox --needs-reply-only  # only threads awaiting my reply
a_c_slack_inbox --quiet --save      # write DATA_DIR/inbox/latest.json (for cron)
a_c_slack_inbox --help              # all flags
```

Read-only: it never posts. Tests: `python3 test_fetch_inbox.py`.

## Cost

- **Polling:** Free (HTTP, no AI)
- **Per summary:** ~$0.01-0.03 (Claude Haiku)
- **Daily reports:** ~$0.02-0.05
- **Nightly consolidation:** ~$0.05-0.10 (Haiku + Sonnet)
- **Typical monthly:** ~$5-15

## Publishing Modes

| Mode | Where docs go | Extra deps |
|------|--------------|------------|
| `local` (default) | `$DATA_DIR/published/slack/*.md` | None |
| `mdnest` | mdnest server/namespace | [mdnest](https://github.com/nichochar/mdnest) |
| `none` | Skip publishing | None |

## Dependencies

| Tool | Required? | Purpose |
|------|-----------|---------|
| Python 3 | Yes | Data processing (stdlib only, no pip) |
| Claude CLI | Yes | AI summarization |
| Slack proxy | Yes | Fetches messages via HTTP ([API contract](docs/proxy-api-contract.md)) |
| mdnest | No | Only if PUBLISH_MODE=mdnest |

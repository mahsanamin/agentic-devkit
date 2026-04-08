# Slack Summarizer

Automated Slack briefing system. Polls your workspace, detects new messages, generates AI-powered summaries, and sends them to your DM.

## How It Works

```
Cron (every 10 min)
  └── slack_poller.sh ── cheap HTTP calls to Slack proxy (no AI tokens)
        ├── Nothing new? Exit. (80-90% of polls — free)
        └── New messages? Filter → claude_summarizer.sh
              ├── Pre-filter: 365KB raw → 33KB slim (truncate, limit replies, add permalinks)
              ├── Claude Haiku: generates Slack mrkdwn briefing (~$0.01-0.03)
              ├── Send to your DM via proxy
              └── Publish living doc (local file or mdnest)
```

## Why a Proxy Instead of MCP?

Data fetching is separated from AI by design:

- **Polling is free.** The cron job hits the proxy via simple HTTP — no LLM tokens burned. Most polls find nothing new and exit immediately.
- **LLM only sees what's new.** Pre-filtering shrinks payloads 10x before Claude touches them. The AI focuses on summarizing content, not data wrangling.
- **No MCP round-trip overhead.** One HTTP call gets the data vs. multi-turn tool-use conversations that burn tokens on each step.
- **Separation of concerns.** Proxy handles auth, rate limits, data format. Summarizer handles intelligence. Either can be swapped independently.

See [docs/proxy-api-contract.md](docs/proxy-api-contract.md) for the full proxy API specification.

## Quick Start

```bash
cp config.env.sample config.env     # 1. Create config
# Edit config.env with your values  # 2. Fill in proxy, user ID, channels
./summarizer check                  # 3. Validate everything
./summarizer list-channels          # 4. Discover channel IDs
./summarizer sendSummary            # 5. First run
```

See [setup.md](setup.md) for detailed step-by-step instructions.

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

## Cost

- **Polling:** Free (HTTP calls, no AI)
- **Per summary:** ~$0.01-0.03 (Claude Haiku, budget capped at $1.00/run)
- **Daily reports:** ~$0.02-0.05 (larger input)
- **Nightly consolidation:** ~$0.05-0.10 (Haiku for links + Sonnet for summary)
- **Typical monthly:** ~$5-15 for a full workweek of 10-min polling

## Publishing Modes

Summaries are published as living docs that update with each poll:

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
| curl | Yes | HTTP calls (pre-installed on macOS) |
| mdnest | No | Only if PUBLISH_MODE=mdnest |

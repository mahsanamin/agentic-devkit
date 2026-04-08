# Slack Summarizer

Automated Slack briefing system. Polls Slack via a local proxy, detects new messages using timestamp watermarks, generates AI-powered summaries with Claude, and sends them to your DM.

## Setup Guide (for Claude)

When a user asks to set up the slack-summarizer, walk them through:

### 1. Create config

```bash
cd tools/slack-summarizer
cp config.env.sample config.env
```

Ask them for these values and update config.env:
- **SLACK_PROXY_URL** — Their local Slack proxy endpoint (e.g., `https://localhost:8282`)
- **SLACK_PROXY_API_KEY** — API key for the proxy
- **MY_SLACK_USER_ID** — Their Slack member ID (Profile -> ... -> Copy member ID)
- **MY_SLACK_USER_NAME** — Their display name
- **SLACK_WORKSPACE_URL** — e.g., `https://mycompany.slack.com`
- **SLACK_DM_CHANNEL** — DM channel ID where summaries go
- **CHANNELS** — Array of channels to monitor (ID:name:tier format)
- **DATA_DIR** — Where to store runtime data (default: `~/.slack_summaries_data`)
- **MDNEST_SERVER** / **MDNEST_NS** — Optional, for mdnest publishing

### 2. Verify it works

```bash
./summarizer sendSummary
```

### 3. Set up cron (optional)

```cron
# Poll every 10 min, 8am-8pm (Mon-Fri)
*/10 8-20 * * 1-5 /path/to/slack-summarizer/cron_runner.sh >> ~/.slack_summaries_data/cron.log 2>&1

# Daily reports: 9am, 1pm, 6pm
0 9,13,18 * * 1-5 /path/to/slack-summarizer/summarizer createReport --no-send >> ~/.slack_summaries_data/cron.log 2>&1

# Nightly consolidation at 11pm
0 23 * * * /path/to/slack-summarizer/summarizer consolidate --delete-old >> ~/.slack_summaries_data/cron.log 2>&1
```

## Architecture

```
config.env        → All user-specific values (proxy URL, API key, channels, user ID)
summarizer        → CLI entry point, routes subcommands, handles PATH/auth for cron
slack_poller.sh   → Polls Slack proxy, compares watermarks, triggers summarizer if new data
claude_summarizer.sh → Pre-filters JSON, calls Claude Haiku, sends to DM, publishes to mdnest
create_report.sh  → Merges 24h of filtered data into a daily report
consolidate.sh    → Nightly: fetches fresh threads, prunes stale, generates living docs
```

## Key Files

| File | Purpose |
|------|---------|
| `config.env` | All configuration (never committed) |
| `summarizer` | CLI entry point |
| `slack_poller.sh` | Polls Slack, filters new messages |
| `claude_summarizer.sh` | Generates summaries via Claude Haiku |
| `create_report.sh` | Aggregates 24h data into daily report |
| `consolidate.sh` | Nightly thread consolidation + living docs |
| `system_prompt.txt` | Claude prompt for 10-min briefings (Slack mrkdwn output) |
| `report_prompt.txt` | Claude prompt for daily reports (Markdown output) |
| `clean_slack_mrkdwn.py` | Converts Slack mrkdwn to Markdown |
| `publish.sh` | Pluggable publish layer (local/mdnest/none) |
| `check.sh` | Config + connectivity validator |
| `list_channels.sh` | Fetches channels from proxy in config-ready format |
| `cron_runner.sh` | PATH wrapper for crontab |
| `docs/proxy-api-contract.md` | Full API spec for the Slack proxy |

## Data Directory

```
$DATA_DIR/
├── raw/YYYY-MM-DD/          # poll_*.json (full) + filtered_*.json (new only)
├── summaries/YYYY-MM-DD/    # summary_*.md + daily_report.md
├── state/
│   ├── last_poll.json       # Watermarks (last_mention_ts, last_thread_ts, channels{})
│   └── user_map.json        # user_id -> user_name cache
├── consolidated/
│   ├── enriched.json        # All threads + user map
│   ├── links.md             # Thread tracker
│   └── latest_summary.md    # Consolidated status
└── cron.log
```

## Key Conventions (for modifying code)

- **Config-driven** — All org-specific values live in config.env. Never hardcode workspace names, channel IDs, or API keys.
- **User identity injected at runtime** — `system_prompt.txt` is generic; `claude_summarizer.sh` prepends the manager's user_id and name from config (skipping first 2 lines of the prompt file).
- **No pip dependencies** — All Python uses stdlib only. Do not add pip requirements.
- **Pluggable publishing** — `publish.sh` abstracts storage via `publish_read`/`publish_write`/`publish_enabled`. Add new backends there.
- **Watermark state** — `state/last_poll.json` tracks what's been seen. Watermarks advance only from filtered (new) data, never from full API responses.

## CLI Commands

```bash
./summarizer check                          # Validate config + connectivity
./summarizer list-channels                  # Discover channel IDs from proxy
./summarizer sendSummary                    # Poll + filter + summarize + send DM
./summarizer createReport                   # Aggregate 24h data, send report
./summarizer createReport --no-send         # Generate report, don't send
./summarizer createReport --output ~/r.md   # Save to custom path
./summarizer consolidate                    # Nightly: refresh threads, generate docs
./summarizer consolidate --dry-run          # Preview without writing
./summarizer consolidate --delete-old       # Also delete old DM messages
```

## Prerequisites

- **Python 3** (stdlib only, no pip)
- **Claude CLI** (`claude`) authenticated via Keychain or ANTHROPIC_API_KEY
- **curl** (pre-installed on macOS)
- **Local Slack proxy** running (not included — set up separately)
- **mdnest** (optional, only if PUBLISH_MODE=mdnest)

# Setup Guide — Slack Summarizer

Complete setup instructions for a fresh machine.

## Prerequisites

| Tool | Install | Verify |
|------|---------|--------|
| Python 3 | `brew install python3` or via asdf | `python3 --version` |
| Claude CLI | `npm install -g @anthropic-ai/claude-code` | `claude --version` |
| curl | Pre-installed on macOS | `curl --version` |
| mdnest (optional) | `npm install -g mdnest` | `mdnest --version` |

## 1. Set up the Slack Proxy

This tool requires a **local Slack proxy** that wraps the Slack API into a compact JSON format. The proxy runs on your machine and handles authentication with Slack.

The proxy needs:
- A valid Slack OAuth token with scopes: `channels:history`, `channels:read`, `groups:history`, `groups:read`, `im:history`, `im:read`, `mpim:history`, `mpim:read`, `users:read`, `chat:write`
- To expose an HTTP API (default: `https://localhost:8282`)
- An API key for securing the endpoint

> The proxy itself is **not included** in this repo. You need to set one up separately or use an existing one your team provides. See [docs/proxy-api-contract.md](docs/proxy-api-contract.md) for the full API specification.

## 2. Create your config

```bash
cp config.env.sample config.env
```

Edit `config.env` and fill in each section:

### Slack Proxy

```bash
SLACK_PROXY_URL="https://localhost:8282"
SLACK_PROXY_API_KEY="your-proxy-api-key"
```

### Your Slack Identity

**Find your Slack User ID:**
1. Open Slack
2. Click your profile picture (bottom-left or top-right)
3. Click "Profile"
4. Click the `...` (more) button
5. Click "Copy member ID"

```bash
MY_SLACK_USER_ID="U0ABC123DEF"
MY_SLACK_USER_NAME="Jane Smith"
```

### Your Workspace URL

```bash
SLACK_WORKSPACE_URL="https://mycompany.slack.com"
```

### DM Channel (where summaries are sent)

**Find your DM channel ID:**
1. Open Slack
2. Go to your DM with yourself (or Slackbot)
3. Click the channel/conversation name at the top
4. Scroll down — you'll see "Channel ID: D0XXXXXXXX"
5. Copy that ID

```bash
SLACK_DM_CHANNEL="D0ABC123DEF"
```

### Channels to Monitor

**Option A: Auto-discover channels** (recommended — requires proxy to be running):

```bash
# List all available channels with IDs in config-ready format
./summarizer list-channels
```

Copy the channels you want into your `config.env` CHANNELS array and set the tier.

**Option B: Find channel IDs manually:**
1. Open the channel in Slack
2. Click the channel name at the top
3. Scroll to the bottom of the popup — "Channel ID: C0XXXXXXXX"

```bash
CHANNELS=(
    # Team channels (full detail, 8 messages per poll)
    "C0XXXXXXX1:my-team-core:team"
    "C0XXXXXXX2:my-team-product:team"

    # Org-wide channels (highlights only, 5 messages per poll)
    "C0XXXXXXX3:general:org"
    "C0XXXXXXX4:engineering:org"

    # Leadership channels (key decisions, 5 messages per poll)
    "C0XXXXXXX5:eng-leads:leads"
)
```

**Tiers explained:**
- `team` — Your team's channels. Every meaningful message is included in summaries.
- `org` — Company-wide. Only outages, announcements, process changes are included.
- `leads` — Leadership channels. Only decisions, escalations, action items.

### Publishing (Living Docs)

Summaries are published as living docs that update with each poll. Three modes:

**Local (default)** — writes to a local directory, no extra dependencies:

```bash
PUBLISH_MODE="local"
PUBLISH_DIR="$DATA_DIR/published"
```

Files end up at:
- `$DATA_DIR/published/slack/latest.md` — Rolling briefing feed
- `$DATA_DIR/published/slack/links-to-track.md` — Thread tracker
- `$DATA_DIR/published/slack/summaries.md` — Consolidated status

**mdnest** — publishes via [mdnest](https://github.com/nichochar/mdnest) CLI:

```bash
PUBLISH_MODE="mdnest"
MDNEST_SERVER="@my-brain"
MDNEST_NS="my_namespace"
```

Publishes to `@my-brain/my_namespace/slack/latest.md` etc.

**None** — skip publishing entirely:

```bash
PUBLISH_MODE="none"
```

## 3. Authenticate Claude CLI

```bash
# Login (stores token in macOS Keychain)
claude /login

# Verify
echo "Hello" | claude -p --model haiku
```

The `summarizer` script auto-extracts the Claude OAuth token from macOS Keychain so it works in cron (non-interactive).

Alternatively, set `ANTHROPIC_API_KEY` in your environment if you prefer API key auth.

## 4. Validate your setup

```bash
./summarizer check
```

This verifies: config.env exists, required values are set, proxy is reachable, API key works, channels are accessible, Claude is authenticated, and publishing is configured.

Fix any failures before continuing.

## 5. Test manually

```bash
./summarizer sendSummary
```

Expected output:
```
[timestamp] Polling Slack...
Filtered: N new items (mentions=X, threads=Y, channels=Z)
[timestamp] Found N new message(s) since last poll
[timestamp] Triggering Claude summarizer...
```

If `Found 0 new messages` — the proxy works but there's nothing new since the last watermark. Reset state to force a re-poll:

```bash
echo '{"last_mention_ts":"0","last_thread_ts":"0","channels":{}}' > ~/.slack_summaries_data/state/last_poll.json
./summarizer sendSummary
```

## 6. Set up cron

Open your crontab for editing:

```bash
crontab -e
```

Paste these 5 lines (replace `/path/to/slack-summarizer` with your actual path, e.g. `/Users/jane/repos/my_setup/tools/slack-summarizer`):

```
*/10 8-20 * * * /path/to/slack-summarizer/cron_runner.sh >> ~/.slack_summaries_data/cron.log 2>&1
0 9 * * * /path/to/slack-summarizer/summarizer createReport >> ~/.slack_summaries_data/cron.log 2>&1
0 13 * * * /path/to/slack-summarizer/summarizer createReport >> ~/.slack_summaries_data/cron.log 2>&1
0 18 * * * /path/to/slack-summarizer/summarizer createReport >> ~/.slack_summaries_data/cron.log 2>&1
0 23 * * * /path/to/slack-summarizer/summarizer consolidate --delete-old >> ~/.slack_summaries_data/cron.log 2>&1
```

Save and exit the editor. What each line does:
- **Line 1:** Poll Slack every 10 min between 8am-8pm (every day including weekends)
- **Lines 2-4:** Generate the daily report and post it as a fresh briefing DM at 9am, 1pm, 6pm (add `--no-send` to write the file without DMing). The poller (line 1) keeps one rolling DM updated in place between these.
- **Line 5:** Nightly consolidation + cleanup at 11pm

Verify it's installed:
```bash
crontab -l
```

## 7. Verify everything

After setup, wait for the next cron cycle (10 min) or run manually:

```bash
./summarizer sendSummary
```

Check:
1. **Slack DM** — you should see a briefing message
2. **Cron log** — `tail -20 ~/.slack_summaries_data/cron.log`
3. **Published docs** — depends on your PUBLISH_MODE:
   - local: `cat ~/.slack_summaries_data/published/slack/latest.md`
   - mdnest: `mdnest read @my-brain/my_namespace/slack/latest.md`

## Troubleshooting

| Symptom | Check | Fix |
|---------|-------|-----|
| No cron output | `crontab -l` | Re-install crontab |
| `command not found` in cron | PATH in `cron_runner.sh` | Edit cron_runner.sh PATH |
| SSL errors | Proxy cert | Scripts use `-k`/`CERT_NONE`; works with self-signed |
| "Not logged in" | Claude auth | Run `claude /login` |
| Empty summaries | Error logs | Check `summaries/YYYY-MM-DD/claude_err_*.log` |
| 0 new messages | Watermarks | `cat state/last_poll.json` — reset timestamps to "0" |
| 429 rate limits | Slack API | Built-in retry with backoff |
| Docs not publishing | Config | Check `PUBLISH_MODE` in config.env (default: `local`) |

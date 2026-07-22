# Slack Summarizer

Automated Slack briefing system. Polls Slack via a local proxy, detects new messages, generates AI summaries with Claude, sends to DM.

## Setup Guide (for Claude)

When a user asks to set up the slack-summarizer, follow these steps interactively. Read `setup.md` for full details on any step.

### Step 1: Prerequisites check

Verify these are installed:
```bash
python3 --version    # Python 3 (stdlib only, no pip needed)
claude --version     # Claude CLI
```

If Claude CLI is missing: `npm install -g @anthropic-ai/claude-code && claude /login`

### Step 2: Create config.env

```bash
cd tools/slack-summarizer
cp config.env.sample config.env
```

Then ask the user for each value and write it into config.env:

**Slack Proxy** — ask: "What's your Slack proxy URL and API key?"
```
SLACK_PROXY_URL="https://..."
SLACK_PROXY_API_KEY="..."
```

**Slack Identity** — ask: "What's your Slack member ID?"
Help them find it: Slack profile -> click `...` -> Copy member ID
```
MY_SLACK_USER_ID="U0ABC..."
MY_SLACK_USER_NAME="Their Name"
```

**Workspace URL** — ask or infer from proxy URL:
```
SLACK_WORKSPACE_URL="https://company.slack.com"
```

**DM Channel** — ask: "What's your DM channel ID?"
Help them find it: Open DM with yourself or Slackbot -> click name at top -> scroll down -> "Channel ID: D0..."
```
SLACK_DM_CHANNEL="D0ABC..."
```

**Channels** — don't ask yet, we'll auto-discover in step 4.

### Step 3: First validation

```bash
./summarizer check
```

This validates proxy connectivity and auth. If proxy/key checks pass, continue. Fix any failures first.

### Step 4: Discover and select channels

```bash
./summarizer list-channels
```

Show the output to the user. Ask them to pick which channels to monitor and what tier (team/org/leads):
- `team` = their direct team channels (full detail)
- `org` = company-wide (highlights only)
- `leads` = leadership (decisions only)

Write the CHANNELS array into config.env:
```
CHANNELS=(
    "C0XXX:channel-name:team"
    "C0YYY:general:org"
)
```

### Step 5: Full validation

```bash
./summarizer check
```

All 26+ checks should pass. If any channel fails, fix the ID.

### Step 6: Test run

```bash
./summarizer sendSummary
```

Wait ~60 seconds, then check:
- Slack DM should have a briefing
- `ls ~/.slack_summaries_data/summaries/$(date +%Y-%m-%d)/` should show summary_*.md

### Step 7: Set up cron (optional)

Tell the user to run `crontab -e` and paste these 5 lines. Replace the path with the actual absolute path to their slack-summarizer directory:

```
*/10 8-20 * * * /absolute/path/to/slack-summarizer/cron_runner.sh >> ~/.slack_summaries_data/cron.log 2>&1
0 9 * * * /absolute/path/to/slack-summarizer/summarizer createReport >> ~/.slack_summaries_data/cron.log 2>&1
0 13 * * * /absolute/path/to/slack-summarizer/summarizer createReport >> ~/.slack_summaries_data/cron.log 2>&1
0 18 * * * /absolute/path/to/slack-summarizer/summarizer createReport >> ~/.slack_summaries_data/cron.log 2>&1
0 23 * * * /absolute/path/to/slack-summarizer/summarizer consolidate --delete-old >> ~/.slack_summaries_data/cron.log 2>&1
```

The three `createReport` lines post a fresh briefing DM at 9am, 1pm, and 6pm (three real pings a day at natural checkpoints). The every-10-min poller keeps a single rolling DM updated in place between those. Add `--no-send` to a report line if you want it to write the report file without DMing.

After they save, verify with `crontab -l`.

## Key Conventions (for modifying code)

- **Config-driven** — All values in config.env. `summarizer` exports them as env vars. Python reads via `lib.load_config()`.
- **User identity injected at runtime** — `summarize.sh` prepends user ID/name from config before the system prompt.
- **No pip dependencies** — All Python uses stdlib only.
- **Publishing** — `lib.py` provides `publish_read`/`publish_write`/`publish_enabled`. Supports local, mdnest, or none.
- **Watermark state** — `state/last_poll.json` tracks what's been seen. Watermarks advance only from filtered data.

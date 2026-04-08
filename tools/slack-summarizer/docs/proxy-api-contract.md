# Slack Proxy API Contract

## Why a Proxy?

This tool separates **data fetching** from **AI summarization** by design.

A Slack proxy is a lightweight open-source tool that exposes your Slack workspace via simple REST APIs. The poller job fetches messages directly through cheap HTTP calls — no LLM tokens burned. Only when new messages are detected does the system invoke Claude, and only on the filtered delta (new messages since last poll).

This matters because:
- **Polling is free.** The cron job runs every 10 minutes. 80-90% of polls find nothing new and exit immediately — zero Claude cost.
- **LLM only sees what's new.** Pre-filtering (truncation, reply limiting, dedup) shrinks payloads from ~365KB to ~33KB before Claude touches them. The AI focuses on content, not data wrangling.
- **No MCP overhead.** Instead of routing every Slack read through an MCP server (which would burn tokens on tool-use round-trips), the proxy gives you raw data in one fast HTTP call.
- **Separation of concerns.** The proxy handles auth, rate limits, and data format. The summarizer handles intelligence. Either can be swapped independently.

Any open-source Slack proxy that exposes channel history and messaging via HTTP will work. The API contract below specifies exactly what endpoints and response formats this tool expects.

## Overview

- **Protocol:** HTTPS (self-signed cert OK — scripts use `-k` / `CERT_NONE`)
- **Auth:** `X-API-Key` header on every request
- **Response format:** JSON with `{ "success": true/false, "data": {...} }` wrapper
- **Default URL:** `https://localhost:8282`

## Endpoints Used

### 1. Get Mentions

```
GET /api/mentions/all?count=30&includeThreads=true
```

Returns messages where the authenticated user is @mentioned.

**Response:**
```json
{
  "success": true,
  "data": {
    "mentions": [
      {
        "ts": "1712345678.123456",
        "user_id": "U0ABC123",
        "user_name": "alice",
        "text": "Hey @you, can you review this PR?",
        "channel_id": "C0ABC123",
        "channel_name": "engineering",
        "permalink": "https://workspace.slack.com/archives/C0ABC123/p1712345678123456",
        "is_thread_reply": false,
        "thread_ts": ""
      }
    ]
  }
}
```

### 2. Get Threads You're In

```
GET /api/activity/threads-im-in?count=20
```

Returns threads where the user is participating (tagged or replied).

**Response:**
```json
{
  "success": true,
  "data": {
    "threads": [
      {
        "thread_ts": "1712345000.000000",
        "channel_id": "C0ABC123",
        "channel_name": "engineering",
        "parent_message": {
          "ts": "1712345000.000000",
          "user_id": "U0DEF456",
          "user_name": "bob",
          "text": "Should we migrate to PostgreSQL 16?"
        },
        "replies": [
          {
            "ts": "1712345100.000000",
            "user_id": "U0ABC123",
            "user_name": "alice",
            "text": "Yes, I'll handle the migration."
          }
        ],
        "thread_stats": {
          "reply_count": 5
        }
      }
    ]
  }
}
```

### 3. Get Your Own Threads

```
GET /api/activity/my-threads?count=20&includeReplies=true
```

Returns threads the user started or replied to. Same response format as threads-im-in.

### 4. Get Channel Messages

```
GET /api/channels/{channel_id}/recent-messages?count={N}&includeThreads=true
```

Returns recent messages from a specific channel.

**Parameters:**
- `channel_id` — Slack channel ID (e.g., `C0ABC123`)
- `count` — Number of messages to return (8 for team channels, 5 for org/leads)

**Response:**
```json
{
  "success": true,
  "data": {
    "messages": [
      {
        "ts": "1712345678.123456",
        "user_id": "U0ABC123",
        "user_name": "alice",
        "text": "Deployed v2.3.1 to production.",
        "permalink": "https://workspace.slack.com/archives/C0ABC123/p1712345678123456"
      }
    ]
  }
}
```

### 5. Get Thread Detail (used by consolidation)

```
GET /api/channels/{channel_id}/thread/{thread_ts}
```

Returns full thread state with parent message and all replies.

**Response:**
```json
{
  "success": true,
  "data": {
    "parent_message": {
      "ts": "1712345000.000000",
      "user_id": "U0DEF456",
      "user_name": "bob",
      "text": "Thread topic..."
    },
    "replies": [ ... ],
    "reply_count": 12
  }
}
```

### 6. Send DM Message

```
POST /api/messages/{channel_id}/send
Content-Type: application/json

{
  "text": "Summary message content...",
  "unfurl_links": false,
  "unfurl_media": false
}
```

Sends a message to a DM channel (used to deliver summaries).

**Response:**
```json
{
  "success": true,
  "data": {
    "ts": "1712345999.000000"
  }
}
```

### 7. Get DM History (used by --delete-old)

```
GET /api/messages/{channel_id}/history?latest={unix_timestamp}&count=200
```

Returns messages from a DM channel older than the given timestamp.

### 8. Delete DM Message (used by --delete-old)

```
DELETE /api/messages/{channel_id}/{message_ts}
```

Deletes a specific message by timestamp.

### 9. List Channels (used by list-channels command)

```
GET /api/channels?count=200
```

Returns available channels with metadata.

**Response:**
```json
{
  "success": true,
  "data": {
    "channels": [
      {
        "id": "C0ABC123",
        "name": "engineering",
        "is_private": false,
        "num_members": 42,
        "purpose": {
          "value": "Engineering discussion"
        }
      }
    ]
  }
}
```

## Message Object (Compact Format)

All messages follow this compact structure:

```json
{
  "ts": "1712345678.123456",
  "user_id": "U0ABC123",
  "user_name": "alice",
  "text": "Message content with <@U0DEF456> mentions and <#C0ABC123|channel-name> refs",
  "permalink": "https://workspace.slack.com/archives/C0ABC123/p1712345678123456"
}
```

**Key points:**
- `ts` is the Slack timestamp (unique message ID, also used as a Unix timestamp)
- `user_id` is the Slack member ID
- `user_name` is the display name (not the @handle)
- `text` is pre-cleaned (no blocks, no attachments, just text with Slack mrkdwn)
- `permalink` is optional — the scripts will construct one from channel_id + ts if missing

## Building Your Own Proxy

If you need to build a proxy that implements this contract:

1. Authenticate with Slack via OAuth (bot token or user token)
2. Map the endpoints above to the corresponding Slack Web API methods:
   - Mentions → `search.messages` or `conversations.history` with filtering
   - Threads → `conversations.replies`
   - Channel messages → `conversations.history`
   - Send → `chat.postMessage`
   - Delete → `chat.delete`
   - List channels → `conversations.list`
3. Transform responses into the compact format above
4. Serve over HTTPS (self-signed is fine)
5. Use `X-API-Key` header for auth

**Required Slack OAuth scopes:**
`channels:history`, `channels:read`, `groups:history`, `groups:read`, `im:history`, `im:read`, `mpim:history`, `mpim:read`, `users:read`, `chat:write`

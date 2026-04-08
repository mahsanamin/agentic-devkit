#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# list_channels.sh — Fetch available channels from Slack proxy
#
# Outputs channels in ready-to-paste config.env format.
# Usage: ./list_channels.sh [--raw]
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$SCRIPT_DIR/config.env" ]] && source "$SCRIPT_DIR/config.env"

API_BASE="${SLACK_PROXY_URL:?Error: SLACK_PROXY_URL not set in config.env}"
API_KEY="${SLACK_PROXY_API_KEY:?Error: SLACK_PROXY_API_KEY not set in config.env}"
RAW_MODE=false

[[ "${1:-}" == "--raw" ]] && RAW_MODE=true

python3 - "$API_BASE" "$API_KEY" "$RAW_MODE" << 'PYEOF'
import json, ssl, urllib.request, sys

api_base, api_key, raw_mode = sys.argv[1], sys.argv[2], sys.argv[3] == "True"

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

def api_get(endpoint):
    req = urllib.request.Request(
        f"{api_base}{endpoint}",
        headers={"X-API-Key": api_key}
    )
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=15) as resp:
            return json.loads(resp.read())
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return {"success": False, "error": str(e)}

# Try the channels list endpoint
resp = api_get("/api/channels?count=200")

if not resp.get("success"):
    # Fallback: try conversations list
    resp = api_get("/api/conversations?count=200")

if not resp.get("success"):
    print(f"Error: Could not fetch channels from proxy", file=sys.stderr)
    print(f"Response: {json.dumps(resp, indent=2)}", file=sys.stderr)
    sys.exit(1)

channels = resp.get("data", {}).get("channels", [])

if not channels:
    print("No channels found.", file=sys.stderr)
    sys.exit(0)

# Sort by name
channels.sort(key=lambda c: c.get("name", ""))

if raw_mode:
    print(json.dumps(channels, indent=2))
    sys.exit(0)

# Output as config-ready format
print(f"# Found {len(channels)} channels")
print(f"# Copy the ones you want into config.env CHANNELS=()")
print(f"#")
print(f"# Format: \"CHANNEL_ID:name:TIER\"")
print(f"#   team  = Your team channels (full detail)")
print(f"#   org   = Company-wide (highlights only)")
print(f"#   leads = Leadership (decisions only)")
print()

for ch in channels:
    ch_id = ch.get("id", "")
    name = ch.get("name", "unknown")
    is_private = ch.get("is_private", False)
    member_count = ch.get("num_members", "?")
    purpose = (ch.get("purpose", {}).get("value", "") or "")[:60]

    marker = "private" if is_private else "public"
    comment = f"  # {marker}, {member_count} members"
    if purpose:
        comment += f" — {purpose}"

    print(f'    # "{ch_id}:{name}:org"{comment}')
PYEOF

#!/usr/bin/env python3
"""Fetch available channels from Slack proxy in config-ready format.

Usage: python3 list_channels.py [--raw]
"""
import json, sys
from lib import load_config, proxy_get

def main():
    raw_mode = "--raw" in sys.argv
    cfg = load_config()

    resp = proxy_get("/api/channels?count=200", cfg)
    if not resp.get("success"):
        resp = proxy_get("/api/conversations?count=200", cfg)

    if not resp.get("success"):
        print(f"Error: Could not fetch channels: {resp.get('error', 'unknown')}", file=sys.stderr)
        sys.exit(1)

    channels = resp.get("data", {}).get("channels", [])
    if not channels:
        print("No channels found.", file=sys.stderr)
        sys.exit(0)

    channels.sort(key=lambda c: c.get("name", ""))

    if raw_mode:
        print(json.dumps(channels, indent=2))
        return

    print(f"# Found {len(channels)} channels")
    print(f"# Copy the ones you want into config.env CHANNELS=()")
    print(f"#")
    print(f'# Format: "CHANNEL_ID:name:TIER"')
    print(f"#   team  = Your team channels (full detail)")
    print(f"#   org   = Company-wide (highlights only)")
    print(f"#   leads = Leadership (decisions only)")
    print()

    for ch in channels:
        ch_id = ch.get("id", "")
        name = ch.get("name", "unknown")
        is_private = ch.get("is_private", False)
        members = ch.get("num_members", "?")
        purpose = (ch.get("purpose", {}).get("value", "") or "")[:60]

        marker = "private" if is_private else "public"
        comment = f"  # {marker}, {members} members"
        if purpose:
            comment += f" — {purpose}"

        print(f'    # "{ch_id}:{name}:org"{comment}')

if __name__ == "__main__":
    main()

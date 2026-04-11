#!/usr/bin/env python3
"""Send a summary file to Slack DM via proxy.

Usage: python3 send_dm.py <summary.md> [--no-send]
"""
import json, sys
from lib import load_config, proxy_post, log

def main():
    if "--no-send" in sys.argv:
        log("Skip-send mode", "dm")
        return

    if len(sys.argv) < 2 or sys.argv[1].startswith("-"):
        print("Usage: send_dm.py <summary.md> [--no-send]", file=sys.stderr)
        sys.exit(1)

    cfg = load_config()
    with open(sys.argv[1]) as f:
        text = f.read().strip()

    if not text:
        log("Empty summary, skipping send", "dm")
        return

    data = {"text": text, "unfurl_links": False, "unfurl_media": False}
    resp = proxy_post(f"/api/messages/{cfg['dm_channel']}/send", data, cfg)

    if resp.get("success"):
        log(f"Sent to DM {cfg['dm_channel']}", "dm")
    else:
        log(f"WARNING: Failed to send: {resp.get('error', 'unknown')}", "dm")

if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Validate configuration and connectivity."""
import os, sys, shutil, subprocess
from lib import load_config, proxy_get

G = "\033[0;32m"  # green
R = "\033[0;31m"  # red
Y = "\033[1;33m"  # yellow
N = "\033[0m"     # reset

PASS = FAIL = WARN = 0

def ok(msg):
    global PASS; PASS += 1; print(f"  {G}OK{N}  {msg}")
def fail(msg):
    global FAIL; FAIL += 1; print(f"  {R}FAIL{N}  {msg}")
def warn(msg):
    global WARN; WARN += 1; print(f"  {Y}WARN{N}  {msg}")
def section(name):
    print(f"\n── {name} ──")

def check_var(cfg, key, display, placeholder=""):
    val = cfg.get(key, "")
    if not val:
        fail(f"{display} is not set")
    elif placeholder and val == placeholder:
        fail(f"{display} is still placeholder")
    else:
        shown = val[:40] + ("..." if len(val) > 40 else "")
        ok(f"{display} = {shown}")

def main():
    cfg = load_config()

    # Config
    section("Config")
    config_path = os.path.join(os.path.dirname(__file__), "config.env")
    if os.path.exists(config_path):
        ok("config.env exists")
    else:
        fail("config.env not found — run: cp config.env.sample config.env")
        summary()
        return

    # Required settings
    section("Required Settings")
    check_var(cfg, "proxy_url", "SLACK_PROXY_URL")
    check_var(cfg, "proxy_key", "SLACK_PROXY_API_KEY", "your-proxy-api-key-here")
    check_var(cfg, "user_id", "MY_SLACK_USER_ID", "U0000000000")
    check_var(cfg, "user_name", "MY_SLACK_USER_NAME", "Your Name")
    check_var(cfg, "workspace_url", "SLACK_WORKSPACE_URL", "https://your-workspace.slack.com")
    check_var(cfg, "dm_channel", "SLACK_DM_CHANNEL", "D000000000")

    channels = cfg["channels"]
    ch_list = [c.strip() for c in channels.split(",") if c.strip()] if channels else []
    if not ch_list:
        fail("CHANNELS is empty — add at least one channel")
    else:
        ok(f"CHANNELS has {len(ch_list)} channel(s)")

    # Proxy
    section("Slack Proxy")
    proxy_ok = False
    if cfg["proxy_url"] and cfg["proxy_key"] != "your-proxy-api-key-here":
        resp = proxy_get("/api/mentions/all?count=1", cfg, timeout=10)
        if resp.get("success"):
            ok(f"Proxy reachable at {cfg['proxy_url']}")
            proxy_ok = True
        elif "HTTP 401" in resp.get("error", "") or "HTTP 403" in resp.get("error", ""):
            fail(f"Proxy returned {resp['error']} — check SLACK_PROXY_API_KEY")
        else:
            fail(f"Cannot connect to proxy: {resp.get('error', 'unknown')}")
    else:
        warn("Skipping proxy check (not configured)")

    # Channels
    if proxy_ok and ch_list:
        section("Channels")
        for ch_spec in ch_list:
            parts = ch_spec.split(":")
            ch_id = parts[0]
            ch_name = parts[1] if len(parts) > 1 else ch_id
            tier = parts[2] if len(parts) > 2 else "org"
            resp = proxy_get(f"/api/channels/{ch_id}/recent-messages?count=1", cfg, timeout=10)
            if resp.get("success"):
                ok(f"#{ch_name} ({ch_id}) — {tier}")
            else:
                fail(f"#{ch_name} ({ch_id}) — {resp.get('error', 'failed')}")

    # DM channel
    if proxy_ok and cfg["dm_channel"] != "D000000000":
        section("DM Channel")
        resp = proxy_get(f"/api/channels/{cfg['dm_channel']}/recent-messages?count=1", cfg, timeout=10)
        if resp.get("success"):
            ok(f"DM channel {cfg['dm_channel']} accessible")
        else:
            fail(f"DM channel {cfg['dm_channel']} — {resp.get('error', 'failed')}")

    # Claude
    section("Claude CLI")
    claude_path = shutil.which("claude")
    if claude_path:
        ok(f"claude found at {claude_path}")
        token = os.environ.get("CLAUDE_CODE_OAUTH_TOKEN", "") or os.environ.get("ANTHROPIC_API_KEY", "")
        if token:
            ok("Auth token available")
        else:
            try:
                result = subprocess.run(
                    ["security", "find-generic-password", "-s", "Claude Code-credentials", "-w"],
                    capture_output=True, text=True, timeout=5
                )
                if result.returncode == 0 and result.stdout.strip():
                    ok("Auth token extractable from Keychain")
                else:
                    fail("No auth token — run: claude /login")
            except Exception:
                fail("No auth token — run: claude /login")
    else:
        fail("claude not found — install: npm install -g @anthropic-ai/claude-code")

    # Python
    section("Python")
    ok(f"python3 {sys.version.split()[0]}")

    # Publishing
    section("Publishing")
    mode = cfg["publish_mode"]
    if mode == "none" or not mode:
        warn("PUBLISH_MODE=none — summaries won't be published as living docs")
    elif mode == "local":
        pub_dir = cfg["publish_dir"] or os.path.join(cfg["data_dir"], "published")
        ok(f"PUBLISH_MODE=local — docs go to {pub_dir}/")
    elif mode == "mdnest":
        if shutil.which("mdnest"):
            ok("PUBLISH_MODE=mdnest — mdnest found")
            if cfg["mdnest_server"] and cfg["mdnest_ns"]:
                ok(f"mdnest target: {cfg['mdnest_server']}/{cfg['mdnest_ns']}/")
            else:
                fail("MDNEST_SERVER or MDNEST_NS not set")
        else:
            fail("PUBLISH_MODE=mdnest but mdnest not installed")

    summary()

def summary():
    print(f"\n{'─' * 35}")
    print(f"  {G}{PASS} passed{N}  {R}{FAIL} failed{N}  {Y}{WARN} warnings{N}")
    print(f"{'─' * 35}")
    if FAIL > 0:
        print(f"\nFix failures before running ./summarizer sendSummary")
        sys.exit(1)
    else:
        print(f"\nReady to go. Try: ./summarizer sendSummary")

if __name__ == "__main__":
    main()

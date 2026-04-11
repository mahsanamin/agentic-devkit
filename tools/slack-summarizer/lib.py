"""Shared utilities for slack-summarizer. Stdlib only, no pip."""

import json, os, re, ssl, time, urllib.request, subprocess, sys, shutil
from datetime import datetime

# ── Config ───────────────────────────────────────────────────────────────────

def load_config():
    """Load config from environment variables (sourced from config.env by bash)."""
    return {
        "data_dir": os.environ.get("DATA_DIR", os.path.dirname(__file__)),
        "proxy_url": os.environ.get("SLACK_PROXY_URL", ""),
        "proxy_key": os.environ.get("SLACK_PROXY_API_KEY", ""),
        "user_id": os.environ.get("MY_SLACK_USER_ID", ""),
        "user_name": os.environ.get("MY_SLACK_USER_NAME", ""),
        "workspace_url": os.environ.get("SLACK_WORKSPACE_URL", ""),
        "dm_channel": os.environ.get("SLACK_DM_CHANNEL", ""),
        "channels": os.environ.get("CHANNELS_LIST", ""),  # comma-separated, set by bash
        "publish_mode": os.environ.get("PUBLISH_MODE", "local"),
        "publish_dir": os.environ.get("PUBLISH_DIR", ""),
        "mdnest_server": os.environ.get("MDNEST_SERVER", ""),
        "mdnest_ns": os.environ.get("MDNEST_NS", ""),
        "stale_days": int(os.environ.get("STALE_DAYS", "30")),
        "delete_older_than_days": int(os.environ.get("DELETE_OLDER_THAN_DAYS", "7")),
    }

def script_dir():
    """Return the directory containing the slack-summarizer scripts."""
    return os.path.dirname(os.path.abspath(__file__))

# ── Logging ──────────────────────────────────────────────────────────────────

def log(msg, tag=""):
    prefix = f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}]"
    if tag:
        prefix += f" [{tag}]"
    print(f"{prefix} {msg}", file=sys.stderr)

# ── Proxy HTTP Client ────────────────────────────────────────────────────────

_ssl_ctx = ssl.create_default_context()
_ssl_ctx.check_hostname = False
_ssl_ctx.verify_mode = ssl.CERT_NONE

def proxy_get(endpoint, cfg=None, timeout=15, retries=3):
    """GET from the Slack proxy. Returns parsed JSON dict."""
    if cfg is None:
        cfg = load_config()
    url = f"{cfg['proxy_url']}{endpoint}"
    for attempt in range(retries):
        req = urllib.request.Request(url, headers={"X-API-Key": cfg["proxy_key"]})
        try:
            with urllib.request.urlopen(req, context=_ssl_ctx, timeout=timeout) as resp:
                return json.loads(resp.read())
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < retries - 1:
                time.sleep((attempt + 1) * 3)
                continue
            return {"success": False, "error": f"HTTP {e.code}"}
        except Exception as e:
            return {"success": False, "error": str(e)}
    return {"success": False, "error": "max retries"}

def proxy_post(endpoint, data, cfg=None, timeout=15):
    """POST JSON to the Slack proxy. Returns parsed JSON dict."""
    if cfg is None:
        cfg = load_config()
    url = f"{cfg['proxy_url']}{endpoint}"
    body = json.dumps(data).encode()
    req = urllib.request.Request(url, data=body, headers={
        "X-API-Key": cfg["proxy_key"],
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req, context=_ssl_ctx, timeout=timeout) as resp:
            return json.loads(resp.read())
    except Exception as e:
        return {"success": False, "error": str(e)}

def proxy_delete(endpoint, cfg=None, timeout=15):
    """DELETE on the Slack proxy. Returns parsed JSON dict."""
    if cfg is None:
        cfg = load_config()
    url = f"{cfg['proxy_url']}{endpoint}"
    req = urllib.request.Request(url, headers={"X-API-Key": cfg["proxy_key"]}, method="DELETE")
    try:
        with urllib.request.urlopen(req, context=_ssl_ctx, timeout=timeout) as resp:
            return json.loads(resp.read())
    except Exception as e:
        return {"success": False, "error": str(e)}

# ── Permalinks ───────────────────────────────────────────────────────────────

def make_permalink(channel_id, ts, cfg=None):
    """Construct Slack permalink from channel ID and message timestamp."""
    if not channel_id or not ts:
        return ""
    if cfg is None:
        cfg = load_config()
    base = cfg["workspace_url"]
    if not base:
        return ""
    return f"{base}/archives/{channel_id}/p{ts.replace('.', '')}"

# ── User Map Cache ───────────────────────────────────────────────────────────

def load_user_map(cfg=None):
    """Load persistent user_id → user_name cache."""
    if cfg is None:
        cfg = load_config()
    cache = os.path.join(cfg["data_dir"], "state", "user_map.json")
    try:
        with open(cache) as f:
            return json.load(f)
    except Exception:
        return {}

def save_user_map(user_map, cfg=None):
    """Save user_id → user_name cache."""
    if cfg is None:
        cfg = load_config()
    cache = os.path.join(cfg["data_dir"], "state", "user_map.json")
    os.makedirs(os.path.dirname(cache), exist_ok=True)
    with open(cache, "w") as f:
        json.dump(user_map, f)

def extract_users(data):
    """Extract user_id→user_name pairs from poll/filtered JSON."""
    users = {}
    for m in data.get("mentions", []):
        uid = m.get("user_id", m.get("user", ""))
        name = m.get("user_name", "")
        if uid and name:
            users[uid] = name
    for t in data.get("threads", []):
        uid, name = t.get("parent_user_id", ""), t.get("parent_user_name", "")
        if uid and name:
            users[uid] = name
        for r in t.get("replies", t.get("_replies", [])):
            uid = r.get("user_id", r.get("user", ""))
            name = r.get("user_name", "")
            if uid and name:
                users[uid] = name
    for ch in data.get("channels", {}).values():
        for m in (ch.get("messages", []) if isinstance(ch, dict) else []):
            uid = m.get("user_id", m.get("user", ""))
            name = m.get("user_name", "")
            if uid and name:
                users[uid] = name
    return users

# ── Publishing ───────────────────────────────────────────────────────────────

def publish_enabled(cfg=None):
    """Check if publishing is configured."""
    if cfg is None:
        cfg = load_config()
    mode = cfg["publish_mode"]
    if mode == "none" or not mode:
        return False
    if mode == "local":
        return True
    if mode == "mdnest":
        if not shutil.which("mdnest"):
            log("WARNING: PUBLISH_MODE=mdnest but mdnest not on PATH")
            return False
        if not cfg["mdnest_server"] or not cfg["mdnest_ns"]:
            log("WARNING: PUBLISH_MODE=mdnest but MDNEST_SERVER/NS not set")
            return False
        return True
    return False

def publish_read(path, cfg=None):
    """Read a published file. Returns content string or empty string."""
    if cfg is None:
        cfg = load_config()
    mode = cfg["publish_mode"]
    if mode == "local":
        fpath = os.path.join(cfg["publish_dir"] or os.path.join(cfg["data_dir"], "published"), path)
        try:
            with open(fpath) as f:
                return f.read()
        except FileNotFoundError:
            return ""
    elif mode == "mdnest":
        try:
            result = subprocess.run(
                ["mdnest", "read", f"{cfg['mdnest_server']}/{cfg['mdnest_ns']}/{path}"],
                capture_output=True, text=True, timeout=15
            )
            return result.stdout if result.returncode == 0 else ""
        except Exception:
            return ""
    return ""

def publish_write(path, content, cfg=None):
    """Write content to a published path. Returns True on success."""
    if cfg is None:
        cfg = load_config()
    mode = cfg["publish_mode"]
    if mode == "local":
        fpath = os.path.join(cfg["publish_dir"] or os.path.join(cfg["data_dir"], "published"), path)
        os.makedirs(os.path.dirname(fpath), exist_ok=True)
        with open(fpath, "w") as f:
            f.write(content)
        return True
    elif mode == "mdnest":
        try:
            result = subprocess.run(
                ["mdnest", "write", f"{cfg['mdnest_server']}/{cfg['mdnest_ns']}/{path}", "-"],
                input=content, capture_output=True, text=True, timeout=15
            )
            return result.returncode == 0
        except Exception:
            return False
    return False

# ── Misc ─────────────────────────────────────────────────────────────────────

def today():
    return datetime.now().strftime("%Y-%m-%d")

def now_ts():
    return datetime.now().strftime("%H%M%S")

def ensure_dirs(cfg=None):
    """Create standard data directories."""
    if cfg is None:
        cfg = load_config()
    d = cfg["data_dir"]
    for sub in [f"raw/{today()}", f"summaries/{today()}", "state", "consolidated"]:
        os.makedirs(os.path.join(d, sub), exist_ok=True)

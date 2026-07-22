#!/usr/bin/env python3
"""Down-alert for the Slack proxy.

The whole summarizer depends on the proxy being reachable. When it goes down,
polls fail silently except for a line in cron.log, so an outage can go unnoticed
for hours (it has). This posts a SINGLE, self-refreshing DM alert so the outage
is visible without reading the log:

  - On the first failed poll it posts one DM: "proxy is DOWN".
  - While it stays down it refreshes that alert at most once per hour: it deletes
    the previous alert message and posts a fresh one, so the alert bumps to the
    bottom of the DM with an updated "down for ~Nh". You see the error is still
    coming instead of a new message piling up every 10 minutes.
  - When the proxy recovers, the standing alert is deleted and state is cleared.

If the proxy is fully down, the DM send goes through that same proxy and also
fails. In that case it falls back to a local macOS desktop notification so there
is still a signal on this (24/7 local) machine.

State: state/proxy_alert.json. It only ever deletes the alert ts it posted itself.
"""
import json, os, subprocess, time
from datetime import datetime

from lib import load_config, proxy_post, proxy_delete, log

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
STATE_FILE = os.path.join(SCRIPT_DIR, "state", "proxy_alert.json")
# Refresh cadence while the proxy stays down. Override for testing.
ALERT_INTERVAL = int(os.environ.get("PROXY_ALERT_INTERVAL_SEC", "3600"))  # once/hour


def _load():
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def _save(st):
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(st, f, indent=2)


def _fmt_duration(seconds):
    m = int(seconds // 60)
    if m < 60:
        return f"{m}m"
    h, m = divmod(m, 60)
    return f"{h}h{m:02d}m"


def _macos_notify(title, message):
    """Best-effort local desktop notification (macOS). No-op if unavailable."""
    try:
        subprocess.run(
            ["osascript", "-e",
             f"display notification {json.dumps(message)} with title {json.dumps(title)}"],
            capture_output=True, timeout=10,
        )
    except Exception:
        pass


def _post(cfg, text):
    resp = proxy_post(
        f"/api/messages/{cfg['dm_channel']}/send",
        {"text": text, "unfurl_links": False, "unfurl_media": False},
        cfg,
    )
    return resp.get("data", {}).get("ts") if resp.get("success") else None


def _delete(cfg, ts):
    if not ts:
        return
    proxy_delete(f"/api/messages/{cfg['dm_channel']}/{ts}", cfg)


def notify_down(err, cfg=None):
    """Record a failed poll and, at most once per hour, post/refresh the DM alert."""
    if cfg is None:
        cfg = load_config()
    now = time.time()
    st = _load()
    if not st.get("down_since"):
        st["down_since"] = now
    st["fail_count"] = st.get("fail_count", 0) + 1
    last = st.get("last_alert_at") or 0

    if now - last >= ALERT_INTERVAL:
        dur = _fmt_duration(now - st["down_since"])
        checked = datetime.now().strftime("%H:%M")
        text = (
            ":rotating_light: *Slack summarizer — proxy is DOWN*\n"
            f"`{cfg['proxy_url']}` unreachable ({err}).\n"
            f"Down for ~{dur} · {st['fail_count']} failed poll(s) · last checked {checked}.\n"
            "_Briefings are paused until it recovers. This alert refreshes hourly "
            "while it stays down._"
        )
        new_ts = _post(cfg, text)
        if new_ts:
            _delete(cfg, st.get("alert_ts"))  # remove the prior alert copy
            st["alert_ts"] = new_ts
            log(f"posted proxy-down alert -> {new_ts}", "alert")
        else:
            # Proxy (and thus the DM send) is down too — fall back to desktop.
            _macos_notify(
                "Slack summarizer: proxy DOWN",
                f"Down ~{dur}, {st['fail_count']} failed polls. Briefings paused.",
            )
            log("proxy-down alert: DM send failed, sent local notification", "alert")
        st["last_alert_at"] = now
    _save(st)


def notify_recovered(cfg=None):
    """Proxy is reachable again: delete the standing alert and clear state."""
    st = _load()
    if not st:
        return
    if cfg is None:
        cfg = load_config()
    _delete(cfg, st.get("alert_ts"))
    dur = _fmt_duration(time.time() - st["down_since"]) if st.get("down_since") else "?"
    log(f"proxy recovered after ~{dur}, cleared down-alert", "alert")
    _save({})

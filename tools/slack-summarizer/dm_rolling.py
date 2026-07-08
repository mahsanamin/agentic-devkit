#!/usr/bin/env python3
"""Maintain ONE rolling briefing message per day in the Slack DM.

Instead of posting a brand-new DM message on every run (which floods the DM),
this merges each new briefing into today's accumulated content (dedup via
merge_briefing), deletes the previous copy of today's message, and reposts the
merged result. Net effect: at most one DM message per day.

Days older than WEEKLY_AFTER_DAYS are merged into a single weekly-digest
message and their individual daily messages are deleted.

Safety: only ever deletes message timestamps this script itself posted and
recorded in state/dm_daily.json. It never bulk-deletes or searches for messages.

Usage: dm_rolling.py <new_summary.md> [--dry-run]
"""
import json, os, re, sys
from datetime import datetime, timedelta

from lib import load_config, proxy_post, proxy_delete, log
from merge_briefing import extract_link_keys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
STATE_FILE = os.path.join(SCRIPT_DIR, "state", "dm_daily.json")
WEEKLY_AFTER_DAYS = int(os.environ.get("WEEKLY_AFTER_DAYS", "7"))


def content_lines(text):
    """Meaningful content lines from a briefing: drop the Briefing header,
    'All quiet' pings, and sync/updated metadata lines."""
    out = []
    for line in text.splitlines():
        st = line.strip()
        if not st:
            continue
        if re.match(r"^:newspaper:.*Briefing", st):
            continue
        if re.search(r"all quiet", st, re.I):
            continue
        if re.match(r"^_(Last synced|updated)", st):
            continue
        out.append(line.rstrip())
    return out


def merge_daily(new_text, old_body):
    """Append new briefing content to today's body, deduped by thread-link
    (falling back to exact line text). Idempotent: re-merging identical input
    returns the same body unchanged."""
    old_lines = [l for l in (old_body or "").splitlines() if l.strip()]
    seen_links = extract_link_keys(old_body or "")
    seen_text = {l.strip() for l in old_lines}
    appended = []
    for line in content_lines(new_text):
        links = extract_link_keys(line)
        if links and (links & seen_links):
            continue
        if not links and line.strip() in seen_text:
            continue
        appended.append(line)
        seen_links |= links
        seen_text.add(line.strip())
    return "\n".join(old_lines + appended).strip()


def data_dir():
    return os.environ.get("DATA_DIR", os.path.expanduser("~/.slack_summaries_data"))


def daily_file(date_str):
    return os.path.join(data_dir(), "summaries", date_str, "daily_merged.md")


def load_state():
    try:
        with open(STATE_FILE) as f:
            st = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        st = {}
    st.setdefault("today", None)
    st.setdefault("today_ts", None)
    st.setdefault("days", {})  # {"YYYY-MM-DD": "<ts of that day's single message>"}
    return st


def save_state(st):
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(st, f, indent=2)


def parse_date(s):
    try:
        return datetime.strptime(s, "%Y-%m-%d").date()
    except (ValueError, TypeError):
        return None


def render_daily(date_str, body):
    now = datetime.now().strftime("%H:%M")
    return f":newspaper: *Daily Briefing* — {date_str}\n_updated {now}_\n\n{body}"


def post(cfg, text, dry):
    if dry:
        log("[dry-run] POST message (%d chars)" % len(text), "dm")
        return "DRYRUN-%d" % (abs(hash(text)) % 10_000_000)
    resp = proxy_post(
        f"/api/messages/{cfg['dm_channel']}/send",
        {"text": text, "unfurl_links": False, "unfurl_media": False},
        cfg,
    )
    if resp.get("success"):
        return resp.get("data", {}).get("ts")
    log(f"WARNING: send failed: {resp.get('error')}", "dm")
    return None


def delete(cfg, ts, dry):
    if not ts:
        return
    if dry:
        log(f"[dry-run] DELETE {ts}", "dm")
        return
    r = proxy_delete(f"/api/messages/{cfg['dm_channel']}/{ts}", cfg)
    if not r.get("success"):
        log(f"WARNING: delete {ts} failed: {r.get('error')}", "dm")


def main():
    dry = "--dry-run" in sys.argv
    files = [a for a in sys.argv[1:] if not a.startswith("-")]
    if not files:
        print("Usage: dm_rolling.py <new_summary.md> [--dry-run]", file=sys.stderr)
        sys.exit(1)

    cfg = load_config()
    today = datetime.now().strftime("%Y-%m-%d")
    # Substitute the date placeholder so merge_briefing can dedup by date.
    new_text = open(files[0]).read().strip().replace("__BRIEFING_DATE__", today)
    if not new_text:
        log("empty summary, skip", "dm")
        return

    st = load_state()
    df = daily_file(today)

    # ---- 1) Roll today's single message --------------------------------------
    old_body = open(df).read() if (st["today"] == today and os.path.exists(df)) else ""
    if st["today"] != today:  # new day: leave yesterday's message as-is
        st["today"] = today
        st["today_ts"] = None
    new_body = merge_daily(new_text, old_body)

    if not new_body:
        log("no content to post today", "dm")
    elif new_body.strip() == old_body.strip():
        log("no new content today, skip repost", "dm")
    else:
        new_ts = post(cfg, render_daily(today, new_body), dry)
        if new_ts:
            delete(cfg, st.get("today_ts"), dry)  # remove the prior copy of today's msg
            st["today_ts"] = new_ts
            st["days"][today] = new_ts
            os.makedirs(os.path.dirname(df), exist_ok=True)
            with open(df, "w") as f:
                f.write(new_body)
            log(f"rolled daily DM message -> {new_ts}", "dm")

    # ---- 2) Weekly rollup: merge days older than WEEKLY_AFTER_DAYS ------------
    cutoff = datetime.now().date() - timedelta(days=WEEKLY_AFTER_DAYS)
    old_days = sorted(d for d in st["days"] if parse_date(d) and parse_date(d) < cutoff)
    blocks = []
    for d in old_days:
        p = daily_file(d)
        if os.path.exists(p) and open(p).read().strip():
            blocks.append(f"*{d}*\n{open(p).read().strip()}")
    if blocks:
        label = f"{old_days[0]} → {old_days[-1]}"
        message = f":card_index_dividers: *Weekly digest* — {label}\n\n" + "\n\n---\n\n".join(blocks)
        wts = post(cfg, message, dry)
        if wts:
            for d in old_days:
                delete(cfg, st["days"].get(d), dry)
                st["days"].pop(d, None)
            log(f"merged {len(old_days)} day(s) into weekly digest -> {wts}", "dm")

    save_state(st)


if __name__ == "__main__":
    main()

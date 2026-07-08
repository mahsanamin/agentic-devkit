#!/usr/bin/env python3
"""Fetch everything in Slack that is "about me": messages where I'm @mentioned
and threads I'm involved in (tagged in, started, or replied to). Emits one clean,
structured JSON document on stdout for a downstream consumer (e.g. a reply-drafting
routine) to read.

This is the data-fetch half of the workflow ONLY. It reads; it never posts.

It reuses the slack-summarizer backend it lives beside:
  - lib.proxy_get / load_config  → the proxy HTTP client + config
  - lib.load_user_map / extract_users → uid→name resolution
  - convert_mrkdwn.convert        → Slack mrkdwn → readable text

Unlike slack_poll.py (which keeps a watermark and emits only the delta for the
summarizer), this returns the FULL current "about me" view by default, because a
reply assistant needs to see every open thread, not just what changed since the
last poll. Pass --since <ts> for incremental behaviour.

Output schema (stdout):
{
  "generated_at": "ISO8601",
  "user": {"id": "U…", "name": "…"},
  "counts": {"mentions": N, "threads": M, "threads_needing_reply": K},
  "mentions": [ {ts, when, channel_id, channel_name, author_id, author,
                 text, text_resolved, permalink, is_thread_reply, thread_ts} ],
  "threads":  [ {thread_ts, channel_id, channel_name, permalink, reply_count,
                 parent:{…}, replies:[…], last_activity, last_activity_ts,
                 last_from_me, i_am_participant, needs_reply} ]
}

Usage:
  fetch_inbox.py [--count N] [--since TS] [--needs-reply-only]
                 [--compact] [--no-resolve] [--out PATH] [--save] [--quiet]

Exit codes: 0 = ok (even if nothing found), 1 = proxy unreachable / all calls failed.
"""
import argparse, json, os, sys
from datetime import datetime

from lib import load_config, proxy_get, make_permalink, load_user_map, extract_users
from convert_mrkdwn import convert


# ── timestamp / field helpers (mirror the variants slack_poll.py tolerates) ────

def _iso(ts):
    try:
        return datetime.fromtimestamp(float(ts)).isoformat(timespec="seconds")
    except (TypeError, ValueError):
        return ""


def _mention_ts(m):
    return m.get("message_ts") or m.get("ts") or "0"


def _author_id(m):
    return m.get("user_id") or m.get("user") or ""


def _thread_parent(t):
    """Parent message of a thread, across the shapes the proxy returns."""
    p = t.get("parent_message") or t.get("complete_thread", {}).get("parent") or {}
    if not p and (t.get("parent_user_id") or t.get("text")):
        p = {
            "ts": t.get("thread_ts", ""),
            "user_id": t.get("parent_user_id", ""),
            "user_name": t.get("parent_user_name", ""),
            "text": t.get("text", ""),
        }
    return p or {}


def _thread_replies(t):
    return (t.get("replies")
            or t.get("_replies")
            or t.get("complete_thread", {}).get("replies")
            or [])


# ── normalisation ──────────────────────────────────────────────────────────────

def _norm_msg(m, umap, resolve):
    text = m.get("text", "") or ""
    out = {
        "ts": m.get("ts", "") or m.get("message_ts", ""),
        "when": _iso(m.get("ts") or m.get("message_ts")),
        "author_id": _author_id(m),
        "author": m.get("user_name", ""),
        "text": text,
    }
    if resolve:
        out["text_resolved"] = convert(text, umap)
    return out


def _norm_mention(m, umap, cfg, resolve):
    cid = m.get("channel_id", "")
    ts = _mention_ts(m)
    text = m.get("text", "") or ""
    rec = {
        "ts": ts,
        "when": _iso(ts),
        "channel_id": cid,
        "channel_name": m.get("channel_name", ""),
        "author_id": _author_id(m),
        "author": m.get("user_name", ""),
        "text": text,
        "permalink": m.get("permalink") or make_permalink(cid, ts, cfg),
        "is_thread_reply": bool(m.get("is_thread_reply", False)),
        "thread_ts": m.get("thread_ts", ""),
    }
    if resolve:
        rec["text_resolved"] = convert(text, umap)
    return rec


def _norm_thread(t, umap, cfg, my_id, resolve):
    cid = t.get("channel_id", "")
    tts = t.get("thread_ts", "")
    parent = _thread_parent(t)
    replies = _thread_replies(t)

    # All messages in timestamp order to reason about "who spoke last".
    ordered = sorted(
        [msg for msg in ([parent] + list(replies)) if msg and msg.get("ts")],
        key=lambda msg: msg.get("ts", "0"),
    )
    last = ordered[-1] if ordered else (parent or {})
    last_uid = _author_id(last)
    last_from_me = bool(my_id) and last_uid == my_id
    i_am_participant = bool(my_id) and any(_author_id(m) == my_id for m in ordered)
    last_ts = last.get("ts", tts)

    reply_count = (t.get("thread_stats", {}) or {}).get("reply_count")
    if reply_count is None:
        reply_count = t.get("reply_count")
    if reply_count is None:
        reply_count = len(replies)

    return {
        "thread_ts": tts,
        "channel_id": cid,
        "channel_name": t.get("channel_name", ""),
        "permalink": make_permalink(cid, tts, cfg),
        "reply_count": reply_count,
        "parent": _norm_msg(parent, umap, resolve) if parent else {},
        "replies": [_norm_msg(r, umap, resolve) for r in
                    sorted(replies, key=lambda r: r.get("ts", "0"))],
        "last_activity": _iso(last_ts),
        "last_activity_ts": last_ts,
        "last_from_me": last_from_me,
        "i_am_participant": i_am_participant,
        # The signal the reply routine cares about: the latest word isn't mine.
        "needs_reply": not last_from_me,
    }


# ── fetch ────────────────────────────────────────────────────────────────────

def fetch(cfg, count):
    mentions_resp = proxy_get(
        f"/api/mentions/all?count={count}&includeThreads=true", cfg)
    threads_resp = proxy_get(
        f"/api/activity/threads-im-in?count={count}", cfg)
    my_threads_resp = proxy_get(
        f"/api/activity/my-threads?count={count}&includeReplies=true", cfg)

    responses = (mentions_resp, threads_resp, my_threads_resp)
    # Mirror slack_poll.py: if every core call failed, the proxy is unreachable
    # or broken. Fail loudly rather than reporting an empty (but healthy) inbox.
    if not any(r.get("success") for r in responses):
        err = mentions_resp.get("error", "unknown error")
        return None, err, responses

    mentions = mentions_resp.get("data", {}).get("mentions", []) if mentions_resp.get("success") else []
    threads = threads_resp.get("data", {}).get("threads", []) if threads_resp.get("success") else []
    my_threads = my_threads_resp.get("data", {}).get("threads", []) if my_threads_resp.get("success") else []

    # Merge my-threads into threads-im-in, dedup by (thread_ts, channel_id).
    seen = {(t.get("thread_ts", ""), t.get("channel_id", "")) for t in threads}
    for mt in my_threads:
        key = (mt.get("thread_ts", ""), mt.get("channel_id", ""))
        if key not in seen:
            threads.append(mt)
            seen.add(key)

    return {"mentions": mentions, "threads": threads}, None, responses


# ── main ───────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description="Fetch Slack mentions + threads I'm in as JSON.")
    ap.add_argument("--count", type=int, default=30,
                    help="messages/threads to request per endpoint (default 30)")
    ap.add_argument("--since", default=None,
                    help="only items with activity newer than this Slack ts")
    ap.add_argument("--needs-reply-only", action="store_true",
                    help="keep only threads whose last message isn't mine (mentions kept as-is)")
    ap.add_argument("--compact", action="store_true", help="compact JSON (default pretty)")
    ap.add_argument("--no-resolve", action="store_true",
                    help="skip mrkdwn→text resolution (text_resolved omitted)")
    ap.add_argument("--out", default=None, help="also write the JSON to this path")
    ap.add_argument("--save", action="store_true",
                    help="also write to DATA_DIR/inbox/inbox_<date>_<time>.json and print that path to stderr")
    ap.add_argument("--quiet", action="store_true", help="don't print JSON to stdout (use with --out/--save)")
    args = ap.parse_args()

    cfg = load_config()
    my_id = cfg["user_id"]
    resolve = not args.no_resolve

    raw, err, responses = fetch(cfg, args.count)
    if raw is None:
        print(f"ERROR: Slack proxy unreachable/failing at {cfg['proxy_url']}: {err}",
              file=sys.stderr)
        sys.exit(1)

    # uid→name map: persistent cache + names seen in this payload.
    umap = load_user_map(cfg)
    umap.update(extract_users(raw))

    mentions = [_norm_mention(m, umap, cfg, resolve) for m in raw["mentions"]]
    threads = [_norm_thread(t, umap, cfg, my_id, resolve) for t in raw["threads"]]

    if args.since:
        mentions = [m for m in mentions if m["ts"] > args.since]
        threads = [t for t in threads if (t["last_activity_ts"] or "0") > args.since]

    if args.needs_reply_only:
        threads = [t for t in threads if t["needs_reply"]]

    # Newest first — most actionable at the top.
    mentions.sort(key=lambda m: m["ts"], reverse=True)
    threads.sort(key=lambda t: t["last_activity_ts"] or "0", reverse=True)

    doc = {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "user": {"id": my_id, "name": cfg["user_name"]},
        "counts": {
            "mentions": len(mentions),
            "threads": len(threads),
            "threads_needing_reply": sum(1 for t in threads if t["needs_reply"]),
        },
        "mentions": mentions,
        "threads": threads,
    }

    text = json.dumps(doc, separators=(",", ":")) if args.compact else json.dumps(doc, indent=2)

    if args.out:
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        with open(args.out, "w") as f:
            f.write(text)
        print(f"wrote {args.out}", file=sys.stderr)

    if args.save:
        d = os.path.join(cfg["data_dir"], "inbox")
        os.makedirs(d, exist_ok=True)
        path = os.path.join(d, f"inbox_{datetime.now().strftime('%Y-%m-%d_%H%M%S')}.json")
        with open(path, "w") as f:
            f.write(text)
        # also keep a stable "latest" pointer for the routine
        with open(os.path.join(d, "latest.json"), "w") as f:
            f.write(text)
        print(f"saved {path}", file=sys.stderr)

    # Partial-failure note so cron logs explain a thin inbox.
    failed = [name for name, r in zip(("mentions", "threads-im-in", "my-threads"), responses)
              if not r.get("success")]
    if failed:
        print(f"WARNING: some endpoints failed: {', '.join(failed)}", file=sys.stderr)

    c = doc["counts"]
    print(f"[inbox] mentions={c['mentions']} threads={c['threads']} "
          f"need_reply={c['threads_needing_reply']}", file=sys.stderr)

    if not args.quiet:
        print(text)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Offline test of fetch_inbox normalization against the real proxy field variants.
Monkeypatches proxy_get so no network is needed.

Run from this directory:  python3 test_fetch_inbox.py
"""
import io, json, os, sys, contextlib

# Self-contained: FORCE the identity/config fetch_inbox.load_config() expects, so the
# test is deterministic and offline. We must override (not setdefault) because a real
# config.env is usually already sourced into the shell — letting it win would make
# `my_id` mismatch the fixture below and silently break the last_from_me assertions.
os.environ["MY_SLACK_USER_ID"] = "U0ME00001"
os.environ["MY_SLACK_USER_NAME"] = "me"
os.environ["SLACK_WORKSPACE_URL"] = "https://x.slack.com"
os.environ["DATA_DIR"] = "/tmp/sinbox_test_data"

import fetch_inbox

ME = "U0ME00001"

MENTIONS = [
    # variant: uses message_ts (not ts), has explicit permalink
    {"message_ts": "1712345678.100000", "user_id": "U0ALICE01", "user_name": "alice",
     "text": "hey <@U0ME00001> can you review this?", "channel_id": "C_ENG",
     "channel_name": "engineering",
     "permalink": "https://x.slack.com/archives/C_ENG/p1712345678100000",
     "is_thread_reply": False, "thread_ts": ""},
    # variant: uses ts, no permalink (must be constructed)
    {"ts": "1712345600.000000", "user_id": "U0BOB0001", "user_name": "bob",
     "text": "<@U0ME00001> ship it", "channel_id": "C_OPS", "channel_name": "ops"},
]

# threads-im-in: parent_message + replies, LAST reply is mine -> needs_reply False
THREADS_IM_IN = [
    {"thread_ts": "1712300000.000000", "channel_id": "C_ENG", "channel_name": "engineering",
     "parent_message": {"ts": "1712300000.000000", "user_id": "U0ALICE01",
                        "user_name": "alice", "text": "deploy plan?"},
     "replies": [
        {"ts": "1712300100.000000", "user_id": "U0BOB0001", "user_name": "bob", "text": "thoughts?"},
        {"ts": "1712300200.000000", "user_id": ME, "user_name": "me", "text": "doing it now"},
     ],
     "thread_stats": {"reply_count": 2}},
]

# my-threads: complete_thread shape + _replies + reply uses `user` (not user_id);
# last msg from someone else -> needs_reply True. Also one DUPLICATE of the above
# thread (same thread_ts+channel) to test dedup.
MY_THREADS = [
    {"thread_ts": "1712400000.000000", "channel_id": "C_OPS", "channel_name": "ops",
     "complete_thread": {
        "parent": {"ts": "1712400000.000000", "user_id": ME, "user_name": "me",
                   "text": "anyone seen the incident?"},
        "replies": [
            {"ts": "1712400100.000000", "user": "U0CAROL01", "user_name": "carol",
             "text": "looking into it"},
        ],
     }},
    # duplicate of THREADS_IM_IN[0] — must be deduped away
    {"thread_ts": "1712300000.000000", "channel_id": "C_ENG", "channel_name": "engineering",
     "parent_message": {"ts": "1712300000.000000", "user_id": "U0ALICE01",
                        "user_name": "alice", "text": "deploy plan?"}},
]


def fake_proxy_get(endpoint, cfg=None, **kw):
    if "mentions" in endpoint:
        return {"success": True, "data": {"mentions": MENTIONS}}
    if "threads-im-in" in endpoint:
        return {"success": True, "data": {"threads": THREADS_IM_IN}}
    if "my-threads" in endpoint:
        return {"success": True, "data": {"threads": MY_THREADS}}
    return {"success": False, "error": "unexpected"}


def run(argv, proxy=fake_proxy_get):
    fetch_inbox.proxy_get = proxy
    out = io.StringIO()
    try:
        with contextlib.redirect_stdout(out):
            sys.argv = ["fetch_inbox.py"] + argv
            fetch_inbox.main()
    except SystemExit as e:
        return None, e.code
    return json.loads(out.getvalue()), 0


def main():
    doc, code = run(["--count", "10"])
    assert code == 0, f"unexpected exit {code}"

    # ---- counts: dedup worked (3 unique threads, not 4) ----
    assert doc["counts"]["threads"] == 2, doc["counts"]
    assert doc["counts"]["mentions"] == 2, doc["counts"]

    # ---- mentions ----
    m_by_author = {m["author"]: m for m in doc["mentions"]}
    # message_ts variant captured as ts
    assert m_by_author["alice"]["ts"] == "1712345678.100000"
    # permalink constructed when missing (bob had none)
    assert m_by_author["bob"]["permalink"].endswith("/archives/C_OPS/p1712345600000000"), m_by_author["bob"]["permalink"]
    # text resolution: <@U0ME00001> -> @me (from payload user map)
    assert "@me" in m_by_author["alice"]["text_resolved"], m_by_author["alice"]["text_resolved"]

    # ---- threads ----
    t_by_ch = {t["channel_id"]: t for t in doc["threads"]}
    eng = t_by_ch["C_ENG"]
    ops = t_by_ch["C_OPS"]

    # ENG thread: last msg is mine -> already replied
    assert eng["last_from_me"] is True, eng
    assert eng["needs_reply"] is False, eng
    assert eng["i_am_participant"] is True
    assert eng["reply_count"] == 2
    assert len(eng["replies"]) == 2

    # OPS thread (complete_thread + _replies + `user` field): last is carol -> needs reply
    assert ops["last_from_me"] is False, ops
    assert ops["needs_reply"] is True, ops
    assert ops["i_am_participant"] is True  # I authored the parent
    assert ops["replies"][0]["author_id"] == "U0CAROL01"  # `user` field mapped to author_id
    assert ops["parent"]["text"] == "anyone seen the incident?"

    # needs_reply count
    assert doc["counts"]["threads_needing_reply"] == 1, doc["counts"]

    # ---- --needs-reply-only filter ----
    doc2, code2 = run(["--needs-reply-only"])
    assert code2 == 0
    assert all(t["needs_reply"] for t in doc2["threads"])
    assert len(doc2["threads"]) == 1

    # ---- loud failure when every endpoint fails ----
    _, code3 = run(["--count", "1"],
                   proxy=lambda *a, **k: {"success": False, "error": "HTTP 502"})
    assert code3 == 1, f"expected exit 1 on total failure, got {code3}"

    print("ALL TESTS PASSED")


if __name__ == "__main__":
    main()

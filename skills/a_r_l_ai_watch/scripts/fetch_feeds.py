#!/usr/bin/env python3
"""fetch_feeds.py

Deterministic discovery layer for a_r_l_ai_watch. Pulls high-volume AI sources that
have clean APIs (Hacker News via Algolia, arXiv) and prints a deduped, timestamped
markdown digest of candidate items with stable keys. This keeps frequent runs cheap:
the skill reads this digest, dedupes against _state.md, and only the editorial layer
(company/lab blogs, launches, policy) needs live WebSearch.

These are LEADS, not final entries. Most are noise. The skill curates and follows each
link to its primary source before logging.

Pure stdlib, no network writes, fails soft (a dead source degrades to a note, never aborts).

Usage:
  python3 fetch_feeds.py [--since ISO8601] [--max N] [--min-points P]
    --since        only items at or after this UTC time (default: 24h ago)
    --max          max items per source after filtering (default: 25)
    --min-points   minimum Hacker News points to keep (default: 15)
"""
import argparse
import json
import urllib.request
import urllib.parse
import xml.etree.ElementTree as ET
from datetime import datetime, timezone, timedelta

UA = {"User-Agent": "a_r_l_ai_watch/1.0 (personal AI news tracker)"}


def safe_xml(text):
    """Parse XML without exposing the XXE / billion-laughs holes the stdlib parser has.
    Prefer defusedxml; otherwise use stdlib expat with entity declarations forbidden
    (blocks internal-entity expansion), and external entities are not fetched anyway
    since no ExternalEntityRefHandler is set."""
    try:
        from defusedxml.ElementTree import fromstring as _defused
        return _defused(text)
    except ImportError:
        parser = ET.XMLParser()
        try:
            def _no_entities(*_a, **_k):
                raise ValueError("XML entity declarations are disabled")
            parser.parser.EntityDeclHandler = _no_entities
        except Exception:
            pass
        return ET.fromstring(text, parser=parser)


def now_utc():
    return datetime.now(timezone.utc)


def parse_iso(s):
    if not s:
        return None
    s = s.strip().replace("Z", "+00:00")
    try:
        d = datetime.fromisoformat(s)
        return d if d.tzinfo else d.replace(tzinfo=timezone.utc)
    except Exception:
        return None


def get(url, timeout=15):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


def fetch_hn(since, cap, min_points):
    """Hacker News stories about AI, newest first, via the Algolia API."""
    queries = ["AI model", "LLM", "open source AI", "artificial intelligence"]
    since_epoch = int(since.timestamp())
    seen, items = set(), []
    for q in queries:
        params = urllib.parse.urlencode({
            "query": q,
            "tags": "story",
            "numericFilters": f"created_at_i>{since_epoch},points>={min_points}",
            "hitsPerPage": 40,
        })
        url = f"https://hn.algolia.com/api/v1/search_by_date?{params}"
        try:
            data = json.loads(get(url))
        except Exception as e:
            items.append(("err", f"HN query '{q}' failed: {e}", None, None))
            continue
        for h in data.get("hits", []):
            oid = h.get("objectID")
            if not oid or oid in seen:
                continue
            seen.add(oid)
            link = h.get("url") or f"https://news.ycombinator.com/item?id={oid}"
            items.append((
                h.get("created_at", ""),
                (h.get("title") or "(untitled)").strip(),
                link,
                f"hn:{oid} | {h.get('points', 0)} pts",
            ))
    items = [i for i in items if i[0] != "err"] + [i for i in items if i[0] == "err"]
    real = sorted([i for i in items if i[0] != "err"], key=lambda x: x[0], reverse=True)[:cap]
    errs = [i for i in items if i[0] == "err"]
    return real + errs


def fetch_arxiv(since, cap):
    """Recent arXiv submissions in cs.AI / cs.LG / cs.CL, newest first."""
    params = urllib.parse.urlencode({
        "search_query": "cat:cs.AI OR cat:cs.LG OR cat:cs.CL",
        "sortBy": "submittedDate",
        "sortOrder": "descending",
        "max_results": 40,
    })
    url = f"http://export.arxiv.org/api/query?{params}"
    try:
        xml = get(url)
    except Exception as e:
        return [("err", f"arXiv failed: {e}", None, None)]
    ns = {"a": "http://www.w3.org/2005/Atom"}
    out = []
    try:
        root = safe_xml(xml)
    except Exception as e:
        return [("err", f"arXiv parse failed: {e}", None, None)]
    for e in root.findall("a:entry", ns):
        pub = (e.findtext("a:published", default="", namespaces=ns) or "").strip()
        d = parse_iso(pub)
        if d and d < since:
            continue
        title = " ".join((e.findtext("a:title", default="", namespaces=ns) or "").split())
        link = (e.findtext("a:id", default="", namespaces=ns) or "").strip()
        aid = link.rsplit("/", 1)[-1] if link else "?"
        out.append((pub, title or "(untitled)", link, f"arxiv:{aid}"))
    return sorted(out, key=lambda x: x[0], reverse=True)[:cap]


def emit(title, rows):
    print(f"### {title}")
    if not rows:
        print("- (none in window)")
        print()
        return
    for created, t, link, key in rows:
        if created == "err":
            print(f"- NOTE: {t}")
        else:
            day = (created or "")[:10]
            print(f"- [{t}]({link}) | {day} | {key}")
    print()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since")
    ap.add_argument("--max", type=int, default=25)
    ap.add_argument("--min-points", type=int, default=15)
    args = ap.parse_args()

    since = parse_iso(args.since) or (now_utc() - timedelta(hours=24))

    print("# AI feed digest (candidates, not final entries)")
    print(f"_since: {since.isoformat()} | generated: {now_utc().isoformat()}_")
    print("_Follow each link to its primary source before logging. Most items are noise; curate._")
    print()
    emit("Hacker News (AI stories)", fetch_hn(since, args.max, args.min_points))
    emit("arXiv (cs.AI / cs.LG / cs.CL, recent)", fetch_arxiv(since, args.max))
    print("_End of digest. Editorial sources (lab/company blogs, launches, policy) are NOT here; use WebSearch for those._")


if __name__ == "__main__":
    main()

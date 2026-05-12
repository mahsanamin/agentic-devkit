#!/usr/bin/env python3
"""Merge new briefing into existing latest.md with thread dedup.

Usage: python3 merge_briefing.py <new.md> <existing.md> <output.md>
"""
import re, sys, os
from datetime import datetime, timedelta

MAX_AGE_DAYS = 2

def extract_link_keys(text):
    """Extract thread keys from all Slack link formats."""
    keys = set()
    for m in re.finditer(r'slack://channel\?team=[^&]+&id=([A-Z0-9]+)&message=([0-9.]+)', text):
        keys.add(f"{m.group(1)}:{m.group(2)}")
    for m in re.finditer(r'[\w-]+\.slack\.com/archives/([A-Z0-9]+)/p(\d+)', text):
        raw_ts = m.group(2)
        ts = f"{raw_ts[:10]}.{raw_ts[10:]}" if len(raw_ts) > 10 else raw_ts
        keys.add(f"{m.group(1)}:{ts}")
    for m in re.finditer(r'slack\.com/app_redirect\?team=[^&]+&channel=([A-Z0-9]+)&message_ts=([0-9.]+)', text):
        keys.add(f"{m.group(1)}:{m.group(2)}")
    return keys

MONTHS = {'jan':'01','feb':'02','mar':'03','apr':'04','may':'05','jun':'06',
          'jul':'07','aug':'08','sep':'09','oct':'10','nov':'11','dec':'12'}

def extract_date(section):
    m = re.search(r'Briefing.*?(\d{4}-\d{2}-\d{2})', section)
    if m:
        return m.group(1)
    m = re.search(r'Briefing.*?((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\w*)\s+(\d+),?\s+(\d{4})', section, re.IGNORECASE)
    if m:
        mon = MONTHS.get(m.group(1)[:3].lower())
        if mon:
            return f"{m.group(3)}-{mon}-{int(m.group(2)):02d}"
    return None

def has_content(section):
    for line in section.split("\n"):
        s = line.strip()
        if not s or s.startswith("_Last synced"):
            continue
        if re.match(r'^[\U0001F4F0].*Briefing', s):
            continue
        if re.match(r'^[\U0001F300-\U0001FFFF\u2600-\u27FF\u2B00-\u2BFF]', s) and 'slack.com' not in s and 'slack://' not in s:
            continue
        return True
    return False

def merge(new_text, old_text):
    old_text = re.sub(r'^_Last synced:.*_\n*', '', old_text).strip()
    old_sections = [s.strip() for s in re.split(r'\n---\n', old_text) if s.strip()]
    new_links = extract_link_keys(new_text)
    new_date = extract_date(new_text)
    kept = []

    for section in old_sections:
        section_date = extract_date(section)
        if section_date and new_date and section_date == new_date:
            lines = section.split("\n")
            filtered = []
            skip = False
            for line in lines:
                if extract_link_keys(line) & new_links:
                    skip = True
                    continue
                if skip and not line.strip():
                    skip = False
                    continue
                skip = False
                filtered.append(line)
            remaining = "\n".join(filtered).strip()
            if has_content(remaining):
                body_lines = [l for l in remaining.split("\n") if not re.match(r'^[\U0001F4F0].*Briefing', l.strip())]
                body = "\n".join(body_lines).strip()
                if body:
                    new_text = new_text.rstrip() + "\n\n" + body
            continue

        if section_date:
            try:
                age = datetime.now().date() - datetime.strptime(section_date, "%Y-%m-%d").date()
                if age > timedelta(days=MAX_AGE_DAYS):
                    continue
            except ValueError:
                pass

        section_links = extract_link_keys(section)
        if section_links & new_links:
            lines = [l for l in section.split("\n") if not (extract_link_keys(l) & new_links)]
            section = "\n".join(lines).strip()
        if has_content(section):
            kept.append(section)

    sync_ts = datetime.now().strftime('%Y-%m-%d %H:%M')
    parts = [f"_Last synced: {sync_ts}_\n\n{new_text}"] + kept
    return "\n\n---\n\n".join(parts) + "\n"

def main():
    if len(sys.argv) < 4:
        print("Usage: merge_briefing.py <new.md> <existing.md> <output.md>", file=sys.stderr)
        sys.exit(1)

    with open(sys.argv[1]) as f:
        new_text = f.read().strip()
    try:
        with open(sys.argv[2]) as f:
            old_text = f.read().strip()
    except FileNotFoundError:
        old_text = ""

    result = merge(new_text, old_text)
    with open(sys.argv[3], "w") as f:
        f.write(result)

if __name__ == "__main__":
    main()

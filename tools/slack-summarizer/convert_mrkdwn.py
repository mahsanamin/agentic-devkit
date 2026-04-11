#!/usr/bin/env python3
"""Convert Slack mrkdwn to Markdown. Resolves user IDs, channels, emojis.

Usage: python3 convert_mrkdwn.py [--user-map <path>] < input.md > output.md
       python3 convert_mrkdwn.py <input_file> [--user-map <path>]
"""
import json, re, sys, os
from lib import load_user_map

EMOJI_MAP = {
    ':newspaper:': '\U0001F4F0', ':zap:': '\u26A1', ':rotating_light:': '\U0001F6A8',
    ':warning:': '\u26A0\uFE0F', ':hammer_and_wrench:': '\U0001F6E0\uFE0F',
    ':globe_with_meridians:': '\U0001F310', ':eyes:': '\U0001F440',
    ':white_check_mark:': '\u2705', ':white_square_button:': '\u2B1C',
    ':point_right:': '\U0001F449', ':fire:': '\U0001F525', ':rocket:': '\U0001F680',
    ':bulb:': '\U0001F4A1', ':memo:': '\U0001F4DD', ':link:': '\U0001F517',
    ':lock:': '\U0001F512', ':gear:': '\u2699\uFE0F', ':tada:': '\U0001F389',
    ':x:': '\u274C', ':heavy_check_mark:': '\u2714\uFE0F', ':clock3:': '\U0001F552',
    ':speech_balloon:': '\U0001F4AC', ':pushpin:': '\U0001F4CC',
    ':red_circle:': '\U0001F534', ':large_blue_circle:': '\U0001F535',
    ':arrow_right:': '\u27A1\uFE0F', ':hourglass:': '\u231B',
    ':chart_with_upwards_trend:': '\U0001F4C8', ':wrench:': '\U0001F527',
    ':package:': '\U0001F4E6', ':bookmark:': '\U0001F516',
}

def convert(text, user_map=None):
    if user_map is None:
        user_map = {}

    # <@USERID|name> → @name
    text = re.sub(r'<@([A-Z0-9]+)\|([^>]+)>', lambda m: f"@{m.group(2)}", text)
    # <@USERID> → @name
    text = re.sub(r'<@([A-Z0-9]+)>', lambda m: f"@{user_map.get(m.group(1), m.group(1))}", text)
    # <#CID|name> → #name
    text = re.sub(r'<#[A-Z0-9]+\|([^>]+)>', r'#\1', text)
    text = re.sub(r'<#([A-Z0-9]+)>', r'#\1', text)
    # <!here>, <!channel>, <!everyone>
    text = re.sub(r'<!here>', '@here', text)
    text = re.sub(r'<!channel>', '@channel', text)
    text = re.sub(r'<!everyone>', '@everyone', text)
    # <!subteam^ID|name>
    text = re.sub(r'<!subteam\^[A-Z0-9]+\|([^>]+)>', r'@\1', text)
    text = re.sub(r'<!subteam\^[A-Z0-9]+>', '@team', text)
    # <url|label> → [label](url)
    text = re.sub(r'<(https?://[^|>]+)\|([^>]+)>', r'[\2](\1)', text)
    # <url> → url
    text = re.sub(r'<(https?://[^>]+)>', r'\1', text)
    # Clean truncated tags
    text = re.sub(r'<@[A-Z0-9]*$', '', text, flags=re.MULTILINE)
    text = re.sub(r'<@[A-Z0-9]+ ', ' ', text)
    text = re.sub(r'<#[A-Z0-9]+ ', ' ', text)
    # Emojis
    for code, uni in EMOJI_MAP.items():
        text = text.replace(code, uni)
    text = re.sub(r':([a-z0-9_+-]+):', r'\1', text)
    return text

def main():
    user_map_path = None
    input_file = None

    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--user-map" and i + 1 < len(args):
            user_map_path = args[i + 1]
            i += 2
        elif not args[i].startswith("-"):
            input_file = args[i]
            i += 1
        else:
            i += 1

    # Load user map
    user_map = {}
    if user_map_path:
        try:
            with open(user_map_path) as f:
                data = json.load(f)
                user_map = data.get("user_map", data) if isinstance(data, dict) else {}
        except Exception:
            pass
    else:
        user_map = load_user_map()

    # Read input
    if input_file:
        with open(input_file) as f:
            text = f.read()
    else:
        text = sys.stdin.read()

    print(convert(text, user_map), end="")

if __name__ == "__main__":
    main()

"""Clean Slack mrkdwn syntax from markdown files.

Usage: python3 clean_slack_mrkdwn.py <enriched_json> <output_dir>

Reads user_map from enriched JSON to resolve <@USERID> to @username.
Processes all .md files in output_dir.
"""
import json, sys, re, os, glob

enriched_file, out_dir = sys.argv[1], sys.argv[2]

with open(enriched_file) as f:
    data = json.load(f)

user_map = data.get("user_map", {})


def clean_slack_mrkdwn(text):
    """Replace Slack mrkdwn with plain markdown equivalents."""

    # <@USERID|name> -> @name
    def replace_user_with_name(m):
        return f"@{m.group(2)}"

    # <@USERID> -> @name (lookup from user_map)
    def replace_user_id(m):
        uid = m.group(1)
        name = user_map.get(uid, uid)
        return f"@{name}"

    text = re.sub(r'<@([A-Z0-9]+)\|([^>]+)>', replace_user_with_name, text)
    text = re.sub(r'<@([A-Z0-9]+)>', replace_user_id, text)

    # <#CHANNELID|name> -> #name
    text = re.sub(r'<#[A-Z0-9]+\|([^>]+)>', r'#\1', text)
    text = re.sub(r'<#([A-Z0-9]+)>', r'#\1', text)

    # <!here>, <!channel>, <!everyone>
    text = re.sub(r'<!here>', '@here', text)
    text = re.sub(r'<!channel>', '@channel', text)
    text = re.sub(r'<!everyone>', '@everyone', text)

    # <!subteam^ID|name> or <!subteam^ID>
    text = re.sub(r'<!subteam\^[A-Z0-9]+\|([^>]+)>', r'@\1', text)
    text = re.sub(r'<!subteam\^[A-Z0-9]+>', '@team', text)

    # <url|label> -> [label](url)
    text = re.sub(r'<(https?://[^|>]+)\|([^>]+)>', r'[\2](\1)', text)
    # <url> -> url
    text = re.sub(r'<(https?://[^>]+)>', r'\1', text)

    # Clean up truncated/incomplete Slack tags (from text truncation at char limit)
    text = re.sub(r'<@[A-Z0-9]*$', '', text, flags=re.MULTILINE)
    text = re.sub(r'<@[A-Z0-9]+(?:\|[^>]*)?$', '', text, flags=re.MULTILINE)
    text = re.sub(r'<#[A-Z0-9]*$', '', text)
    text = re.sub(r'<!subteam\^[A-Z0-9]*$', '', text)
    # Bare <@ with space (no ID at all)
    text = re.sub(r'<@ ', ' ', text)
    # Mid-text truncated tags like "<@U03NCQV0D " (no closing >)
    text = re.sub(r'<@[A-Z0-9]+ ', ' ', text)
    text = re.sub(r'<#[A-Z0-9]+ ', ' ', text)

    return text


for md_file in glob.glob(os.path.join(out_dir, "*.md")):
    with open(md_file) as f:
        content = f.read()
    cleaned = clean_slack_mrkdwn(content)
    if cleaned != content:
        with open(md_file, "w") as f:
            f.write(cleaned)
        print(f"  Cleaned: {os.path.basename(md_file)}", file=sys.stderr)
    else:
        print(f"  No changes: {os.path.basename(md_file)}", file=sys.stderr)

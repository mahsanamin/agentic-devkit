# File templates

Exact structure for the five files. Keep the shape stable across runs so diffs and dedup stay clean. Dates are ISO. No em or en dashes anywhere; use colons, commas, or parentheses.

---

## news.md

```markdown
# AI News (the field)

> General AI news, newest first. Maintained by a_r_l_ai_watch.
> Claude and Anthropic deep dives live in StayUptoDate/Claude, not here.

## YYYY-MM-DD

### <headline>
- **What:** <one or two lines>
- **Source:** <primary url> (<outlet>)
- **Why it matters:** <one line>

## Archive (older than ~2 months)

<entries moved down here, same format, not deleted>
```

---

## advancements.md

```markdown
# AI Advancements and Research

> Capability and research progress, newest first: SOTA models, benchmark jumps, papers, new methods.

## YYYY-MM-DD

### <title>
- **What:** <what is newly possible or better>
- **Who:** <lab or authors>
- **Source:** <primary url, the paper or the lab post>
- **Significance:** <why it is a step forward, one line>

## Archive (older than ~2 months)
```

---

## technology.md

```markdown
# AI Technology and Tools

> New tools, products, frameworks, infra, and APIs a builder could use, newest first.

## YYYY-MM-DD

### <tool or product>
- **What:** <one line>
- **Category:** <agent framework | API | model serving | dev tool | hardware | data | other>
- **Source:** <product page or repo>
- **Could I use it:** <one line through his lens: an eng leader building AI workflows at a travel company>

## Archive (older than ~2 months)
```

---

## terms.md

```markdown
# New AI Terms and Concepts

> Vocabulary entering the AI field, with plain definitions. Maintained by a_r_l_ai_watch.

| Term | Plain definition | Context (why it surfaced) | First seen | Source |
|---|---|---|---|---|
| <term> | <one clear sentence, no jargon> | <where it is showing up> | YYYY-MM-DD | <url> |
```

Note: key by term. Add a row only if the term is not already in the table.

---

## _state.md

```markdown
# _state (bookkeeping for a_r_l_ai_watch, do not hand-edit)

```json
{
  "resolved_base": "@srv-ahsan-mini/mahsan_brain/StayUptoDate/GloballyAI",
  "last_run": "YYYY-MM-DDTHH:MM:SSZ",
  "seen_keys": ["hn:48591348", "arxiv:2606.20547v1", "url:https://example.com/post"],
  "last_change_summary": "one line, e.g. 'added 3: 2 advancements, 1 tool' or 'no new items'"
}
```
```

Notes:
- `last_run` is a full UTC timestamp (from `date -u`), not just a date, so multiple runs per day stay incremental.
- `seen_keys` is the dedup cache. Append new keys each run and trim to the most recent ~500. The files themselves are the durable record; this list just makes dedup fast.

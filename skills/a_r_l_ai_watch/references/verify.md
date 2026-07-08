# Self-verify rubric

Run after writing, before reporting done. This skill runs unattended and often, so its failure modes are: duplicates creeping in across runs, items filed in the wrong bucket, noise logged as signal, claims from a weak source, and the standing formatting rules. If subagents are available, hand a verifier this rubric and the file paths and tell it to be adversarial; otherwise check inline. Fix high and medium findings, then continue. Keep the loop bounded; do not spin on nits.

## The checks

1. **Dedup held.** No item appears twice within a file, and nothing added this run duplicates an entry already present from a prior run (check by URL and by headline). Duplicates are the top risk for a frequently-run skill, so this is a high-severity check.
2. **Routing is correct.** Each item is in the right file per the taxonomy: news (what happened), advancements (what got better / newly possible), technology (what I could build with), terms (what a word means). An item should not be split across files.
3. **Signal, not noise.** Entries are genuinely notable. Flag obvious firehose noise that slipped through (an off-topic Hacker News story, a minor incremental paper logged as a breakthrough).
4. **Sources are primary and real.** Each entry links to a source you could actually open, ideally the lab post / paper / product page, not an aggregator or a Hacker News comment page. Flag dead-looking, circular, or content-farm links.
5. **Dates sane.** ISO format, newest first, nothing dated after today, date headings consistent.
6. **terms.md.** Definitions are plain and correct, one term per row, no duplicate terms.
7. **Formatting.** Zero em dashes (—) and en dashes (–) anywhere (grep all files). Mermaid for any diagram, never ASCII art.
8. **_state.md.** Parseable JSON; `last_run` is a full timestamp; `seen_keys` includes the keys for items added this run; `resolved_base` matches where the files live.

## Suggested verifier output

A fenced ```json block:

```json
{
  "overall_satisfied": true,
  "em_dash_check": "pass",
  "duplicate_check": "pass",
  "findings": [
    {"file": "...", "severity": "high|med|low", "issue": "...", "evidence": "<quote>", "suggested_fix": "..."}
  ],
  "summary": "bottom line"
}
```

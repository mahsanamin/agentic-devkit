# Self-verify rubric

Run this after the files are written, before you tell the user you are done. The point is to catch the failure modes this skill is prone to: features invented from stale memory, wrong version-to-feature mappings, probe noise leaking into "what I use", and the standing formatting rules. A real second run found a model marked GA that had since been suspended, so this step is not ceremony.

## How to run it

If subagents are available (interactive session, or a cloud run that allows them), spawn one verifier agent and hand it this rubric plus the file paths. Tell it to be adversarial (assume there are mistakes) and to return structured findings, not prose. Then fix what it flags and, for anything material, re-verify. If subagents are not available, run the checklist inline yourself with the same skepticism. Either way the verifier only reads; the main agent does the fixing.

Keep the loop bounded: verify, fix the high and medium findings, re-check those. Do not spin on low-severity nits.

## The checks

1. **Completeness.** All four files present and non-trivial (`mdnest read` each).
2. **No invented or noise entries in terms.md Part A.** Every "what I use" row must trace to the probe output or a real read of his config. Flag anything that looks like probe noise (a `*-workspace` directory, a plugin internal file like `blocklist.json` or `cache`) or a feature he does not actually use.
3. **Watchlist quality.** Every Part B item carries a specific, personal "why it fits me" tied to his real stack, not a generic benefit. Statuses (🟢🟡⚪🔴) are present and sensible.
4. **news.md shape.** Dated, newest first, each entry has What + Source + Relevance. No dates after today. No internal contradictions (for example a model both "adopt this" and "suspended").
5. **Factual accuracy against primary sources.** Spot-check the load-bearing version-to-feature mappings and model claims against the official changelog (`code.claude.com/docs/en/changelog.md`) and, for model availability or anything high-stakes, the Anthropic news page. Mark each as supported, contradicted, or unverifiable. Anything contradicted is a high-severity fix.
6. **Formatting rules.** Zero em dashes (—) and en dashes (–) anywhere (grep all four files). Diagrams, if any, are Mermaid, not ASCII art.
7. **_state.md.** Contains a parseable JSON block with a version watermark and an ISO date, and `resolved_base` matches where the files actually live.

## Suggested verifier output shape

A fenced ```json block:

```json
{
  "overall_satisfied": true,
  "em_dash_check": "pass",
  "findings": [
    {"file": "...", "severity": "high|med|low", "issue": "...", "evidence": "<quote>", "suggested_fix": "..."}
  ],
  "factual_flags": [
    {"claim": "...", "file": "...", "primary_source_says": "...", "verdict": "supported|contradicted|unverifiable"}
  ],
  "summary": "bottom line"
}
```

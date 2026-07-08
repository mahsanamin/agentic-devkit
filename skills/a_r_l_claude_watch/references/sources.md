# Sources to check each run

Goal: collect what changed since the `_state.md` watermark, not the whole history. Anchor every query on the last-seen version and today's date. Verify live; never trust training memory for version numbers, release dates, or "is this still the latest" claims.

## Tier 1: the agent (use first for Claude Code, API, SDK)

The `claude-code-guide` agent is purpose-built for "Can Claude... / Does Claude... / How do I..." questions about Claude Code, the Agent SDK, and the API, and it has web access. Spawn it with a pointed prompt, for example:

> What shipped in Claude Code since version `<watermark>`? List new slash commands, skills/agent features, hooks, settings, and MCP changes. Also list anything Anthropic has announced as coming soon. Cite sources.

This is usually the fastest high-signal pass. Treat its output as a lead, then confirm specifics against Tier 2 if they will land in the tracker.

## Tier 2: canonical pages (WebFetch, these are HTML)

- Claude Code changelog (canonical, fetches cleanly as markdown): `https://code.claude.com/docs/en/changelog.md`
- Docs release notes hub: `https://docs.claude.com/en/release-notes/overview`
  - Claude Code: `https://docs.claude.com/en/release-notes/claude-code`
  - API: `https://docs.claude.com/en/release-notes/api`
  - Claude apps: `https://docs.claude.com/en/release-notes/claude-apps`
  - System prompts: `https://docs.claude.com/en/release-notes/system-prompts`
- Claude Code docs root (feature pages): `https://docs.claude.com/en/docs/claude-code/overview`
- Anthropic news / announcements: `https://www.anthropic.com/news`
- Anthropic engineering blog (deeper technique posts): `https://www.anthropic.com/engineering`

URLs drift over time. If one 404s, fall back to a WebSearch for the same thing and update this list.

## Tier 3: targeted WebSearch (for models, pricing, app features)

Scope queries to recency. Examples:

- `Claude Code release notes <current month> <year>`
- `Anthropic Claude new model announcement <year>`
- `Claude Code new feature <quarter> <year>`
- `Claude API changelog <month> <year>`

## Deterministic, no research needed

- Latest Claude Code version: `scripts/probe.sh` reads it from the npm registry.
- The user's installed version and full local toolkit: also from `scripts/probe.sh`.

## Source quality

Rank sources: official changelog and `docs.claude.com` / `anthropic.com` first, then reputable tech press, then blogs and aggregators last. Put a version or feature claim in the tracker only when a primary source supports it. If the only source is a third-party blog, you can still log it, but label it "(third-party, unconfirmed)" and hedge the relevance. And remember a primary source can override a stale one: a model can look GA in the changelog yet be suspended on the Anthropic news page, so confirm model availability and other high-stakes claims against the news page, not just the changelog.

## Framing the diff

The watermark in `_state.md` (`claude_code_version_seen`, `last_run`) defines "new." If the installed/latest Claude Code version jumped several minor versions since last run, read every changelog entry in that range. If nothing moved and `last_run` was recent, a light pass is fine; say so in the report rather than padding.

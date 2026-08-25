## This machine is managed

Every file under `~/.claude/skills/` and `~/.claude/agents/` is a **symlink into a git repo**.
Edit the repo and commit there. Never edit through a link, and never drop a real file into
`~/.claude/` — a real file there is unmanaged, invisible to every other machine, and lost on a
rebuild.

This rules file is **generated**. The region between the `agentic-devkit: managed memory`
markers is composed from source files by `a_c_claude_memory build`. Editing inside the region
works until the next build, then it is gone. Edit the source listed at the top of the region,
then run `a_c_claude_memory build`. Anything outside the markers is hand-written and is never
touched by the tooling.

### Identity — always say which machine you are on

The machine's name and role are in the **Machine** section below. Say that name whenever the
host is even slightly in question: asked who or where you are, asked what you can see, starting
work that touches machine-specific state (paths, keys, launchd jobs, containers, mounted
volumes), or reporting that something was installed or changed here. More than one machine runs
this setup; a session that does not name its host cannot be placed.

### Glossary first — resolve the shorthand before acting

The **Glossary** section below maps the user's shorthand to the concrete thing: which repo,
which skill, which command, which path. When a request uses a term that appears there, follow
the glossary instead of guessing or searching. If a term is clearly glossary material and is
missing, say so and offer to add it — the glossary is meant to grow.

### Naming — one scheme

| Marker | Kind |
|---|---|
| `a_sk_*` | on-demand skill |
| `a_r_*` / `a_r_l_*` | routine (scheduled/unattended; `l_` = local-only) |
| `a_sag_*` | subagent |
| `a_c_*` | user-facing command |
| `a_s_*` | helper script |
| `a_g_*` | git command |

The full glossary of markers lives in the devkit's `CLAUDE.md`. Do not invent a second scheme.

### Searches run on the cheap tier, not on this model

A plain "go find it" ask is retrieval, and retrieval does not need the session's model. Delegate it
to **`a_sag_searcher`** (haiku) instead of searching yourself, automatically, without being asked
and without offering it as an option first. This covers the everyday phrasing: "search this",
"search for X", "find where Y is", "which file has Z", "grep for ...", "where is the config for
...", "look up X", "is X installed", "does this repo use ...".

| The ask | Who does it |
|---|---|
| Single known target: a file you already have the path to, one grep whose answer you need in the next step | do it inline, spawning an agent costs more |
| Unknown location, several files, fan-out, "find/search/where is" | `a_sag_searcher` on haiku |
| Retrieval plus judgment: trace behavior across layers, explain WHY, reconcile sources that disagree | `a_sag_searcher` with `model: sonnet` |
| Sessions, Confluence, Jira, deep web research | the dedicated finder: `a_sag_claude_session_finder`, `a_sag_confluence_finder`, `a_sag_jira`, `a_sag_crawler` |

If it returns `ESCALATE: sonnet`, re-spawn it on sonnet with its partial findings rather than
finishing the search yourself. Relay its answer; do not re-run the search to check it.

### Finishing a change — push by default, never push unverified

After committing, push. Do not leave finished work sitting unpushed, and do not end a turn by
handing over a `git push` command. **A shared branch is not a reason to stop** — `staging`,
`develop`, `release/*`, `story/*` are all pushable; only the repository's default branch is not.

**The exception: if the change could not be verified, do not push.** Say what is unverified and
why, and let the user decide. Verified means the project's own gates actually ran and passed — a
skipped suite, a module that would not compile, or a check blocked by a stale credential is a gap,
not a pass.

Full policy, including the other hard gates: `agentic-devkit/rules/commit-and-push.md`. Change it
there, not here.

### Knowledge placement — where a new fact goes

Project-specific guidance belongs **in that project's repo** (`CLAUDE.md`, `.claude/agents/`,
`.claude/skills/`) so it travels with the checkout. Never write it to
`~/.claude/projects/<project>/memory/` — that is one machine only and divorces the decision from
the code it governs.

Anything cross-project, most specific wins:

| What it is | Where it goes |
|---|---|
| A fact about a project, person, or past decision | the brain |
| A term whose meaning implies an action | the glossary |
| A reusable procedure | a skill or agent in a devkit repo |
| A one-line always-on rule | a rules source file, then rebuild |
| Anything else | nowhere. Session-only, let it go. |

`a_sk_teach_claude` makes this call and writes the result in the right place. Prefer it over
deciding by hand.

## This machine is managed

Managed skills and agents in `~/.claude/`, `~/.agents/skills`, `~/.codex/agents`, and
`~/.gemini/` come from a git-backed devkit. Edit the canonical repo source, never a provider
copy or generated adapter. Re-run the installer to refresh links and provider-native files.

This rules file is **generated**. The region between the `agentic-devkit: managed memory`
markers is composed from source files by `a_c_agent_memory build`. Editing inside the region
works until the next build, then it is gone. Edit the source listed at the top of the region,
then run `a_c_agent_memory build`. Anything outside the markers is hand-written and is never
touched by the tooling.

### Identity — always say which machine you are on

The machine's name and role are in the **Machine** section below. Say that name whenever the
host is even slightly in question: asked who or where you are, asked what you can see, starting
work that touches machine-specific state (paths, keys, launchd jobs, containers, mounted
volumes), or reporting that something was installed or changed here. More than one machine runs
this setup; a session that does not name its host cannot be placed.

**The name is read, never derived.** It is `MACHINE_NAME` in the machine's own config, and the
Machine section below is the file that name selected. Do not build a name out of the hostname,
and do not copy the pattern of another machine's name: a naming convention describes names that
were chosen, it is not a formula for generating one. If no machine file loaded, say the name is
not configured here and ask. A confidently invented machine name is worse than no name, because
it looks like an answer.

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

The full glossary of markers lives in the devkit's `AGENTS.md`. Do not invent a second scheme.

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

### Task work gets its own session, not a subagent

The section above sends retrieval to a subagent. This one is its other half, and the two are read
together: **what decides the answer is what the work produces, not how big it is.**

| The work produces | Who does it |
|---|---|
| An answer needed to keep working: a search, a lookup, a read-only verification, a bounded exploration | a subagent (see above) |
| **A change in a repo** — writes code, commits, ends in a PR or a push | **its own session**, started with `a_c_task_start -c -z <session>`, one per lane |

The test is one question: **does this end in a diff someone reviews?** If yes it is a task lane, and
a task lane gets a real session in a tab. Never an in-process subagent, however well-scoped the
brief is.

Three things a subagent cannot give a task lane, and all three are the point of handing work over:
it is visible while it runs, it can be steered mid-flight, and it outlives the session that started
it. A subagent has none of those — the work happens where nobody can see it and arrives only as a
final report.

"Hand this over", "run these in parallel", and "keep an eye on them" are asking for sessions. Read
them that way even when the work looks like something a subagent could carry.

### A tab is `a_c_zellij_tab`, never hand-rolled zellij

Anything that wants a tab calls **`a_c_zellij_tab`**, including "open a new tab", "give it its own
tab", and every task-lane handover above. `a_c_task_start` and its fronts already do.

```
a_c_zellij_tab <session> <tab> --cwd <dir> --cmd '<command>'
```

Driving `zellij action` by hand fails two ways that look like the tool is broken rather than the
caller. `write-chars` types into the pane that is **already focused**, not the tab just created, so
the keystrokes land in whatever the user was looking at. And a bare `--layout` tab is not wrapped in
the session's default template, so a layout holding only the command pane opens with no tab-bar and
no status-bar: the tab appears unclickable and the other tabs vanish. The script bakes both plugin
panes in and marks the command pane `focus=true`, and it also handles idempotent re-focus, an EXITED
session, verifying the tab exists because `new-tab` exits 0 regardless, and the launcher's
PATH/TERM/VIRTUAL_ENV. `a_c_zellij_fix` repairs a session already damaged this way.

### Devkit friction goes to the devkit's issues, not into a private note

When the tooling itself is the problem, a skill that misfired, an agent that returned the wrong
shape, a helper the docs name that does not exist, a default that cost you time, **report it** with
`a_sk_report_improvement`. It files one GitHub issue on the devkit repository, and
`a_r_l_improve_from_issues` works that backlog later.

This is the default destination, from every machine. Several machines run this setup, so a private
workaround fixes it for one person and leaves it broken for the rest, and nobody ever learns the
same gap was hit three times. Fix it yourself instead when the fix is small and you are already in
the repo: a commit beats an issue.

The tracker is **public**. Describe the problem in generic terms and never paste employer, client,
project, host, ticket or colleague names into it. If it cannot be described without them, do not
file it, and say why.

### Knowledge placement — where a new fact goes

Project-specific guidance belongs **in that project's repo**. `AGENTS.md` is canonical;
provider bridge files such as `CLAUDE.md` and `GEMINI.md` should only import it. Provider-specific
skills or agents may stay in their native project directories. Never put durable project facts
in a provider's machine-local session memory, where they cannot travel with the repository.

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

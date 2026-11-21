## This machine is managed

Managed skills and agents in `~/.claude/`, `~/.agents/skills`, `~/.codex/agents`, and
`~/.gemini/` come from a git-backed devkit. Edit the canonical repo source, never a provider
copy or generated adapter, and re-run the installer to refresh links.

This guidance is **generated** by `a_c_agent_memory build` from source files, between the
`agentic-devkit: managed memory` markers. An edit inside the markers is lost on the next build:
edit the source listed at the top of the region, then rebuild. Text outside the markers is
hand-written and never touched.

### Glossary first — resolve the shorthand before acting

The **Glossary** section below maps the user's shorthand to the concrete repo, skill, command, or
path. When a request uses a term listed there, follow it instead of guessing or searching. If a
term is clearly glossary material and is missing, say so and offer to add it.

### Naming — one scheme

| Marker | Kind |
|---|---|
| `a_sk_*` | on-demand skill |
| `a_r_*` / `a_r_l_*` | routine (scheduled/unattended; `l_` = local-only) |
| `a_sag_*` | subagent |
| `a_c_*` | user-facing command |
| `a_s_*` | helper script |
| `a_g_*` | git command |

The full list lives in the devkit's `AGENTS.md`. Do not invent a second scheme.

### Searches run on the cheap tier, not on this model

A plain "go find it" ask is retrieval. Delegate it to **`a_sag_searcher`** (haiku) automatically,
without asking first: "search for X", "find where Y is", "which file has Z", "grep for ...",
"where is the config for ...", "is X installed", "does this repo use ...".

| The ask | Who does it |
|---|---|
| Single known target: a file you have the path to, one grep you need for the next step | inline, an agent costs more |
| Unknown location, several files, fan-out | `a_sag_searcher` on haiku |
| Retrieval plus judgment: trace behavior across layers, explain why, reconcile sources | `a_sag_searcher` with `model: sonnet` |
| Sessions, Confluence, Jira, deep web research | `a_sag_claude_session_finder`, `a_sag_confluence_finder`, `a_sag_jira`, `a_sag_crawler` |
| Reading Slack | `a_sag_slack_reader` (read-only). Posting or drafting is `a_sag_slack_writer`, which drafts unless told to send |

If it returns `ESCALATE: sonnet`, re-spawn it on sonnet with its partial findings. Relay its answer;
do not re-run the search to check it.

**Never spawn a read-only agent with worktree isolation.** Searchers, finders, readers and reviewers
change nothing, so they gain nothing from a worktree, and the spawn fails outright when the working
directory is not a git repo ("Cannot create agent worktree: not in a git repository"). If any agent
spawn fails on that error, re-send it once without `isolation`. Never retry a failed spawn
unchanged: the same call gives the same error.

### Task work gets its own session, not a subagent

The test is one question: **does this end in a diff someone reviews?** If yes, it is a task lane
and gets its own session in a tab, started with `a_c_task_start -c -z <session>`, one per lane.
Never an in-process subagent: a session is visible while it runs, can be steered, and outlives
the session that started it. Subagents are for answers you need to keep working.

"Hand this over", "run these in parallel", and "keep an eye on them" are asking for sessions.

A session already busy with something else (a release, a bug report, other lanes) that finds new
work ending in its own PR does not branch and code in place. It writes a brief with what it found
(cause, call sites, traps, how to verify), launches `a_c_task_start -c -z <session> --task-file
<brief>`, then supervises: answers questions, checks reports, relays results.

- **One lane at a time**, unless the user asks for several.
- **Only for a real task.** A one-line fix, a comment reply, or a follow-up commit on a branch
  this session already owns is done directly.

### Messaging another session when its name does not resolve

Some sessions never register their name, so `SendMessage` fails with "No agent named ... is
reachable" while the session is alive. Do not conclude it is gone: run `a_s_session_address
<name>` and send to the `uds:` address it prints (`--list` shows every live session). When you
start a session that should report back, put your own address in its brief
(`uds:$CLAUDE_CODE_MESSAGING_SOCKET`). Reply to a received message at its `from=` address.

### A tab is `a_c_zellij_tab`, never hand-rolled zellij

Anything that wants a tab calls `a_c_zellij_tab <session> <tab> --cwd <dir> --cmd '<command>'`.
Raw `zellij action` types into whichever pane is focused and opens tabs without the tab-bar and
status-bar. `a_c_zellij_fix` repairs a session already damaged that way.

### Devkit friction goes to the devkit's issues, not into a private note

When the tooling itself is the problem (a skill that misfired, an agent with the wrong output, a
helper the docs name that does not exist), file it with `a_sk_report_improvement`;
`a_r_l_improve_from_issues` works that backlog. If the fix is small and you are already in the
repo, fix it instead: a commit beats an issue. The tracker is **public**: describe the problem
generically, never with employer, client, project, host, ticket or colleague names. If it cannot
be described without them, do not file it, and say why.

### A status is verified, or it says "not confirmed"

Any claim about the state of something (deployed, merged, running, passing, done, owned) is
checked against its system of record right before you say it, and the answer says where. A check
from earlier in the session, a brief, or a peer's report is stale once time or work has passed:
run it again yourself before repeating it. What was not
checked is written as **"not confirmed"**, never as "not yet" or "not deployed". A merge, a tag, a
branch containing the commit, or a green CI or deploy job only suggests the state. Before a status
reaches other people, re-check every negative claim: a wrong "not done" reads as an accusation.

**A peer's finding is a lead, not a fact.** Check which branch, repo or system another session or
subagent actually looked at before repeating it. "Not on `development`" is not "not done": check
open PRs and release branches first.

**"Is it done" is judged against the ticket, not the brief.** When the work has a ticket or
issue, read its own Done when list, its Out of scope section and its latest comments before
answering. A session brief, another session's goal, or your own research can describe more than
the ticket asks for, and that extra is not a reason to say "not done". When there is no ticket,
judge against what the user actually asked for.

### Before sending a value to more places, find who reads it

When a value (a header, an id, a field) is reported missing from some calls, first search the
receiving side for it. If nothing consumes it there, the answer is "by design", not a sweep and a
PR.

### Knowledge placement — where a new fact goes

Project-specific guidance belongs **in that project's repo**: `AGENTS.md` is canonical, and
`CLAUDE.md` / `GEMINI.md` only import it. Never put durable project facts in a provider's
machine-local session memory. Anything cross-project, most specific wins:

| What it is | Where it goes |
|---|---|
| A fact about a project, person, or past decision | the brain |
| A term whose meaning implies an action | the glossary |
| A reusable procedure | a skill or agent in a devkit repo |
| A one-line always-on rule | a rules source file, then rebuild |
| Anything else | nowhere, it is session-only |

`a_sk_teach_claude` makes this call and writes it in the right place. Prefer it.

### Use full links

When a reply refers to a pull request, issue, commit, branch, CI run, ticket or web page, give
its full clickable URL rather than only a short reference such as `#123` or `owner/repo#123`.
A short reference can follow the URL, but should not replace it.

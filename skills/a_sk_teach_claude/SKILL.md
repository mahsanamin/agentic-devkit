---
name: a_sk_teach_claude
providers: claude
description: Make the setup self-learning by recording what this session taught you into the right layer, permanently. Takes a correction, a new fact, a stated preference, or a decision, works out whether it belongs in the private brain (knowledge), the global CLAUDE.md (a one-line always-on rule), or a skill/agent in a devkit repo (a reusable procedure), then writes it there, dated, and commits. Deliberately drops what is not worth keeping so the rules file stops growing. Use for "remember this", "don't make that mistake again", "add this to my brain", "record what we learned", "save this preference", "update the glossary with this", "capture this decision", or at the end of a session where you were corrected. Also run it after any session that discovered a repo, epic, owner, or convention Claude did not know.
---

# a_sk_teach_claude — write down what was learned, in the right place

Claude forgets everything at the end of a session. This skill is how a fact survives it. One
decision per item: **which layer owns this?** Then write it, date it, commit it.

The layers and the routing rule are in `docs/managed-claude.md`. Read it. This skill is the
procedure for one item; that doc is the model.

## What counts as learnable

Anything that would have made this session faster if Claude had known it at the start:

- **A correction.** "No, the ticket goes under epic X, not Y." "That service was renamed."
- **A fact about the work.** A repo-to-tracker mapping, who owns a service, why a design went
  the way it did.
- **A stated preference.** How the user wants messages written, PRs sized, tests structured.
- **A gotcha.** A tool that fails a specific way, and the workaround.
- **A procedure** the user walked you through step by step.

## What does not count (this is the important half)

Be strict. A rules file that grows every session stops being read, and a brain full of noise is
worse than a small one.

Drop it if it is:

- **Already recorded** somewhere. Search first, always.
- **Derivable from the repo.** Code structure, file locations, what a function does, git
  history. Claude can read those. Writing them down just creates something to go stale.
- **True only today.** "The build is broken", "PR 412 is waiting on review". State, not
  knowledge.
- **A one-off.** A thing done once, unlikely to recur.
- **Inferred, not stated.** If you guessed it rather than being told, ask before writing it.

When unsure, ask. One question is cheaper than a wrong permanent fact.

## Step 1 — gather the candidates

If the user pointed at something specific, that is the candidate; skip ahead.

Otherwise scan the session for: corrections the user made, questions you had to ask that a
record would have answered, and anything the user stated as a standing preference. List them and
show the list. Do not silently pick.

## Step 2 — search before writing

For each candidate, check whether it already exists:

```bash
grep -rin "<key term>" ~/.claude/CLAUDE.md <brain-path> <devkit-repos>/skills <devkit-repos>/agents 2>/dev/null
```

Three outcomes:

- **Not found** -> new entry (step 3).
- **Found, and it agrees** -> nothing to do. Say so; do not write a second copy. Duplicated facts
  drift and then contradict each other.
- **Found, and it disagrees** -> this is the valuable case. Something is now wrong. **Update in
  place**, do not append. Show the user the old text and the new, and confirm which is current
  before overwriting.

## Step 3 — route it

Run the decision from `docs/managed-claude.md`:

| The item is | Goes to | Form |
|---|---|---|
| A fact about a project, person, decision, or mapping | **private brain** | a line or short section in the right folder |
| A term of the user's whose meaning implies an action | **`<overlay>/machine/glossary.md`** | one row: term, what it is, what to do |
| A fact about *this machine* (role, what runs here, a gotcha) | **`<overlay>/machine/<A_MACHINE_NAME>.md`** | a line under the right heading |
| A one-line behavior, personal | **`<overlay>/machine/rules.md`** | one or two lines under an existing heading |
| A one-line behavior, generic to any machine | **`agentic-devkit/memory/core-rules.md`** | one or two lines under an existing heading |
| A multi-step procedure, work-specific | **org overlay** | a new or edited skill/agent |
| A multi-step procedure, generic | **agentic-devkit** | a new or edited skill/agent |
| Anything else | **nowhere** | say you dropped it, and why |

**Never edit `~/.claude/CLAUDE.md` directly.** It is generated from the sources above; the next
`a_c_agent_memory build` overwrites anything written into the managed regions. After writing to
a source, run `a_c_agent_memory build` so the change is live in every configured agent, and say that you did.

**The glossary row is the most under-used option.** If you picked the wrong tool this session
and were corrected, that is not a rule and not a brain fact — it is a missing glossary row.
Prefer it whenever the lesson is "when I say X, you should reach for Y".

Two rules that decide most of the hard cases:

- **Knowledge goes to the brain, not the rules file.** A project list, a key mapping, an owner:
  all brain. The global file gets at most a pointer, and only if one is not already there.
- **A procedure becomes a skill, not a rule.** If it has steps, it is a skill. Skills load only
  when relevant; rules load on every request forever. Never paste a procedure into the global
  file.

## Step 4 — write it

**Into the brain** (most common). Put it in the folder that matches the *question it answers*,
per the brain's own `CLAUDE.md`:

- a name/mapping/epic -> `Glossary/`
- why something is the way it is -> `Decisions/`
- who owns what -> `People/`
- how the user wants work done -> `Conventions/`
- a correction or gotcha -> `Learned/`

Format every entry so it is still readable in a year:

```markdown
## <short title>

**As of 2026-07-28.** <the fact, in one or two plain sentences.>

<Why it matters, or what to do differently, if that is not obvious.>
```

**Use an absolute date, never a relative one.** "Last sprint" is worthless six months on. If a
fact has a known expiry (an epic that will close, a temporary workaround), say so in the entry so
the next reader knows to re-check it.

Write brain files with the tools you normally use for that brain. If the brain is a plain git
repo, edit files directly. If it is served through a notes CLI, use the safe-write path for that
CLI rather than piping markdown through a shell.

**Into a memory source** (`memory/core-rules.md`, `machine/rules.md`, `machine/<name>.md`, or
`machine/glossary.md`). Add to an existing heading; do not create a new one for a single line.
Keep it to one or two lines — a glossary row is exactly one. Before finishing, re-read the
section you touched and check it does not now contradict a line above or below it. Then:

```bash
a_c_agent_memory diff    # confirm only your change moved
a_c_agent_memory build   # make it live in Claude, Codex, and Gemini
```

**Into a skill or agent.** Follow the repo's conventions: `a_sk_<name>` for a skill, `a_r_<name>`
or `a_r_l_<name>` for a routine, `a_sag_<name>` for a subagent, frontmatter `name:` matching the
file or directory, and a `description:` written so the skill actually triggers. Then run
`a_c_skills install <name>` (or `a_c_agents install <name>`) and commit.

## Step 5 — commit

An uncommitted brain entry is a lost brain entry. Commit in whichever repo you wrote to, with
that repo's identity. One commit per session's learnings is fine; the message should say what was
learned, not "update notes".

If the repo has a pre-commit guard (for example one blocking work content from a public repo),
let it run. If it blocks you, the item was routed to the wrong layer. Re-route it, do not bypass
the guard.

## Step 6 — report

Short and concrete:

- What was recorded, where, one line each.
- What was **dropped**, and why. This matters as much as what was kept, because it shows the
  filter is working.
- Anything that contradicted an existing entry, and how it was resolved.
- Which repos were committed, and anything left uncommitted.

## Running it regularly

This works best at the end of a session that involved corrections, and it can be scheduled. If
you schedule it, keep it a review pass: read the recent sessions, propose entries, and let the
user approve before writing. Unattended permanent writes to a memory layer will eventually record
something wrong, and a wrong fact in the brain is worse than a missing one.

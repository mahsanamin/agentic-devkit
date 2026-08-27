# A managed Claude

This is the one canonical description of how a Claude Code setup is organised when
agentic-devkit manages it. The skills that build and repair that setup
(`a_sk_setup_claude`, `a_sk_tame_claude`, `a_sk_teach_claude`) all defer to this
document instead of restating it.

## Managed vs unmanaged

**Unmanaged** is where most people are. `~/.claude/` fills up over months with hand-written
files: a long `CLAUDE.md` nobody re-reads, skills pasted in from a blog post, agents copied
from another machine, rules that contradict each other. Nothing is in git. Nothing survives a
laptop swap. You cannot tell what is still true.

**Managed** means every file Claude loads is a **symlink into a git repo**. `~/.claude/` holds
pointers only. To change behavior you edit a repo and commit. To set up a new machine you clone
and run one installer. To see what changed you read a diff.

The test: *if this laptop died right now, could a new one be identical in ten minutes?* If yes,
it is managed.

## The four layers

Two different things get managed, and mixing them up is the usual mistake.

- **Capability** is what Claude can *do*: skills, subagents, shell commands. It is code.
- **Knowledge** is what Claude *knows* about you: your projects, your decisions, your people,
  your preferences. It is memory.

Capability is reusable and mostly shareable. Knowledge is specific and almost always private.
They live in different repos.

```mermaid
flowchart TD
    GC["~/.claude/CLAUDE.md<br/>always-loaded rules"]
    subgraph cap["Capability (what Claude can do)"]
        CORE["agentic-devkit<br/>generic - public"]
        ORG["org overlay<br/>work-specific - private"]
        PERS["personal overlay<br/>personal-life - private"]
    end
    subgraph know["Knowledge (what Claude knows)"]
        BRAIN["private brain<br/>glossary, decisions, people - private"]
    end
    GC -->|"symlinks + installer"| CORE
    GC -->|"symlinks + installer"| ORG
    GC -->|"symlinks + installer"| PERS
    GC -->|"reads and writes back"| BRAIN
    CORE -->|"installer reused by"| ORG
    CORE -->|"installer reused by"| PERS
    style GC fill:#334155,stroke:#1e293b,color:#ffffff,stroke-width:2px
    style CORE fill:#1d4ed8,stroke:#1e3a8a,color:#ffffff,stroke-width:2px
    style ORG fill:#b45309,stroke:#7c3a06,color:#ffffff,stroke-width:2px
    style PERS fill:#b45309,stroke:#7c3a06,color:#ffffff,stroke-width:2px
    style BRAIN fill:#1f7a3a,stroke:#0f4d24,color:#ffffff,stroke-width:2px
```

| Layer | Repo | Visibility | Holds |
|---|---|---|---|
| Rules | `~/.claude/CLAUDE.md` | **generated** from repo sources | the short, always-loaded rules; points at everything else |
| Core capability | **agentic-devkit** (this repo) | public | generic skills, agents, shell, tools |
| Org capability | your work overlay | private | work-only skills/agents, org profile |
| Personal capability | your personal overlay | private | personal-life skills |
| Knowledge | your **private brain** | private | glossary, decisions, people, conventions, learned corrections |

Only the core is required. Add an overlay when you have something that must not be public. Add
the brain the first time you catch yourself re-explaining the same background to Claude.

### How the overlays work

An overlay is deliberately thin. It does not copy the installer, the shell wiring, or any
generic skill. It has its own `skills/` and `agents/` and an `install.sh` that calls this repo's
`a_c_skills` / `a_c_agents` through `CLAUDE_SKILLS_SRC` / `CLAUDE_AGENTS_SRC`. One installer,
many sources. Install the core first; the overlays fail loudly without it.

### Routing: which repo does a new thing go in?

Most specific wins.

1. Names a work project, service, host, ticket tracker, or internal hostname -> **org overlay**.
2. Personal life or a personal tool, no work content -> **personal overlay**.
3. Everything else -> **agentic-devkit**. This is the default.

If scrubbing the work specifics would leave something useful, put the generic version in the
core and a thin work-specific front in the overlay.

**Guard it.** Put a pre-commit hook on the public repo that greps for your employer's names,
domains, package prefixes, and project code names, and blocks the commit on a hit. A leak into a
public repo is not something you want to discover later.

## The rules file is generated, not hand-written

`~/.claude/CLAUDE.md` loads on **every single request**, and on most machines it is the one file
that is hand-typed and version-controlled nowhere. Skills and agents survive a laptop swap; the
rules do not. That is the last unmanaged thing in an otherwise managed setup.

`a_c_agent_memory` fixes it by composing every provider's native global file from sources that do live in git:

| Block | Source | Layer |
|---|---|---|
| core rules | `agentic-devkit/memory/core-rules.md` | core (public, generic) |
| machine identity | `<overlay>/machine/<A_MACHINE_NAME>.md` | overlay (private) |
| personal rules | `<overlay>/machine/rules.md` | overlay (private) |
| glossary | `<overlay>/machine/glossary.md` | overlay (private) |
| pointers | generated from the configured repo paths | — |

```bash
a_c_agent_memory status   # sources found, regions present, in sync?
a_c_agent_memory diff     # what a build would change
a_c_agent_memory build    # regenerate all native provider files
a_c_agent_memory check    # exit 1 on drift (used by a_c_workflow_doctor)
```

Everything it writes sits between `agentic-devkit: managed memory` markers. **Text outside the
markers is never touched** — adopting an existing hand-written file keeps that file, verbatim,
below the generated region. Three variables in `configs.profile` drive it: `A_MACHINE_NAME`,
`A_AGENT_OVERLAY_DIR`, `A_AGENT_BRAIN_DIR`. With none of them set you still get valid files
from the core rules alone.

### Machine identity

A machine that runs unattended work needs a name it can introduce itself with, a stated role,
and explicit limits on what it may do without being asked. That is `machine/<name>.md` in the
overlay: the name (which need not be the hostname), what lives on the box, which volumes must be
mounted, which git identity to commit as, and what a scheduled routine is allowed to touch.

Name it distinctly. "Which machine am I on" should never be answered by inference.

### Path tokens — because overlay sources are shared

`machine/rules.md` and `machine/glossary.md` are read by **every** machine, but the repos they
talk about sit at a different absolute path on each one. A hardcoded path is therefore correct on
exactly one box, and an `@/abs/path/file.md` import that does not resolve is worse than a missing
rule: it fails silently, so the machine looks configured and quietly runs without that rule.

Write tokens instead. The build expands them per machine:

| Token | Expands to |
|---|---|
| `{{DEVKIT}}` | `$MY_WORKFLOW_DIR` — the public core repo |
| `{{OVERLAY}}` | `$A_AGENT_OVERLAY_DIR` — the private overlay |
| `{{BRAIN}}` | `$A_AGENT_BRAIN_DIR` — the private brain |

```markdown
@{{DEVKIT}}/rules/mdnest.md
```

Better still, in prose: name repos by their `cd_g` / `cd_p` / `cd_w` tier rather than by path, and
keep absolute paths in `machine/<name>.md`, which is the one source that is allowed to be
machine-specific because there is one per machine.

### The glossary

The highest-leverage block. A table of *the user's shorthand* mapped to the concrete thing:
which repo, which skill, which command, which path. It is loaded on every request, so a term in
it is resolved instead of searched for, and the right tool gets picked instead of improvised.

Keep rows to one line and keep it a routing table, not documentation — the long version goes in
the brain with a pointer from the glossary. It grows from corrections: every time the wrong tool
was picked, that is a missing row.

## The private brain

A git repo of plain Markdown holding facts about your work that no code repo records. Name it
whatever you like: `my_private_brain`, `<name>-brain`, `second-brain`. Keep it **private**.

Suggested layout. Only `CLAUDE.md` and `Glossary/` really matter on day one; grow the rest as
you hit the need.

```
my_private_brain/
├── CLAUDE.md         entry point: which folder answers which question. Read first.
├── Glossary/         short name -> repo -> tracker key; the epics/boards in flight
├── Decisions/        why things are the way they are; trade-offs; rejected options
├── People/           who owns what, who to ping, team boundaries
├── Conventions/      how you want work done (review bar, release habits, naming)
├── Learned/          corrections and gotchas captured from past sessions
└── current_work/     notes on whatever is in flight right now
```

Two rules keep it useful:

- **`CLAUDE.md` is the index.** It tells Claude which folder answers which kind of question, so
  a session does not have to guess or read everything.
- **Facts only, and dated.** Write absolute dates, not "last week". A brain full of stale
  relative time is worse than no brain.

Hook it into the global `CLAUDE.md` with a short section naming the path and telling Claude to
read the brain's `CLAUDE.md` first, and to skip silently if the path is missing (unmounted
volume, different machine). Never let a missing brain block a session.

## More than one machine

Once a second machine exists, the overlay and the brain are only shared in theory: a fact helps
the other box after it is **pushed**, and a clone that has not pulled is how two machines end up
disagreeing with each other. `a_c_repo_sync` closes that gap.

```bash
a_c_repo_sync              # pull, commit anything local, push - overlay and brain
a_c_repo_sync -n           # dry run
a_c_repo_sync --pull-only  # take updates, send nothing
a_c_repo_sync <path> ...   # specific repos (default: $A_CLAUDE_OVERLAY_DIR, $A_CLAUDE_BRAIN_DIR)
```

It is intentionally dull, and the guarantees are the point: it never force-pushes, never rewrites
history, and never resolves a conflict — on any conflict it aborts, restores the repo, and tells
you to fix it by hand. It skips a repo that is mid-rebase, detached, upstream-less, or has no git
identity, and one repo failing does not stop the others. When a pull changes anything under
`machine/`, it rebuilds the rules file, because otherwise the machine keeps running yesterday's
rules.

Two things it is not. It is **not** a knowledge-producing routine — it moves that machine's own
commits and nothing else, which is why every machine may run it on a timer even when the fleet
rule is that only one box owns the scheduled routines. And it is **not** a substitute for an
unlocked SSH agent: if every key on the box is passphrase-protected, an unattended run can only
push after a human has unlocked the agent once since boot. The script says so plainly instead of
failing obscurely.

Wire it per machine with whatever that OS uses — a systemd user timer on Linux, a launchd agent
on macOS. Per machine, because it is local plumbing, not shared capability.

## The self-learning loop

The setup improves only if what you learn gets written down in the right place. That is one
decision, made every time:

```mermaid
flowchart TD
    NEW["Something new was learned<br/>(a correction, a fact, a preference)"]
    Q1{"About a specific<br/>project, person,<br/>or past decision?"}
    Q2{"A reusable behavior<br/>Claude should always have?"}
    Q3{"Work-specific?"}
    BRAIN["-> private brain<br/>(knowledge)"]
    RULES["-> global CLAUDE.md<br/>(short rule, always loaded)"]
    ORG["-> org overlay<br/>(skill or agent)"]
    CORE["-> agentic-devkit<br/>(skill or agent)"]
    DROP["-> nowhere.<br/>Session-only. Let it go."]
    NEW --> Q1
    Q1 -->|yes| BRAIN
    Q1 -->|no| Q2
    Q2 -->|"no"| DROP
    Q2 -->|"yes, and it is one line"| RULES
    Q2 -->|"yes, and it is a procedure"| Q3
    Q3 -->|yes| ORG
    Q3 -->|no| CORE
    style BRAIN fill:#1f7a3a,stroke:#0f4d24,color:#ffffff,stroke-width:2px
    style RULES fill:#334155,stroke:#1e293b,color:#ffffff,stroke-width:2px
    style CORE fill:#1d4ed8,stroke:#1e3a8a,color:#ffffff,stroke-width:2px
    style ORG fill:#b45309,stroke:#7c3a06,color:#ffffff,stroke-width:2px
    style DROP fill:#b91c1c,stroke:#7f1414,color:#ffffff,stroke-width:2px
```

The most important box is the red one. Not everything is worth remembering, and a rules file
that grows every session stops being read. `a_sk_teach_claude` runs this decision for you and
writes the result.

## What the three skills do

| Skill | Use it when |
|---|---|
| `a_sk_setup_claude` | Fresh machine, or a working machine that just needs the devkit wired in |
| `a_sk_tame_claude` | `~/.claude` is a mess: hand-written files, broken links, no git behind it |
| `a_sk_teach_claude` | End of a session where something durable was learned |

## Health rules

- `~/.claude/skills/*` and `~/.claude/agents/*` are **symlinks**. A real file or directory there
  is unmanaged and needs a decision: adopt it into a repo, or delete it.
- **No broken links.** A symlink pointing at a moved or deleted repo silently removes a skill.
  Renaming a repo directory breaks every link into it; re-run the installer with `-f` after any
  rename.
- **Edit the repo, never the link.** Editing through a symlink does write to the repo, but it
  leaves the change uncommitted and easy to lose. Open the repo file.
- **The global `CLAUDE.md` stays short.** It is loaded into every session, so it costs you on
  every request. Long material belongs in a repo doc that gets read on demand, pulled in with an
  `@path` import, or in the brain.
- **One fact, one home.** If the same rule appears in two files they will drift. Keep it in one
  place and link.

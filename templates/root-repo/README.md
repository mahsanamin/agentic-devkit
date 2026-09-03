# {{ORG_NAME}} root instructions

**The starting point. One small repo that every AI tool reads first.**

Each AI tool looks for its own instruction file: `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, and more
arrive every few months. Keeping the same rules in all of them means they drift, and then there
are three answers to one question.

So this repo holds one file, [`ROOT.md`](ROOT.md). `AGENTS.md` points at it, and every other tool
file is a one line import of `AGENTS.md`. Fix a rule once, every tool gets it.

The second problem it solves is machines. The layout is the same on each one, the folders are
not, so instructions written with one machine's paths are wrong on the next.
[`root.config`](root.config) holds every path and nothing else does. New machine: change one
value. New company: copy this repo, keep the key names, change the values.

## What is in it

| File | For |
|---|---|
| [`ROOT.md`](ROOT.md) | the root instruction: the rule with no exceptions, where to look things up, the short list |
| [`root.config`](root.config) | every path and remote, keyed by role. Nothing else hardcodes a path |
| `root.local.config` | this machine's overrides. Gitignored, never committed |
| [`rules/boundary.md`](rules/boundary.md) | nothing about the company leaves the company, and the check before an outward push |
| [`rules/conduct.md`](rules/conduct.md) | how to work: base branch, ownership, ticket, worktree, commit, push, messages |
| `AGENTS.md` | the canonical stub: read `ROOT.md`. `CLAUDE.md` and `GEMINI.md` import `AGENTS.md` |

It holds no company facts and no skills. Those go in the brain and the toolkit repos it points
at.

## First things to do

1. Set the repo tiers in `root.config` to where your repos actually live.
2. Create `root.local.config` with at least `MACHINE_NAME`.
3. Add the repos you have: the company brain, your overlays, the framework. Leave the rest empty.
4. Read [`rules/boundary.md`](rules/boundary.md) and put your approved agents in it.
5. Wire the machine: see `agentic-devkit/docs/root-repo.md`, or run its setup skill.

## Keeping it lean

Only three things belong here: a rule that has no exceptions everywhere, a pointer to the repo
that owns a class of question, and a path. A company fact goes in the brain. A skill, an agent or
a script goes in a toolkit repo. If a line names a command, it is not a root line.

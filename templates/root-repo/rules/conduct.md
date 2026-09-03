# How to work

The tool side of conduct: git, tickets, and messages. Short on purpose.

The org side, what you may change and what you hand to another team, lives in the company brain
at `rules/agent-conduct.md` (`ORG_BRAIN_DIR`). Read that too. This file does not repeat it.

## Before you read code

**Fetch, then read the base branch.** A local clone is a snapshot of whenever it was last pulled.
Reading a stale one does not fail loudly, it gives a coherent and confidently wrong answer. This
applies to read only analysis as well.

## Before you change code

**Push access is not ownership.** The org grants push on almost every company repo, so a wrong
repo push succeeds and policy is the only barrier. Establish that the repo is yours to change
first. The company brain has the three cases: yours, shared infrastructure, another team's app.

**Ticket first.** Create it, under the right epic, before the first edit. Name the branch and the
worktree from the ticket key. A random name loses the trail.

**Work in a worktree, never branch in the main checkout.** The main clone stays on its default
branch and stays clean, for reading, orchestration, and ticket or PR work. Editing and committing
happen in a worktree for that ticket.

## Committing and pushing

- **Never commit or push on `main`, `master`, or a default branch.** The one exception is a
  personal single maintainer repo where that is the norm.
- **Finish the work, verify it, then commit and push without asking.** Any branch that is not the
  default branch is pushable, including a shared integration branch. Shared is not a reason to
  stop.
- **Could not verify it? Do not push.** Verified means the project's own gates ran and passed. A
  skipped suite, a module that would not compile, or a check blocked by a stale credential is a
  gap, not a pass.
- **Force push is stricter.** Never on a default branch or a shared branch.
- **Merging a PR is the human's call.** Open it, let review and CI land, hand it over.

## Messages that leave your machine

**Never send one on your own initiative:** chat, email, ticket comments, PR comments, anything
another person receives. Write the draft, show it, let the human send it. Composing is welcome,
posting is not yours. The exception is a routine the human invoked that says it posts.

**Volume needs its own approval.** "Create the tickets" authorises the kind of action, not ten of
them. Propose the list first and default to one.

## Data handling

Personal data, names, passport numbers, payment details, bookings, IPs, does not go into prompts,
logs, tickets, or files. No production data in a development environment. See
[`boundary.md`](boundary.md).

## Reporting

Report what actually happened. If tests fail, say so with the output. If a step was skipped, say
that. A green summary line is not evidence a suite ran. Do not present a decision you made alone
as one that was agreed.

## When you learned something

Fix it in the same session. Company wide facts go to the company brain, facts only you need go to
your private brain, a reusable procedure goes to a toolkit repo.

# Root instructions: {{ORG_NAME}}

The starting point for any AI tool doing work for this company. **Read this file, then open the
one file it sends you to.** Do not read the whole repo.

This file holds no company facts and no machine paths. It holds the rules that have no
exceptions, and the pointers to the repos that hold everything else.

**Paths live in [`root.config`](root.config), nowhere else.** Read it to learn where each repo
below sits on this machine. An empty value means that repo is not here. That is normal: skip it.

## 1. The rule with no exceptions

**Nothing about the company leaves the company.**

Before you paste, publish, push, or share anything outward, read
[`rules/boundary.md`](rules/boundary.md). It says what counts as company content, where it may
never go, and the check to run first.

If you cannot tell whether something is company content, treat it as company content, and ask.

## 2. Where to look things up

| Your question | Go to |
|---|---|
| What does this word or codename mean? Which repo owns it? Which team? Which service serves this URL? Where are the logs? | `ORG_BRAIN_DIR`, its entry file, which routes you to exactly one file |
| What may I change, and what do I hand to another team? | `ORG_BRAIN_DIR` -> `rules/agent-conduct.md` |
| How do I work: ticket, worktree, commit, push, PR, messages? | [`rules/conduct.md`](rules/conduct.md) |
| How does THIS repo want work done? | that repo's own `AGENTS.md` |
| What skills, agents, and helpers exist on this machine? | `DEVKIT_DIR`, then the overlays `ORG_DEVKIT_DIR` and `PRIVATE_DEVKIT_DIR` |
| What am I working on, and what do I call it? | `PRIVATE_BRAIN_DIR` |

One hop. If the file the table names does not answer it, that file names the repo that does. Do
not go crawling through repos.

## 3. The repos this points to

Roles, not names. The name and path for each role are in [`root.config`](root.config).

| Role key | Holds | Layer |
|---|---|---|
| `ORG_BRAIN_DIR` | company knowledge everyone needs: glossary, repo and team map, routing, org rules | knowledge |
| `PRIVATE_BRAIN_DIR` | my own layer: my short names, active epics, decisions, current work | knowledge |
| `DEVKIT_DIR` | the generic toolkit: reusable skills, agents, scripts | capability |
| `ORG_DEVKIT_DIR` | the company overlay on that toolkit | capability |
| `PRIVATE_DEVKIT_DIR` | the private overlay on that toolkit: my own skills and rules | capability |
| `AGENT_FRAMEWORK_DIR` | the per repo workflow installed into a project | capability |

Knowledge is what we know, capability is what an agent can do. Do not put a fact in a toolkit
repo, and do not put a skill in a brain.

A role marked `*_NO_ORG_CONTENT="true"` in `root.config` must never receive company content, not
in the diff and not in the commit message. That flag, not `*_IS_PUBLIC`, is what triggers the
check: a private repo can still be the wrong home, because it is shared or mirrored elsewhere.

## 4. The short list

Hard rules. The full text is in [`rules/conduct.md`](rules/conduct.md).

1. Fetch and read the latest base branch before your first grep. A stale clone gives a confident
   wrong answer and never fails loudly.
2. Push access is not ownership. You can push to almost every company repo. That proves nothing.
3. Ticket first, then a worktree named from the ticket key. Never branch in the main checkout.
4. Never commit or push on `main`, `master`, or a repo's default branch.
5. Never send an outbound message on your own initiative: chat, email, ticket comment, PR
   comment. Draft it and let the human send it.
6. Merging a PR is the human's call.
7. No secrets, no production data, no personal data in prompts, logs, tickets, or files.
8. Report what actually happened. A skipped suite is not a pass.

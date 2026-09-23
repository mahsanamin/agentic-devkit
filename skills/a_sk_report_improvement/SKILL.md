---
name: a_sk_report_improvement
description: Report a devkit improvement, defect, or gap as a GitHub issue on the agentic-devkit repository, so it survives the session and a later triage run can pick it up. Use the moment something in the devkit itself is wrong, missing, confusing, or costs time: a skill that misfires, an agent that returns the wrong shape, a helper that does not exist, a rule that contradicts another, a name in the docs that does not resolve. Say "report an improvement", "file this against the devkit", "this is a devkit bug", "raise an issue for this", or "the devkit should do X". Also runs at the end of a session where you had to work around the tooling.
---

# a_sk_report_improvement, send friction back to the devkit

Friction with the tooling is only useful if it leaves the session it happened in. This skill turns
one piece of friction into one GitHub issue on the devkit repository, where `a_r_l_improve_from_issues`
can pick it up later.

**This is the default destination for devkit friction.** Not the brain, not a local note, not a
sentence in a reply that scrolls away. Anyone running the devkit, on any machine, reports here, which
is the point: the same gap hit by three people becomes one issue with three voices instead of three
private workarounds.

## What belongs here, and what does not

| The thing | Where it goes |
|---|---|
| A devkit skill, agent, script, or rule is wrong, missing, or confusing | **here**, an issue |
| A devkit name in the docs that resolves to nothing | **here**, an issue |
| A devkit default that cost you time | **here**, an issue |
| A fact about a project, person, or decision | the private brain, via `a_sk_teach_claude` |
| A preference about how the user wants you to work | a rules source, via `a_sk_teach_claude` |
| A defect in a project that merely uses the devkit | that project's own tracker |
| Something you can just fix here, now, in one small commit | fix it, no issue |

That last row matters. An issue is for what you are **not** fixing in this session. A PR beats an
issue every time; file an issue when you lack the context, the authority, or the session budget.

## Step 1, decide it is real

Answer these before writing anything. If you cannot, there is no issue yet.

1. **What did you expect, and what happened?** Both, concretely.
2. **Can someone else reproduce it?** Name the skill, agent, script, or file, and the command.
3. **Would it happen to another user of the devkit?** If it is only true on this machine, it is a
   machine-config problem, not a devkit issue.

## Step 2, do not file a duplicate

The same friction hits many people, which is the value here and also the failure mode. Search before
you write:

```bash
repo="${A_DEVKIT_ISSUE_REPO:-mahsanamin/agentic-devkit}"
gh issue list --repo "$repo" --state all --limit 50 --search "<two or three distinctive words>"
```

Found one that is the same thing? **Comment on it** with what you saw, and stop. A second voice on
an existing issue is worth more than a second issue.

## Step 3, scrub it, because this tracker is public

**The devkit repository is public. Everything you file is world-readable, permanently, and an edit
does not remove it from the API history.** The improvement is about the devkit, so it never needs
anything private to be understood. Before writing the body, remove:

- Employer, client, team, product, and service names, and any internal codename.
- Private repository names and URLs, internal hostnames, ticket keys, Slack channels.
- Absolute paths that carry a person's name or an organization's layout.
- Real log lines, payloads, customer data, credentials, and tokens.
- Colleagues' names. Say "a reviewer", "a teammate".

Generalize instead of redacting. "In a Spring Boot service with a multi-module Gradle build" tells a
maintainer everything that matters and names nobody.

**If you cannot describe the problem without private content, do not file it.** Say so, record it
locally instead, and tell the user why. A public issue is not worth a leak, and this gate is never
overridden by a user asking you to hurry.

## Step 4, write it so a cold reader can act

The reader is you, months later, with none of this context. Title is one specific line, naming the
artifact:

```
a_g_worktree_list: no companion script, so it cannot run from an agent shell
```

Not "worktree helpers are broken". Body, four short sections, plain sentences:

```markdown
**What happened**
<the behaviour, the command, the artifact by name>

**What I expected**
<the behaviour that would have been correct>

**Why it matters**
<who hits this and what it costs them, one or two lines>

**Idea (optional)**
<a fix if you have one; say plainly if you do not>
```

No transcripts, no stack dumps longer than the few lines that carry the signal, no version history.

## Step 5, file it

```bash
repo="${A_DEVKIT_ISSUE_REPO:-mahsanamin/agentic-devkit}"
gh issue create --repo "$repo" \
  --title "<title>" \
  --body-file <path-to-the-body-you-wrote> \
  --label bug          # or --label enhancement for a gap or an idea
```

Use `bug` when something is broken and `enhancement` when something is missing. Those two exist on
every GitHub repository from the day it is created, so this works on a fork with no setup. Any other
label must already exist on the repo: a label `gh` has to invent is noise, and `gh issue create`
fails outright on an unknown one, which loses the report you just wrote.

A fork or a private mirror sets `A_DEVKIT_ISSUE_REPO` to its own slug; everyone else gets the
upstream default and no configuration.

Rules for this step:

- **Show the user the exact title and body, and get a yes, before the first `gh issue create` of a
  session.** Filing is outward-facing and public. Once they have approved the shape, further issues
  in the same session can go without asking again.
- **Say which account will post it**, from `gh auth status`, in that same confirmation. An issue
  carries its author forever, and the account `gh` happens to be logged into is often not the one
  the user would choose to associate with a public repository. This costs one line and prevents a
  mistake that cannot be undone by editing the issue.
- If `gh` is missing, unauthenticated, or the network is down, **do not lose the report**: write the
  body to `~/.claude/devkit-improvements/<date>-<slug>.md`, tell the user it is queued, and move on.
  A later run of this skill files anything queued there and deletes what it filed.

## Step 6, tell the user what you filed

One line, with the URL. Do not restate the body they just approved.

## What this is not

It is not a place to think out loud. One issue is one problem. Three problems noticed in one session
are three issues, or one issue if they are three faces of a single cause, and deciding which is your
job, not the reader's.

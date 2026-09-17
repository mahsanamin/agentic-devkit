---
name: a_r_l_improve_from_issues
description: Work the devkit's open improvement issues in one pass, in an isolated worktree, and close what ships. This is the consuming half of a_sk_report_improvement: that skill files friction as GitHub issues from wherever it was hit, this routine turns a batch of them into actual changes. Use when asked to triage the devkit backlog, improve the devkit from its issues, pick up reported improvements, do the devkit improvement round, or when a scheduled improvement run fires. Parameterized: pass limit (how many issues), label (default improvement), and mode (apply or dry-run). Triggers without the exact name: "go through the devkit issues", "what have people reported", "fix the reported improvements", "run the improvement round".
---

# a_r_l_improve_from_issues, turn reported friction into changes

`a_sk_report_improvement` files friction as issues from every machine running the devkit. Nothing
improves until someone works them. This routine is that session, run as one batch so related reports
are fixed together rather than one at a time by three people who each see a third of the picture.

**Read the whole batch before editing anything.** That is the point of batching: two issues that look
separate are often one cause, and fixing them independently produces two half-fixes that disagree.

## Step 1, pull the batch

```bash
repo="${A_DEVKIT_ISSUE_REPO:-mahsanamin/agentic-devkit}"
gh issue list --repo "$repo" --state open --label "${label:-improvement}" \
  --limit "${limit:-20}" --json number,title,body,labels,comments,createdAt,url \
  > /tmp/devkit-issues.json
jq -r '.[] | "#\(.number)  \(.title)"' /tmp/devkit-issues.json
```

Redirect to a file and read the file. Do not print twenty issue bodies into the session.

Nothing open means nothing to do. Say so and stop; that is a clean result, not a failure.

## Step 2, group by cause, not by issue

Read every body, then write a short grouping: which issues share one underlying cause, which are
genuinely separate, and which are already fixed.

Four outcomes per issue, decided here and not revisited later:

| Outcome | What you do |
|---|---|
| **Fix** | It is real, it is the devkit's, and you can fix it in this pass |
| **Already fixed** | The behaviour it reports is gone. Verify against the current code, then close with the commit that fixed it |
| **Not the devkit's** | It is a machine-config or project problem. Close with a one-line reason and where it belongs |
| **Needs a decision** | It is real but the fix is a judgement the user owns. Leave open, comment with the options, and surface it in the report |

**Check for contradictions before you edit a single file.** Two issues can each be right and still
ask for opposite things, and the devkit is consumed by several machines, so a contradictory change
has outsized reach. On a conflict: stop, put both sides in front of the user, ask which wins, and
only then apply.

## Step 3, work in a worktree

Never work in the main checkout.

```bash
bash "${AGENTIC_DEVKIT_DIR:-$HOME/agentic-devkit}"/scripts/a_g_worktree_init improve/issues-$(date +%Y%m%d)
```

Fix one group at a time. One commit per group, and the commit message names the issues it closes.
A group that turns out to be bigger than this pass stays open; do not half-fix it.

## Step 4, verify before claiming anything

Every changed shell script gets `bash -n`, and every script with a case suite gets its suite run. A
change to a skill or agent body gets read back in full: prose has no compiler, so re-reading it is
the only check there is.

Never report a suite as passing that you did not run, and never describe a skill edit as verified
because the file saved.

## Step 5, land it the way this repo lands work

Read the repository's own `AGENTS.md` and follow what it says. This repository takes small
maintenance commits **directly on `main`**, so this routine commits and pushes there rather than
opening a PR for a batch of skill edits. A fork whose `AGENTS.md` says otherwise gets a branch and a
PR instead. When neither is stated, open a PR: that is the reversible choice.

Attribution follows the repository's rule, which here means **no tool or assistant trailer**.

## Step 6, close what shipped

Closing is part of the work, not an afterthought. An issue that was fixed and left open gets
re-reported by the next person who hits it.

```bash
gh issue close <n> --repo "$repo" --comment "Fixed in <sha>. <one line saying what changed>"
```

For an issue left open because it needs a decision, comment with the options and say plainly that it
is waiting on a human. Do not close it to tidy the list.

## Step 7, report

Print a short table: issue, outcome, and the commit or the reason. Then the two things the user
actually has to act on:

- Anything left open that is waiting on their decision, one line each.
- Anything you could not verify, and why.

Nothing else. They can read the diff.

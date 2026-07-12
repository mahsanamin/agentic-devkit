---
name: a_sk_pr
description: Open a GitHub pull request for the current branch, filling the project's PR template properly. Pushes the branch if needed, fills the template body from the actual changes, picks the correct base branch, and creates the PR (respecting the repo's permission posture). Say "a_sk_pr" or "pr" when ready to open a PR. Generic and project-agnostic — imported from an upstream framework and de-coupled from it.
---

# a_sk_pr — open a pull request

An on-demand skill to open a clean PR for the current branch. It delegates the title + body drafting to the `a_sag_pr_writer` agent and keeps the git/gh actions here. No task-flow / config-file coupling.

## When to use
- Your branch is ready for review and you want a well-formed PR.
- Triggers: "pr", "create pr", "a_sk_pr", "open a pull request".

## Flow
1. **Confirm readiness.** The branch has committed work, is not a protected branch, and builds/tests are green (or say what's outstanding). `git status` clean or intentionally so.
2. **Determine the base branch.** Default to the repo's default branch (`main`/`master`) unless the branch was cut from a story/integration branch — then target that. State the base you'll use.
3. **Push the branch** to origin (`git push -u origin <branch>`) if it isn't already, per the permission posture (see step 5).
4. **Fill the template.** Find the project's PR template (`.github/PULL_REQUEST_TEMPLATE.md` or `.github/PULL_REQUEST_TEMPLATE/*`). Invoke the **`a_sag_pr_writer`** agent with the diff + template + any ticket context; it returns the title and the filled body (it does not run git/gh). If there's no template, produce a concise Summary / Changes / Testing body.
5. **Create the PR** per the repo's permission posture:
   - Default (`ask`): show the title + body + base, get approval, then `gh pr create --base <base> --title … --body …`.
   - Autonomous (`git push` / `gh pr create` already in `.claude/settings.json` `allow`): narrate *"Creating PR against <base>: <title>"* and proceed, only when genuinely PR-ready. Don't ask redundantly.
6. **Never force-push.** Report the PR URL.

## Done-when
A PR exists against the correct base with a complete, template-filled body and a clear title; the branch is pushed; force-push was never used. Report the PR URL.

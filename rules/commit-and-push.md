# Committing and pushing (canonical)

How to finish a piece of work. Imported into global `~/.claude/CLAUDE.md`. If a rule changes,
change it here, not in the machine's copy.

## The default is: commit AND push, without asking

**As of 2026-08-07.** Finish the work, verify the build and tests, commit, push. Do not ask "want
me to commit?", do not stop at "nothing pushed yet", do not end a turn by handing over a
`! git push origin <branch>` command. The base-harness default of "commit or push only when the
user asks" does not apply here; asking every time is friction on a workflow already opted into.

**Push wherever a push is allowed, and "allowed" means one thing only: the branch is not the
repository's default branch.** Nothing else narrows it.

- A shared integration branch is pushable. `staging`, `develop`, `release/*`, `story/*`, an epic
  branch, a branch other people also commit to: all pushable. **Being shared is not a reason to
  stop.**
- The older wording said "pushing a feature branch is pre-authorized". Read that as "any branch
  that is not the default branch". It was never meant to exclude integration branches.
- Recorded 2026-08-21, after resolving a merge conflict on a `staging` branch, committing it, and
  then stopping to hand over the push command because `staging` looked like a shared action. It is
  not. That turn ended with finished, verified work sitting locally for no reason, twice.

**Never report a task as done while a commit sits unpushed.** If one of the hard gates below
genuinely stopped the push, name the gate and give the one-line command. Otherwise the push is part
of "done".

## The hard gates (these, and nothing else, stop a push)

- **Never commit or push on `main` / `master` / the default branch**, except in the personal
  single-maintainer repos where committing on the default branch is the norm. Everywhere else,
  branch or worktree first, always.
- **Merging a PR is the user's call, never automatic.** Open the PR, let CI and review comments
  land, then hand it over.
- **Force-push is gated separately.** `--force`, `-f`, and a `+refspec` push are never allowed
  anywhere. `--force-with-lease` is fine on a personal feature branch, never on the default branch,
  `develop`, `release/*`, or `story/*`. If a guard blocks it, say so and hand over the `! ` command
  rather than stalling silently.
- **Open a PR only when the task was heading there.** Do not create one speculatively.
- **A push that fails on `Permission denied (publickey)` is the user's to run, not mine to debug.**
  A non-interactive shell has no ssh-agent, so once that agent dies mid-session nothing
  authenticates, in ANY repo, including ones already pushed to in the same session. Do not retry
  it, do not test ssh, do not try another remote, do not go looking at key files. Commit as normal,
  then hand over `! cd <repo> && git push origin <branch>` and move on. Recorded 2026-08-21 after
  burning turns diagnosing this.

## Not a gate

None of these justify holding a push:

- The branch is shared, long-lived, or deploys somewhere.
- The commit is a merge commit, or resolves conflicts.
- The change is large, or touches many files.
- A reviewer might want to look first. Review happens on the pushed branch, not on a local one.
- Wanting confirmation that a resolution was right. Say what was decided in the report; a commit is
  revertable, an unpushed branch is invisible.

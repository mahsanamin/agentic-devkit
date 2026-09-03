## Without a root repo

These rules move to the root instruction repo when there is one, so this file is rendered ONLY
when `A_ROOT_DIR` is unset. With a root repo present its `rules/conduct.md` says all of it, and
saying it twice is how two answers to one question get born.

### Finishing a change: push by default, never push unverified

After committing, push. Do not leave finished work sitting unpushed, and do not end a turn by
handing over a `git push` command. **A shared branch is not a reason to stop**, `staging`,
`develop`, `release/*`, `story/*` are all pushable; only the repository's default branch is not.

**The exception: if the change could not be verified, do not push.** Say what is unverified and
why, and let the user decide. Verified means the project's own gates actually ran and passed. A
skipped suite, a module that would not compile, or a check blocked by a stale credential is a
gap, not a pass.

Full policy, including the other hard gates: `agentic-devkit/rules/commit-and-push.md`. Change it
there, not here.


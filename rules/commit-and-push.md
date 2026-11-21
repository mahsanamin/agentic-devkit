# Committing and pushing (canonical)

How to finish a piece of work. Imported into the global guidance; change it here.

## The default is: commit AND push, without asking

Finish the work, verify the build and tests, commit, push. Do not ask "want me to commit?", and do
not end a turn by handing over a push command. This overrides the harness default of "commit or
push only when asked".

**Any branch that is not the repository's default branch is pushable**, including shared
integration branches (`staging`, `develop`, `release/*`, `story/*`, an epic branch). Being shared
is not a reason to stop. Never report a task as done while a commit sits unpushed: if a gate below
stopped the push, name the gate and give the one-line command.

## The hard gates (these, and nothing else, stop a push)

- **Never commit or push on the default branch**, except in a repo that declares itself
  push-to-default in its own root `AGENTS.md`. That declaration is the only authorization; never
  infer it from a repo looking personal.
- **Merging a PR is the user's call.** Open it, let CI and review land, hand it over.
- **Force-push:** `--force`, `-f`, and `+refspec` never. `--force-with-lease` only on a personal
  feature branch, never on the default branch, `develop`, `release/*`, or `story/*`.
- **Open a PR only when the task was heading there.**
- **Could not verify it? Do not push.** Verified means the project's own gates ran and passed. A
  skipped suite, a module that would not compile, or a check blocked by a stale credential is a
  gap, not a pass. Say what is unverified and let the user decide.
- **`Permission denied (publickey)` is the user's to run.** The ssh-agent has died. Do not retry,
  test ssh, try another remote, or inspect keys. Commit, then hand over
  `cd <repo> && git push origin <branch>`.

Not gates: the branch is shared or deploys somewhere, it is a merge commit, the change is large, a
reviewer might want a look, or you want confirmation. Say what was decided in the report.

## When an attribution hook blocks a commit in his own repo

An org plugin may block every `git commit` that lacks an AI co-author trailer, in every repo. In a
repo he owns personally (no trailer, see the attribution rule), do not add the trailer and do not
stop. Run the repo's own pre-commit hook by hand (`"$(git config core.hooksPath || echo .git/hooks)/pre-commit"`),
and if it passes, commit with `--no-verify`, which that hook accepts as the opt-out. Never use
`--no-verify` in a company repo: there the trailer is added and the hooks run. (`git commit
--no-verify` is allowed in his Claude settings for this, as of 2026-10-30.)

## Pulling in his own repos: plain pull, no rebase

In a repo he owns, when a push is rejected or the branch is behind, run a plain `git pull` (a
merge). Do not rebase and do not ask which to use. If the merge conflicts, resolve the conflicts,
commit, and push. Keep it simple. Recorded 2026-11-06.

## A handed-over command is bare

Give a command for him to run with nothing in front of it: no `!`, `$`, or `>`. He pastes into
zsh, where `! cd repo && git commit ... && git push` inverts the `cd`, stops the chain, and prints
nothing, so it looks like it worked. This overrides the harness suggestion of `! <command>`, which
only works at the Claude Code prompt. Drop the `cd` when he is already in that directory.

Never hand over a heredoc (`cat > file <<'EOF'`): pasting indents the closing `EOF`, so zsh hangs
at `heredoc>`. Keep each command short, one per code block, because a long line wraps when copied
and the inserted newline breaks it. Split the work: `cd` first, then short lines with `echo` or
`printf` and single-quoted content. Recorded 2026-10-31.

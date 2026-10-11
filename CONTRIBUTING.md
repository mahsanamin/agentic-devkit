# Contributing

These are the rules for everyone who changes this repository, people and agents alike.

## Branches

| Branch | What it holds | How it changes |
|---|---|---|
| `develop` | The next release. The default branch. | Pull requests only, with one approval and green checks |
| `main` | The latest release. | Only a release PR from `develop`, cut by the maintainer |
| anything else | Your work in progress | Push freely to your own branch or fork |

Both `develop` and `main` refuse direct pushes and force pushes on GitHub, so a push straight to either one fails. That is expected: push your branch and open a PR.

## Making a change

1. Branch from the latest `develop`. Name the branch after the change, for example `fix/worktree-cleanup-dirty-check` or `feat/zellij-tab-reuse`.
2. Keep one change per PR. A skill fix and an unrelated script refactor are two PRs.
3. Run the tests before you push:
   ```bash
   for t in tests/*.sh; do bash "$t" || echo "FAIL $t"; done
   python3 -m unittest tests/test_agent_modes.py
   ```
4. Open the PR into `develop`. Say what changed and why, and how you checked it. CI runs the same tests and must pass before the PR can merge.
5. The maintainer reviews it. A PR that changes the direction of the toolkit (naming scheme, the source-of-truth model, provider parity) needs that discussed in an issue first.

PRs into `develop` are squash-merged, so the commit history on `develop` reads as one line per change.

## Releases

Releases are cut by the maintainer, usually weekly, with a patch release in between when a fix should not wait. A release bumps `VERSION`, adds an entry to `CHANGELOG.md`, merges `develop` into `main` through a PR titled `Release vX.Y.Z`, and tags `main` with a GitHub release. Contributors do not need to do anything for a release.

Versions follow `X.Y.Z`: a weekly release bumps the middle number, a patch release the last one, and a breaking change (a renamed skill, a removed command, a changed install layout) the first.

## What every change must respect

- **This repository is public.** No employer, client, or project names, no internal hosts, URLs, repo or ticket names, and nothing that identifies where the work is done. Use neutral placeholders. When an example needs a private repo, describe its shape instead of naming it.
- **No secrets.** No tokens, keys, or personal config. The files listed under "Sensitive files" in `AGENTS.md` are never committed.
- **No AI attribution trailers.** No `Co-Authored-By` lines for an agent and no "Generated with" lines, in commits or PR bodies.
- **Follow the naming scheme** in `AGENTS.md` (`a_sk_*`, `a_r_*`, `a_sag_*`, `a_c_*`, `a_s_*`, `a_g_*`). A new skill's `name:` must match its directory.
- **Canonical sources only.** Edit `skills/` and `agents/` in this repo. Provider directories hold links and generated adapters, never sources.
- **Plain language** in docs and skills, as described in `rules/answer-style.md`.

## Reporting a problem

Open an issue with what you ran, what you expected, and what happened. Keep it generic, for the same reason as above: the tracker is public.

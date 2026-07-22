---
name: a_r_l_worktree_cleaner
description: Clean up the git worktrees of one repository in a single pass, safely. Local routine: point it at a repo's main clone directory and it inventories every worktree, removes only the ones that are provably done (branch merged into the default branch, or its PR is merged on GitHub, or its remote branch was deleted and nothing local is unpushed), prunes stale registrations, and leaves anything with real work (uncommitted changes, or unpushed-and-unmerged commits) untouched with a reason. Never touches the main checkout. Repo-agnostic: you pass the repo's local clone path (dir=<path>) and it derives the default branch, worktree list, and PR state itself. Use when asked to clean up / tidy / prune / remove finished worktrees, clear out merged worktrees, "clean the worktrees in <repo>", "get rid of the worktrees whose PRs are merged", or when a scheduled worktree-cleanup routine fires. Parameterized: dir (required, the main clone path), dry_run (default false = actually remove; true = report only), force (default false = also remove unmerged/unpushed worktrees, still never dirty). Invoke as `run a_r_l_worktree_cleaner for dir=<path>`. Triggers even without the exact name: "clean up the worktrees in <repo>", "remove the merged worktrees", "tidy my worktrees", "prune finished worktrees".
---

# a_r_l_worktree_cleaner

Clean the git worktrees of **one** repository in a single pass, without destroying unfinished work. Repo-agnostic and safe by default: you give it the repo's main clone directory, it works out the rest.

This is a thin, deterministic wrapper over raw `git worktree` + `gh`, with the worktree helpers as the removal primitive. Keep it dumb and safe: it only removes worktrees it can *prove* are done.

## Inputs

| Input | Meaning | Default |
|-------|---------|---------|
| `dir` | **Required.** Full path to the repository's **main clone** (not a worktree). All commands run from here. | — |
| `dry_run` | `true` = classify and report only, remove nothing. `false` = actually remove the ones classified removable. | `false` |
| `force` | `true` = also remove worktrees whose branch is unmerged / unpushed (WIP that is not dirty). `false` = leave those alone and report them. **Even with `force`, dirty worktrees are never removed.** | `false` |

Invoke: `run a_r_l_worktree_cleaner for dir=$HOME/repos/<repo>` (add `dry_run=true` to preview, `force=true` to also clear unmerged WIP).

## Safety rules (do not violate)

1. **Never remove the main checkout.** It is the first entry in `git worktree list` and the one whose path is not under `.../WorkTrees/`. If `dir` is itself a worktree (its `git rev-parse --git-common-dir` points elsewhere), stop and tell the user to pass the main clone.
2. **Never remove a dirty worktree** (uncommitted or untracked changes), under any mode. Report it instead.
3. **Never remove unpushed-and-unmerged work** unless `force=true`. A branch with commits not on its remote and not merged anywhere is real WIP.
4. **Removals are the only destructive action.** Do not reset, force-push, or delete remote branches. Local branch deletion happens only as part of removing its (safe) worktree.
5. If any single removal fails or is ambiguous, **skip it, record why, and keep going**. One bad worktree must not abort the pass.

## What counts as "removable"

For each worktree other than the main checkout, classify against the repo's default branch (`main`, else `master`):

**REMOVE (done)** — any of:
- Branch is an ancestor of / merged into the local default branch (`git merge-base --is-ancestor <branch> <default>`, or `git branch --merged <default>` / `git branch --merged origin/<default>` lists it).
- Its PR is **MERGED** on GitHub (`gh pr list --head <branch> --state all --json state,number,title`). This is the authoritative signal and also catches squash-merges the local ancestor check misses.
- Its remote branch is **gone** (`git ls-remote --heads origin <branch>` is empty) **and** the local branch has no unpushed commits — the branch was merged and cleaned up upstream.

**KEEP (report, don't remove)**:
- **Dirty** — has uncommitted/untracked changes. Always kept.
- **Open PR** — `gh` shows an OPEN PR for the branch. Work in review; keep.
- **Unmerged WIP** — not merged, no merged PR, and either unpushed commits or no upstream. Kept unless `force=true`.
- **Closed-not-merged PR** — the PR was closed without merging. Treat as WIP (kept unless `force=true`), because closing without merge usually means abandoned-but-maybe-wanted; do not silently delete.

**PRUNE** separately: stale registrations (git tracks a worktree path that no longer exists on disk). These carry no work and are always safe to prune.

## Execution

Run everything from `dir`. Do the classification with raw git/gh (deterministic, no shell sourcing needed); use the vetted helper for the actual removal.

1. **Validate.** `cd "$dir"`. Confirm it is a git repo and the **main** checkout (`git rev-parse --git-common-dir` resolves inside `$dir/.git`, not elsewhere). Determine the default branch. Fetch/prune remotes so merge and gone-branch checks are current: `git fetch --prune origin` (best-effort; continue if offline, but say so).

2. **Inventory.** Parse `git worktree list --porcelain` into (path, branch) pairs. Drop the main checkout. For a quick human view you may also run the helper report: `cd "$dir" && source worktree.sh 2>/dev/null && a_g_worktree_doctor` — but do the removal decision from the raw checks below, not from the report text.

3. **Classify** each remaining worktree into REMOVE / KEEP / (stale→PRUNE) using the rules above. Gather: dirty?, merged (local+remote)?, PR state (`gh pr list --head <branch> --state all`), remote branch present?, unpushed commit count (`git rev-list --count @{u}..<branch>` when an upstream exists).

4. **Act** (skip this step's removals entirely if `dry_run=true`):
   - For each REMOVE worktree, run from inside `$dir`:
     `a_g_worktree_remove <branch-or-name> --verify`
     `--verify` re-checks merged status (including squash-merge) and removes the worktree **and** its local branch without prompting; it refuses and exits non-zero if the branch is not actually merged. If it refuses but the PR is confirmed **MERGED** via `gh` (squash edge cases), re-run with `--force` instead. Never use `--force` on a KEEP item.
   - When `force=true`, also remove the **Unmerged WIP** and **Closed-not-merged** items with `a_g_worktree_remove <name> --force`. Still never the dirty ones.
   - **Prune stale registrations:** `git -C "$dir" worktree prune` (removes only registrations whose directory is missing; no work at risk, no prompt).

5. **Report.** Print a table: each worktree, its branch, the decision (Removed / Kept / Pruned / Failed), and the one-line reason (e.g. "PR #602 merged", "uncommitted changes", "open PR #610", "unpushed commits, no merge"). End with counts: N removed, M kept, K pruned, and the current `git worktree list` after the pass.

## Notes

- **Squash-merge is the common case in many repos** (PRs squash into `main`), so the `gh` PR-state check is what makes this reliable; the local `--is-ancestor` check alone would miss squashed branches and wrongly keep them. Always consult `gh`.
- The AA worktree layout is `.../WorkTrees/<project>/<branch>`; `a_g_worktree_remove` takes the worktree **name** (the last path segment / branch), not the full path, and acts on the current repo, so `cd "$dir"` first.
- Unattended/scheduled use: pass `dir` as the absolute main-clone path and leave `dry_run=false`. The safety rules above are what make an unattended run non-destructive to live work.

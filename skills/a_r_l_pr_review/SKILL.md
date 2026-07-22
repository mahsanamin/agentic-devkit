---
name: a_r_l_pr_review
description: Review one or more GitHub PRs in an isolated git worktree using parallel agents, without disturbing the working repo. Local routine: for each PR it creates a dedicated review worktree on a review-pr-<N> branch (never your own working branch), runs the project's PR-review skill, optionally auto-posts the comments that clear a high bar, then tears the review worktree down. Use when asked to review a PR, review my assigned PRs, do a worktree PR review, or when a scheduled "PR review" routine fires. Parameterized: pass repo (full local clone path for unattended runs), pr (a number, a list, or "mine" = all PRs assigned to me), and optionally the review skill, parallelism, cleanup, and post (auto = post the comments that clear a high bar without asking, THE DEFAULT; draft = review only, post nothing). Invoke as `run a_r_l_pr_review for repo=<path> pr=<number|mine>`. Triggers even without the exact name: "review PR 123 in a worktree", "review the PRs assigned to me", "do an isolated review of this PR".
---

# a_r_l_pr_review

Review GitHub PRs safely in an **isolated worktree** so the review never touches your main checkout, then drive the project's own review skill. This is a thin, repo-agnostic wrapper. Keep the division of labor strict so the two skills don't fight or duplicate:

## Division of labor (read first)

**`a_r_l_pr_review` (this skill) owns:** PR resolution (incl. `mine`), worktree **isolation**, getting the **PR's head code onto disk on the branch it will merge into**, branch hygiene, the per-PR loop, and **guarded teardown**.

**`review_skill` (e.g. `/review-pr`) owns the review itself — do NOT reinvent any of this:**
- The diff. `/review-pr` runs `gh pr diff <N>`, which is GitHub's **head-vs-base** diff, i.e. the change as it will land in the PR's **merge target**. The base-vs-head comparison is already correct via `gh`; this wrapper does not compute diffs or pick a base.
- Base/head detection (`gh pr view --json baseRefName,headRefName`), ticket/task-intent lookup, rule selection, the reviewer agent, self-review, draft, and posting.

**Why the worktree still matters even though `gh pr diff` is checkout-independent:** `/review-pr`'s agent reviews by **reading the full source files from the working tree** (not just the diff), and `/review-pr` itself **does not check out anything**. Run it from your main checkout and it reads stale code from whatever branch you're on. Running it inside a worktree whose HEAD is the PR's head branch is what guarantees the agent reads the **actual PR code on its merge base**. That is the whole point of this wrapper.

**Posting: `post=auto` is the default.** `/review-pr` on its own stops at a draft and asks which comments to post. This wrapper does not, by design: auto-posting the comments that clear a high bar is the intended behavior for every repo. The mode:
- `post=auto` (**default**) — skip the human-approval gate and **post the comments that clear the bar** (see Auto-post policy), without asking. The agent does not surface the draft for selection; it applies the bar itself, self-verifies each candidate, and posts via `/review-pr`'s own batch path (`gh api repos/{owner}/{repo}/pulls/<N>/reviews`).
- `post=draft` — review only: generate the draft(s), report them, post nothing. Use for a dry run, or a PR you are not ready to comment on.

**Running this skill IS the authorization to post.** The standing intention is encoded here, in the skill itself (not in a per-task instruction or a memory): a bar-clearing comment gets posted. Do NOT re-impose a "draft-only unless explicitly told to post" assumption — on an unattended run that would silently swallow real findings (exactly the failure this skill exists to prevent). To suppress posting, the caller passes `post=draft`.

## Inputs (fill in the blanks)

| Input | Meaning | Default |
|-------|---------|---------|
| `repo` | GitHub repo to review, as a URL (`https://github.com/<org>/<name>`) or `<org>/<name>` slug, or a local clone path. | the current repo (`gh repo view`) |
| `pr` | What to review: a single PR number, a comma list of numbers, or `mine` = every open PR where I am the assignee (`you@example.com`). | `mine` |
| `review_skill` | The project's PR-review skill to run inside the worktree. | `/review-pr` |
| `parallelism` | Max review agents to run at once. | `4` |
| `cleanup` | Remove each review worktree after its review completes. | `true` |
| `post` | `auto` = post the comments that clear the bar (Auto-post policy) without asking (the standing intention for every repo). `draft` = review only, post nothing. | `auto` |

**For an unattended local routine, pass `repo` as the full local clone path** (e.g. `$HOME/repos/my-service`) and **`cd` into it before any `gh` or worktree command.** The `a_g_worktree_*` helpers act on the *current* repo, and a scheduled run does not start inside it, so a bare `<org>/<name>` slug or "current repo" is ambiguous. If `repo` is given as a slug/URL, resolve it to the local clone path (or, if not cloned, clone it first or stop and say so). Resolve `mine` with `gh pr list --search "assignee:@me" --state open` (or `assignee:you@example.com`), run from inside that clone.

## Worktree helpers (the real commands)

This skill uses the worktree helpers. From Claude Code's non-interactive Bash, invoke the scripts directly (the shell-function auto-`cd` does not persist across separate Bash calls, so always `cd` into the printed worktree path yourself):

- **Create (the right primitive for PRs):** `a_g_worktree_review <N>` — looks the PR up via `gh`, fetches its head, and creates a worktree on a local branch **`review-pr-<N>`** at `…/WorkTrees/<project>/review-pr-<N>`. Use this, not `a_g_worktree_init` (that one is for starting your own branch and prompts for a base).
- **Already exists? Delete and recreate.** If `a_g_worktree_review <N>` reports the `review-pr-<N>` worktree/branch already exists, remove it (`a_g_worktree_remove review-pr-<N> --force`) and run `a_g_worktree_review <N>` again. This is the easy, deterministic path: a fresh checkout always reflects the latest PR head. (It only ever deletes a `review-pr-<N>` worktree, never your working tree.)
- **Tear down:** `a_g_worktree_remove review-pr-<N> --force` — removes the worktree and deletes the **local** `review-pr-<N>` branch. `--force` is required so the unattended run is not blocked by the "branch never pushed, delete anyway?" prompt; in this mode it never deletes the remote, so the PR's real branch is untouched. Do **not** use `--verify` / `a_g_worktree_conclude` here: a review branch is never merged, so verify would refuse it.

## Execution model

- Resolve PRs, set up worktrees, and run the review without asking. Posting follows the `post` mode (**default `auto`**): `auto` posts what clears the bar (see Auto-post policy); `draft` posts nothing (review only). If you hit any other genuinely blocking decision, stop and put it in the final report.
- **One PR per worktree per `/review-pr` invocation.** Do NOT hand a list of PRs to a single `/review-pr` call: its multi-PR mode reads every PR's source from one working tree, defeating the point of checking out each PR's head. Run one `review-pr-<N>` worktree + one `/review-pr <N>` per PR.
- Run up to `parallelism` of these per-PR pipelines concurrently. Per-PR worktrees are what make parallel review safe (no checkout collisions). Keep going until every requested PR is reviewed; do not stop early.

## Per-PR lifecycle

For each PR number `N`:

1. **Create (recreate if it exists).** Run `a_g_worktree_review <N>`. If it reports the `review-pr-<N>` worktree/branch already exists, remove it with `a_g_worktree_remove review-pr-<N> --force` and run `a_g_worktree_review <N>` again so you start from a fresh checkout of the latest PR head.
2. **Recover on failure.** If the helper fails, diagnose and recover on your own (e.g. `cd` into `…/WorkTrees/<project>/review-pr-<N>` directly). Always confirm you are inside the right worktree and on the right branch before reviewing.
3. **Verify before reviewing.** Pull the PR's branches with `gh pr view <N> --json headRefName,baseRefName` and print four things: current worktree path, current branch (`review-pr-<N>`), the PR **head** (`headRefName`, must equal what the worktree checked out), and the PR **base** (`baseRefName`, the branch it will merge into). The worktree HEAD must be the PR head; the base is the merge target the review compares against. If head doesn't match, fix it before proceeding.
4. **Review — from inside the worktree.** `cd` into `…/WorkTrees/<project>/review-pr-<N>`, then run `review_skill` (default `/review-pr <N>`). It will run `gh pr diff <N>` (head-vs-base) itself and read the full source files from this worktree, so the review reflects the PR code on its merge base. Do not compute the diff or pick a base yourself. It produces a draft (file path under the reviews root).
5. **Post (mode-dependent).**
   - `post=draft`: post nothing. Record the draft path and what it contained.
   - `post=auto`: from the draft, take the comments marked **Action: Post** whose type is Bug/Error, Security, Missing, or a correctness-affecting Question. Run the self-verify + dedup guard (Auto-post policy). Post the survivors as one batch review on PR `N` via `/review-pr`'s own posting step (`gh api repos/{owner}/{repo}/pulls/<N>/reviews`). Then **verify** they landed (see Target). A clean PR with zero bar-clearing comments posts nothing — that is success, not failure.
6. **Approve when clean (`post=auto` only).** Apply the **Auto-approve policy**: if nothing cleared the bar, there is no open question, all automated reviews (CodeRabbit, SonarQube) and required checks are finished and green, and confidence is high — `gh pr review <N> --approve` and verify it landed. If any of those fail, do not approve; stop and report why. `post=draft` never approves.
7. **Tear down (only if `cleanup` and only what this run created).** Once the review (and any posting) for `N` is complete and its output is captured, remove the review worktree: `a_g_worktree_remove review-pr-<N> --force`. See Teardown safety.

## Auto-post policy (`post=auto`)

Post a drafted comment ONLY if it is marked **Action: Post** by the review and is one of:
- **Bug/Error** — wrong behavior, logic error, data-loss risk
- **Security** — vulnerability, injection, auth bypass
- **Missing** — a required piece whose absence breaks things (missing migration, null check, error handling)
- **Question** — only if the answer materially affects correctness and it genuinely can't be resolved from the code

NEVER auto-post: praise, style nits, "consider X", trade-off / internal notes, or anything the author doesn't need to act on. Those stay in the draft file.

**Self-verify guard before each post (cheap, keeps false positives off the PR):** confirm the concrete code path the comment claims, confirm it's NEW code (not pre-existing/unchanged), and dedup against the PR's existing comments (`gh api repos/{owner}/{repo}/pulls/<N>/comments` + `.../issues/<N>/comments`) so you never repost something already there. Drop any candidate that fails the guard; note it in the report rather than posting a shaky comment.

## Auto-approve policy (`post=auto`)

After the post step, decide whether to **approve** the PR. Approve **only when ALL** of the following hold; if any one fails, do **not** approve — post any bar-clearing comments as usual and **stop**, leaving the call to a human and saying why in the report.

1. **Nothing to raise.** This review posted **zero** bar-clearing comments (no Bug/Error, Security, or Missing), you have **no open correctness-affecting Question**, and there is **no unresolved question or blocking thread from another reviewer** on the PR. A prior review whose only point was a nit that a later commit already fixed does **not** block (verify the fix is actually in the current head).
2. **No automated review pending or unhappy.** Check `gh pr checks <N>`: CodeRabbit has **finished** (not "review in progress") and is not requesting changes; SonarQube's quality gate (if the repo runs one) has **completed and passed**; and required CI checks are **green** (none pending or red). If any required check is still running or failing, do **not** approve — stop and report it.
3. **Confidence is high.** The change is small/clear enough that you verified it end to end and have no material doubt.

When all three hold, approve via `gh pr review <N> --approve --body "<one short paragraph: what you statically verified + that checks are green>"`, then **verify it landed** (`gh pr view <N> --json reviews`). Approving is fine even when the PR still shows `reviewDecision: REVIEW_REQUIRED` — that means a specific CODEOWNERS/required approver is separate from you; your approval is still recorded. Note the approval (or why you held off) in the report.

**Never** auto-`REQUEST_CHANGES` and **never** auto-merge. `post=draft` never approves (it is a dry run). This approval authority rides on the same standing intent as `post=auto`: the caller opted into acting on the PR without a per-task gate.

## Teardown safety (the one hard rule)

The only thing this skill ever deletes is a `review-pr-<N>` worktree (the throwaway review checkout). Deleting and recreating one that already exists is fine and expected — that is the easy path. But:

- **Only `review-pr-*` names, ever.** Never remove a worktree or branch whose name does not match `review-pr-<N>`. Never the main worktree, never a feature/story branch, never anything you are actively working in. This is the non-negotiable guarantee.
- `a_g_worktree_remove`'s protected-branch guard (main/master/staging/develop/...) and its refusal to remove the main worktree are a backstop, not your primary check. Decide by exact `review-pr-<N>` name first, then let the guard catch mistakes.

## Target (done-when) — self-check before concluding

Treat this as the routine's goal and verify it for **every** requested PR before you report done. Do not conclude on "I produced a draft"; conclude on the target below.

For each PR `N`:
1. **Reviewed:** the worktree was created, its HEAD matched the live PR head SHA (`gh pr view <N> --json headRefOid`), the review ran, and a draft exists.
2. **Posting matches the mode:**
   - `post=draft`: nothing posted; the draft path is reported. ✓
   - `post=auto`: **every** comment that cleared the bar was actually posted. **Verify, do not assume:** after posting, re-fetch `gh api repos/{owner}/{repo}/pulls/<N>/comments` and confirm each intended comment is present. Report the posted count. If a qualifying comment failed to post (API error, etc.), retry once; if it still fails, the target is **NOT met** for that PR — say so explicitly with the unposted comment(s). Never silently drop a bar-clearing comment.
   - **Approval (`post=auto`):** if the Auto-approve policy's conditions were all met, the PR was approved and the approval was verified present (`gh pr view <N> --json reviews`); if any condition failed, no approval was made and the report says which condition held it back. State which path was taken.
3. **No collateral:** the worktree was torn down (if `cleanup`), and the **main checkout is untouched** (same branch/HEAD it started on). Confirm and state this.

If any PR's target is not met, the run is not done: surface exactly which PR and which sub-check failed. A PR with zero bar-clearing comments meets the target with zero posts — that is success.

## Report

End with a per-PR summary: PR number + title; worktree path and branch; head and base (merge target) compared; the `post` mode; **comments posted (count + which) or "draft only"**, with the draft file path; whether the worktree was recreated and torn down; and the **target status per PR (met / not met + why)**. State explicitly that the main checkout is unchanged. Note any PR you could not position correctly.

## Run logging (visibility)

When this run finishes (success, partial, nothing-to-do, or failure), call the **a_sag_routine_logger** sub-agent once (Agent tool, `subagent_type: a_sag_routine_logger`) with `routine=<this skill's name from the frontmatter above>`, a `status`, and a one-line `summary` of what the run did. It appends a single dated line to `MyAutomations/ClaudeRoutines/<routine>/logs/<YYYY-MM>.md`, so the last run and what it did are visible at a glance. Keep the summary to ONE line. Logging is best-effort: if the mdnest CLI is unavailable (e.g. a headless cloud run) the logger no-ops; never let a logging failure abort the routine's real work.

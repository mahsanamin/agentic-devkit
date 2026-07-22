---
name: a_sk_l_review_pr
description: Review a GitHub PR end-to-end from just its URL. Give it a PR link (or owner/repo#N); it finds the repo you ALREADY have cloned locally (via a cached lookup, then a scan of your cd_w workspace — never a duplicate clone), clones into cd_w only if you don't have it, spins up a git worktree checked out on the PR's real head branch updated to latest, then runs the project's own review skill (review-pr) if it has one or the global global-pr-reviewer otherwise, auto-posts the comments that clear a high bar as GitHub inline review comments, and tears the worktree + local branch down. This is a SKILL, not a routine (no _r); a routine may call it. Use when asked to "review this PR <url>", "review a PR from its link", "do a full review of <github pull url>", or given a bare GitHub PR URL to review. Parameterized: pr (URL / owner/repo#N / number), post (auto | draft), reviewer (auto | project | global).
---

# a_sk_l_review_pr — review a GitHub PR from its URL

One entry point: hand it a PR URL and it does the whole thing. It owns **getting the right code onto disk with zero duplication** and the **posting + cleanup**; it delegates the **review itself** to an existing reviewer skill. Do not reinvent the review engine, the repo-resolution logic, or the worktree layout — each already exists and is reused here.

> **From a terminal (no need to open Claude first):** the command `a_c_review_pr <pr-url>` does the mechanical setup — resolve the repo, make the worktree on the head branch — and then launches a Claude session in auto mode whose opening prompt runs *this* review policy. When invoked that way you are told "you are already in the worktree" — so skip step 2/4 (resolve + create) and go straight to the review + post; the command handles teardown.

## What this reuses (do not duplicate)

- **Repo resolution + cache:** the `a_s_resolve_repo` script (in `my_setup/scripts/`, on PATH). It turns a PR/repo reference into a local clone path via cache → `cd_w` workspace scan (match by git remote) → clone into `cd_w`. It is the single source of truth for "which local clone is this PR's repo" and for avoiding duplicate clones.
- **The review engine:** the project's `review-pr` skill, or the global `global-pr-reviewer`. These produce the categorized review draft (diff, rules, reviewer agent, GitHub-style inline comments). This skill never re-implements the diff or the review.
- **Auto-post policy, self-verify guard, and teardown-safety rules:** identical to `a_r_l_pr_review` (`skills/a_r_l_pr_review/SKILL.md`). Read that skill's **Auto-post policy** and **Teardown safety** sections and apply them verbatim — they are restated compactly below, not forked.

## Inputs

| Input | Meaning | Default |
|-------|---------|---------|
| `pr` | The PR: a full URL (`https://github.com/<owner>/<repo>/pull/<N>`), an `<owner>/<repo>#<N>` slug, or a bare number **only if** you are already inside the repo. | required |
| `post` | `auto` = post the comments that clear the bar (below) without asking. `draft` = review only, post nothing. | `auto` |
| `reviewer` | `auto` = project `review-pr` if the repo has it, else global `global-pr-reviewer`. `project` / `global` force one. | `auto` |

## Flow

### 1. Parse the PR reference
From `pr`, get `OWNER`, `REPO`, and the PR number `N`. A bare number with no repo context is ambiguous — if you can't tell the repo, ask for the URL. Keep the canonical PR URL `https://github.com/<OWNER>/<REPO>/pull/<N>` for the reviewer + reporting.

### 2. Resolve the repo to a LOCAL clone (cache → workspace → clone)
Run the resolver (on PATH; it prints only the path on stdout):

```bash
REPO_PATH="$(a_s_resolve_repo "<the PR url or OWNER/REPO>")" || { echo "could not resolve repo"; exit 1; }
```

- It reuses a clone you already have under `cd_w` (matched by the origin remote's `owner/repo`, or by repo-name when unique — the fork case) and records it in the cache so next time is instant.
- It clones into `cd_w` **only** if you have no local copy. If it exits non-zero with an "ambiguous" message (two same-named clones, different owners), surface that and stop — don't guess.
- Never hand-clone a duplicate; always go through `a_s_resolve_repo`.

`cd "$REPO_PATH"` before any `gh`/`git`/worktree command below.

### 3. Read the PR's branch + state
```bash
gh pr view <N> --json headRefName,baseRefName,headRefOid,state,isCrossRepository,title,url
```
Record: `headRefName` (the branch the PR is from — what you check out), `baseRefName` (merge target the review compares against), `headRefOid` (the live head SHA, for the done-check), and `isCrossRepository` (fork PR?).

### 4. Create a worktree on the PR's **head branch**, updated
Worktrees live beside the main repo, matching the layout used everywhere else:
`WT="$(dirname "$REPO_PATH")/WorkTrees/$(basename "$REPO_PATH")/<dir>"`.

- **Fetch latest first** so the branch is up to date: `git fetch origin`.
- **Same-repo PR** (`isCrossRepository=false`) — check out the *actual* head branch so you can even push fixes, updated to the remote head:
  - `LOCAL_BR="$headRefName"`, `WT=".../WorkTrees/<project>/${headRefName//\//-}"`.
  - If `$headRefName` is already checked out in another worktree, reuse that worktree (`git worktree list`) and `git -C <wt> pull --ff-only` instead of creating a second one. Otherwise:
    `git worktree add -B "$LOCAL_BR" "$WT" "origin/$headRefName"` (the `-B` resets it to the fresh remote head).
- **Fork PR** (`isCrossRepository=true`) — you can't track a fork branch by name cleanly, so fetch the PR head ref (always present on the base repo) into a review branch:
  - `git fetch origin "pull/$N/head"` then `LOCAL_BR="pr-$N-review"`, `git worktree add -b "$LOCAL_BR" "$WT" FETCH_HEAD`. Note in the report that fixes can't be pushed back to the fork from here.
- **Verify before reviewing:** print the worktree path, the checked-out branch, and confirm `git -C "$WT" rev-parse HEAD` equals `headRefOid`. If it doesn't, fetch again / fix before proceeding. `cd "$WT"`.

### 5. Pick the reviewer and run it (from inside the worktree)
- `reviewer=auto`: if `"$REPO_PATH/.claude/skills/review-pr/SKILL.md"` exists → use the **project** reviewer: `/review-pr <N>`. Else → use the **global** reviewer: `global-pr-reviewer <PR-URL>`. (`global-pr-reviewer` is installed globally and is itself project-aware, so it is a safe fallback; it must never be re-created — per this repo's rules `aa-*` skills belong to the upstream framework, not here.)
- If the project reviewer's skill is present on disk but not invocable in this session, fall back to the global reviewer rather than failing.
- The reviewer reads the full source from **this worktree** (that's why the head-branch checkout matters) and runs `gh pr diff <N>` (head-vs-base) itself. It emits a categorized **draft** (path under the reviewer's reviews root). Do not compute the diff or pick a base yourself.

### 6. Post — `post=auto` (default) or `draft`
Apply `a_r_l_pr_review`'s **Auto-post policy** verbatim. Compactly:
- Post ONLY comments the draft marks **Action: Post** that are **Bug/Error**, **Security**, **Missing** (a required piece whose absence breaks things), or a **Question** that materially affects correctness. Never post praise, style nits, "consider X", or trade-off notes.
- **Self-verify guard before each post:** confirm the exact code path the comment claims, confirm it's NEW code in this PR (not pre-existing), and **dedup** against the PR's existing comments (`gh api repos/{OWNER}/{REPO}/pulls/<N>/comments` and `.../issues/<N>/comments`) so nothing is reposted. Drop anything that fails the guard; note it in the report.
- Post the survivors as ONE batch review via `gh api repos/{OWNER}/{REPO}/pulls/<N>/reviews`, GitHub inline-comment style with fix suggestions. **Verify they landed** (re-fetch the comments). A clean PR with zero bar-clearing comments posts nothing — that is success.
- `post=draft`: post nothing; report the draft path and what it contained.

Running this skill with `post=auto` **is** the authorization to post (same standing intent as `a_r_l_pr_review`); do not re-impose a draft-only default.

### 6b. Approve when clean — `post=auto` only
Apply `a_r_l_pr_review`'s **Auto-approve policy** verbatim. Compactly: after posting, **approve the PR only when ALL hold** — (1) nothing cleared the bar (zero Bug/Error/Security/Missing posted, no open correctness-affecting Question, no unresolved blocking thread from another reviewer; a nit a later commit already fixed doesn't count), (2) no automated review is pending or unhappy — `gh pr checks <N>` shows CodeRabbit finished and not requesting changes, SonarQube's gate (if any) passed, and required CI is green (nothing pending/red), and (3) confidence is high. Then `gh pr review <N> --approve --body "<one short paragraph of what you statically verified + checks green>"` and verify it landed (`gh pr view <N> --json reviews`); approving is fine even if the PR still shows `REVIEW_REQUIRED` (a required CODEOWNERS approver is separate). If **any** condition fails — a question exists, a bot is mid-run, a check is red, or confidence isn't high — do **not** approve: post any bar-clearing comments and **stop**, leaving the call to a human and saying why. Never auto-`REQUEST_CHANGES`, never auto-merge; `post=draft` never approves.

### 7. Tear down — the ONE hard safety rule
After the review (and any posting) is captured, remove **only** what this run created, and **only locally**:

```bash
cd "$REPO_PATH"                       # leave the worktree first
git worktree remove --force "$WT"
git branch -D "$LOCAL_BR"             # LOCAL branch only
```

- **NEVER delete the remote branch.** It is the PR's real source branch. Do NOT run `git push origin --delete …`, and do NOT use `a_g_worktree_remove` here — that helper deletes the remote branch by default (only `--keep-remote` stops it), so plain `git` above is the safe path.
- Never delete a protected branch (`main`/`master`/`develop`/`staging`/`prod`). For a same-repo PR the local branch equals `headRefName`; deleting the *local* copy is safe (remote untouched). If that local branch had un-pushed commits of your own (ahead of origin), keep it and say so instead of deleting.
- The main checkout is never touched.

## Target (done-when) — self-check before concluding
1. **Right code:** `REPO_PATH` is your existing clone (no duplicate was made — or a clone was made only because you truly lacked one), and the worktree HEAD matched `headRefOid`.
2. **Reviewed:** the chosen reviewer ran against the worktree and produced a draft.
3. **Posting matches the mode:** `auto` → every bar-clearing comment was posted **and verified present** (retry once on failure; if it still fails, say which comment didn't post — never silently drop it). `draft` → nothing posted, draft path reported.
4. **Approval decided (`post=auto`):** either the PR was approved (Auto-approve policy's conditions all met) and the approval was verified present, or it was intentionally held (state which condition — a question, a pending/red check, or low confidence — held it back). `draft` never approves.
5. **Cleaned up:** worktree removed, local review branch deleted, **remote branch untouched**, main checkout unchanged. State this explicitly.

## Report
End with: PR number + title + URL; resolved repo path and whether it came from cache / workspace / a fresh clone; head branch and base (merge target); worktree path + local branch; which reviewer ran (project vs global); comments posted (count + which) or "draft only" with the draft path; **whether the PR was approved or held (and why held)**; and the **target status (met / not met + why)**. Confirm the remote branch and main checkout are untouched.

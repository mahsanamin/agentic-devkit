---
name: a_sk_review_pr
description: Review a GitHub PR end-to-end from just its URL. Give it a PR link (or owner/repo#N); it finds the repo you ALREADY have cloned locally (via a cached lookup, then a scan of your cd_w workspace — never a duplicate clone), clones into cd_w only if you don't have it, spins up a git worktree checked out on the PR's real head branch updated to latest, then runs the project's own review skill (review-pr) if it has one or the global global-pr-reviewer otherwise, auto-posts the comments that clear a high bar as GitHub inline review comments, and tears the worktree + local branch down. This is a SKILL, not a routine (no _r); a routine may call it. Use when asked to "review this PR <url>", "review a PR from its link", "do a full review of <github pull url>", or given a bare GitHub PR URL to review. Parameterized: pr (URL / owner/repo#N / number), post (auto | draft), reviewer (auto | project | global).
---

# a_sk_review_pr — review a GitHub PR from its URL

One entry point: hand it a PR URL and it does the whole thing. It owns **getting the right code onto disk with zero duplication** and the **posting + cleanup**; it delegates the **review itself** to an existing reviewer skill. Do not reinvent the review engine, the repo-resolution logic, or the worktree layout — each already exists and is reused here.

> **Optional Claude terminal wrapper:** `a_c_review_pr <pr-url>` performs the mechanical setup and launches Claude with this policy. Codex and AGY users invoke this shared skill from their existing session. When the wrapper says "you are already in the worktree", skip repo resolution and worktree creation; the wrapper handles teardown.

## What this reuses (do not duplicate)

- **Repo resolution + cache:** the `a_s_resolve_repo` script (in `agentic-devkit/scripts/`, on PATH). It turns a PR/repo reference into a local clone path via cache → `cd_w` workspace scan (match by git remote) → clone into `cd_w`. It is the single source of truth for "which local clone is this PR's repo" and for avoiding duplicate clones.
- **The review engine:** the project's `review-pr` skill, or the global `global-pr-reviewer`. These produce the categorized review draft (diff, rules, reviewer agent, GitHub-style inline comments). This skill never re-implements the diff or the review.
- **Review-started announcement, auto-post policy, self-verify guard, and teardown-safety rules:** identical to `a_r_l_pr_review` (`skills/a_r_l_pr_review/SKILL.md`). Read that skill's **Review-started announcement**, **Auto-post policy**, and **Teardown safety** sections and apply them verbatim — they are restated compactly below, not forked.

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

### 4. Create the worktree with `a_c_review_pr`, never by hand
**Do not run `git worktree add` yourself, and do not write a launcher script.**
`a_c_review_pr` already does the whole job: it resolves the repo, fetches, picks
the right strategy for a same-repo vs a fork PR, verifies the checked-out HEAD
against the live PR head, and tears the worktree down afterwards. Call it:

```bash
"$MY_WORKFLOW_DIR/scripts/a_c_review_pr" <pr-url-or-number>
```

Use the absolute path as written. `scripts/` is only on `PATH` for an
interactive shell, so a bare `a_c_review_pr` resolves when you type it and fails
inside a launcher, a zellij pane, or a scheduled run.

Two rules that exist because breaking them has cost real debugging time:

- **Never hand-roll the worktree.** Duplicating the fetch-and-add logic here is
  how a second, weaker implementation appears: the hand-rolled versions kept
  missing the fork case, where the head branch does not exist on the base repo at
  all and only `pull/<N>/head` works.
- **Never write your own launcher script.** A generated `launch-pr<N>.sh` that
  calls a devkit command by bare name dies with `a_c_claude_remote: not found`,
  because nothing outside an interactive shell has `scripts/` on `PATH`. When a
  session needs its own tab, call `a_c_zellij_tab` or `a_c_task_start`; both build
  a launcher that sets `PATH` correctly.

`a_c_review_pr` prints the worktree path and the branch it checked out. Read them
from its output, `cd` there, and review. If it warns that HEAD does not match the
PR head, stop and resolve that before reviewing: you would otherwise be reviewing
a stale commit and reporting it as current.

### 4b. Announce that the review has started (`post=auto` only)
Apply `a_r_l_pr_review`'s **Review-started announcement** verbatim. Before any code is read, post ONE top-level comment so the author knows a review is underway. Read the machine identity from the active provider's global guidance (`CLAUDE.md`, `AGENTS.md`, or `GEMINI.md`) when present, and name the actual runtime (`Claude Code`, `Codex`, or `AGY`). If no agent identity exists, use only the runtime label and never invent a name.

```bash
HEAD_SHA="$(gh pr view <N> --json headRefOid --jq '.headRefOid[0:7]')"
ALREADY="$(gh api "repos/{OWNER}/{REPO}/issues/<N>/comments" \
  --jq "[.[] | select(.body | test(\"Review started\"; \"i\")) | select(.body | contains(\"$HEAD_SHA\"))] | length")"

if [ "$ALREADY" = "0" ]; then
  gh api "repos/{OWNER}/{REPO}/issues/<N>/comments" -f body="🔍 Review started by **<AGENT-NAME-IF-ANY>** (<RUNTIME>) on \`$HEAD_SHA\`.
Anything that needs action will land as inline comments; a clean pass posts nothing."
fi
```

- **Never reword the marker:** always the literal `🔍 Review started`, even on a re-review. The idempotency grep depends on it, so a variant like "Re-review started" defeats the check and duplicates the comment. The head SHA already distinguishes a re-review.
- **Idempotent per head SHA:** the check above must pass before posting, and use the same case-insensitive grep to verify it landed. A force-push (new head SHA) gets a fresh announcement.
- **`post=draft` posts nothing here:** a dry run leaves no trace on the PR.
- **Best-effort:** if it fails, note it and review anyway. This step must never block the review.
- This runs even on the `a_c_review_pr` path where steps 2 and 4 are skipped, since the worktree already exists there.

### 5. Pick the reviewer and run it (from inside the worktree)
- `reviewer=auto`: look for the project's `review-pr` skill in the active provider's project skill paths (`.claude/skills`, `.agents/skills`, or `.gemini/skills`) and invoke it with the provider-native skill mechanism. If none is invocable, delegate the review to `a_sag_code_reviewer`.
- If a project reviewer exists on disk but is not invocable in this session, use `a_sag_code_reviewer` rather than failing.
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
2. **Announced (`post=auto`):** the review-started comment is present on the PR for the current head SHA (posted by this run, or already there from an earlier run on the same head). Say so if the post failed. `draft` → nothing was posted.
3. **Reviewed:** the chosen reviewer ran against the worktree and produced a draft.
4. **Posting matches the mode:** `auto` → every bar-clearing comment was posted **and verified present** (retry once on failure; if it still fails, say which comment didn't post — never silently drop it). `draft` → nothing posted, draft path reported.
5. **Approval decided (`post=auto`):** either the PR was approved (Auto-approve policy's conditions all met) and the approval was verified present, or it was intentionally held (state which condition — a question, a pending/red check, or low confidence — held it back). `draft` never approves.
6. **Cleaned up:** worktree removed, local review branch deleted, **remote branch untouched**, main checkout unchanged. State this explicitly.

## Report
End with: PR number + title + URL; resolved repo path and whether it came from cache / workspace / a fresh clone; head branch and base (merge target); worktree path + local branch; which reviewer ran (project vs global); whether the **review-started comment** was posted (or already present, skipped for `draft`, or failed); comments posted (count + which) or "draft only" with the draft path; **whether the PR was approved or held (and why held)**; and the **target status (met / not met + why)**. Confirm the remote branch and main checkout are untouched.

---
name: a_r_l_dependabot_collector
description: Run this to take a repository's whole backlog of open Dependabot PRs off someone's plate in one pass. The work is always the same shape: many open dependency-update / dependency-bump PRs from the bot, fix each red one to green, set risky ones aside and flag them, batch the rest onto the current month's release branch, then open a single consolidated PR for a human to review. The routine runs weekly; the release it builds is monthly, so each weekly run adds onto the same monthly release branch and keeps the open consolidation PR fresh (open a new one, close the old) so an org-wide stale-PR automation can't auto-close it before review. Repo-agnostic; point it at a local path or a GitHub URL/slug (it reuses your clone or clones into your workspace), and it auto-detects the repo's config, asking only for the build/test command when that can't be safely determined. Reach for it on asks like "process / clean up / triage / batch the dependabot PRs", "fix the red bumps and combine them", "weekly or monthly dependency bump run or sweep", "consolidate this month's dependency upgrades into one PR I can review", "N dependabot PRs are piling up, get them green and into one PR", "deal with the dependabot backlog", "process dependabot for <repo>", "run a_r_l_dependabot_collector", or a scheduled call with repo=<slug> or path=<dir>. These are multi-PR, end-to-end jobs even when phrased casually. Don't use it for single-PR or setup work: authoring dependabot.yml, scheduling the routine, explaining one bump's diff, merging an already-reviewed PR, or just listing open PRs.
---

You maintain a repository's open Dependabot PRs end to end. You are typically invoked one of two ways: interactively (a person asks you to process a repo's Dependabot PRs) or from a scheduled routine that passes `repo=<slug>` or `path=<dir>` (optionally `build_cmd=<cmd>`) and expects zero interaction. Run autonomously; during a scheduled run never ask the user questions. If you hit a genuinely blocking decision, stop and leave it in the final report instead of guessing.

## Cadence and release scope

This routine runs **weekly**, but the release it builds is **monthly**. "Monthly release" is the *batching target*, not how often you run. Each weekly run adds that week's freshly-green bumps onto the *current month's* release branch (`release/dependabot-<YYYY-MM>`) and its single open consolidation PR. So within a month the same release branch and the same consolidation PR accumulate across roughly four weekly runs; on the first run of a new month you start a fresh branch and PR for the new tag.

Two consequences shape every run:

- **A weekly run with no new bumps is not a no-op.** You must still keep the open consolidation PR fresh (Phase 3's refresh step), because an org-wide automation (the CTO's stale-PR process) closes PRs that sit open too long, and our long-lived consolidation PR is exactly what it sweeps.
- **Do not redo earlier weeks' work.** Bumps already merged onto the release branch, or already held out and flagged, are done. Each run only acts on Dependabot PRs not yet merged onto the current release branch.

## Step 0 — Resolve the target repo to a local clone

You need a local clone to build and test in. There is no repo registry to maintain: you take a path or a GitHub reference and resolve it. In order:

1. `path=<dir>` (or the user names a local directory): use it directly, once you confirm it is a git repo (`git -C <dir> rev-parse --git-dir`).
2. `repo=<owner/repo|slug>`, `url=<github url>`, or a bare slug/URL: hand it to the resolver, which reuses a clone you already have (its cache, then a scan of your `cd_w` workspace) and only clones into `$a_dir_w_repos` (the predefined workspace root) if you don't have one:
   ```
   REPO_PATH="$(a_s_resolve_repo -q "<slug-or-url>")"    # prints only the local path on stdout
   ```
   If it exits non-zero (unparseable slug, ambiguous same-name clones, clone failed), stop and report its stderr; do not guess a path.
3. Nothing usable passed AND a human is present interactively: ask for a local path or a GitHub URL, then resolve via step 1 or 2.
4. Nothing passed and this is a scheduled/non-interactive run: stop with a one-line report, "No repo specified." Do not guess.

`<REPO_PATH>` everywhere below is the resolved absolute path. `a_s_resolve_repo` needs `$a_dir_w_repos` set (it comes from the sourced profile); if it is unset, source the profile or pass a `path=` instead.

Tag: use the current calendar month, so the consolidation branch is `release/dependabot-<YYYY-MM>`. Reuse it if it already exists, since the weekly runs within a month all share one monthly tag (see "Cadence and release scope").

## Step 0.5 — Detect the repo's config

Everything the old per-repo registry stored is either constant, auto-detectable from `<REPO_PATH>`, or (for the one field that isn't) resolved once and cached. Determine each placeholder used below:

- `<BASE_BRANCH>` — the repo's default branch: `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` (run in `<REPO_PATH>`). Fallback: `git -C <REPO_PATH> symbolic-ref --short refs/remotes/origin/HEAD` and strip the `origin/` prefix.
- `<DEPENDABOT_AUTHOR>` — default `app/dependabot`. Confirm it actually authored the open PRs in Phase 0; a few orgs use a different bot login.
- `<WORKTREE_HELPER>` — always `a_g_worktree` (invoke the `a_g_worktree_<verb> <args>` command; it is on PATH once this repo's shell profile is loaded, or run it by path as `bash "$MY_WORKFLOW_DIR/scripts/a_g_worktree_<verb>" <args>`).
- `<INFRA_NOISE>` — derive from the detected ecosystem: npm/Node -> `registry.npmjs.org`; Gradle/Maven -> `plugins.gradle.org`, Maven Central. Always also treat `github.com` as infra noise (git deps, actions, `@scope` git installs).
- `<BUILD_TEST_CMD>` — the "green gate". This is the ONE field that cannot be safely guessed, so resolve it in this order and never skip the ambiguity guard:
  1. If `build_cmd=` was passed (interactively, or set in the routine's schedule config), use it verbatim.
  2. Else check the gate cache `~/.a_tasks/dependabot_gates.tsv` (TSV: `slug<TAB>command`), keyed by the repo slug. If a row exists, use it.
  3. Else auto-detect from the repo root: `gradlew`/`build.gradle` -> `./gradlew test`; a root `package.json` with a `build` script -> `npm ci && npm run build && npm test` (build is usually the real gate); a root `package.json` without a build script -> `npm ci && npm test`.
  4. **Ambiguity guard (this is the user-auth-services case).** If the open Dependabot PRs target directories that do NOT match the root build system (e.g. a Gradle root, but every open bump is an npm bump inside subprojects), root detection is untrustworthy: DO NOT use it. Interactive -> ask for the exact command and whether it runs per-subdirectory. Scheduled/non-interactive -> stop and report: "green gate ambiguous; pass build_cmd= (root is <root ecosystem>, but bumps live in <dirs>)." Never guess a gate across ecosystems.
  Once resolved by ask or detection (not when it came from the cache), persist it so the next run, especially an unattended scheduled one, does not re-block:
  ```
  mkdir -p ~/.a_tasks
  tmp=~/.a_tasks/dependabot_gates.tsv.tmp
  { [ -f ~/.a_tasks/dependabot_gates.tsv ] && awk -F'\t' -v k="<slug>" '$1!=k' ~/.a_tasks/dependabot_gates.tsv; \
    printf '%s\t%s\n' "<slug>" "<BUILD_TEST_CMD>"; } > "$tmp" && mv "$tmp" ~/.a_tasks/dependabot_gates.tsv
  ```

For known per-stack traps (Gradle JDK overshoot, Next-9/React-16 majors, `@myorg/internal-lib` git dep, conflicting axios PRs), consult "Ecosystem gotchas (reference)" at the bottom. Those are optional hints, not required config; add to them as runs discover new traps.

## Hard rules

- Never commit directly to `<BASE_BRANCH>`. Always work in a dedicated worktree/branch.
- "Green" means the full suite passes (`<BUILD_TEST_CMD>`), not just a compile.
- Always sync a branch with the latest `<BASE_BRANCH>` before building, testing, or merging onto it.
- You may merge green PRs into the release branch. You may NOT merge the release branch into `<BASE_BRANCH>`; that PR stays open for human review.
- A red CI run is not automatically a real failure. Transient 429 / Too Many Requests from `<INFRA_NOISE>`, and dependency-download flakes, are infra noise: re-run once before investigating, and never edit code to chase a network or rate-limit error.
- Assemble the release branch only through GitHub PR merges, one PR at a time: push the PR's green-fix commits to its own branch, re-target its base to the release branch, then `gh pr merge`. Never `git merge` the PR branches into the release branch locally and push. That pre-populates the release branch, so GitHub then refuses to re-target the PRs ("no new commits between base and head") and they strand on `<BASE_BRANCH>`.
- Never force-push, and never delete-then-recreate the release branch to "redo" a botched merge order. A safety hook may block force-push, and deleting the branch closes the open consolidation PR. Get the order right the first time.
- An org-wide automation (the CTO's stale-PR process) closes PRs that stay open too long, and the consolidation PR is exactly its target: one long-lived PR awaiting human review. Do not let it get swept. Keep it fresh by refreshing it on the weekly cadence (Phase 3): open a new consolidation PR from the same release branch and close the old one, which resets the staleness clock. Refreshing swaps only the PR object; it never touches the release branch (per the no-delete rule above).

## Phase 0 — Discover & dedupe

Run `gh pr list --state open --author "<DEPENDABOT_AUTHOR>" --json number,title,headRefName,baseRefName` (in `<REPO_PATH>`).

If there ARE new bumps: close exact duplicates (e.g. the same bump opened twice), treat one PR spanning multiple directories as a single unit, produce the list of distinct bumps, and continue to Phase 1.

If there are NO new Dependabot PRs, do not stop yet, because a weekly run still has to keep any open consolidation PR fresh. Skip Phases 1-2 and go straight to Phase 3's refresh step. Only when there are neither new bumps nor an open consolidation PR for the current tag is the run a genuine "nothing to do": report that and stop.

## Phase 1 — Fix each PR green (work in parallel)

Spin up as many agents as makes sense, one per distinct PR/worktree. A spawned agent does not inherit this skill's context, so give each one the resolved repo config it needs (`<REPO_PATH>`, `<BUILD_TEST_CMD>`, `<BASE_BRANCH>`, `<WORKTREE_HELPER>`, and the relevant `<GOTCHAS>`).

1. Existing branch -> `<WORKTREE_HELPER>_switch`; otherwise `<WORKTREE_HELPER>_init`.
2. Sync the branch with latest `<BASE_BRANCH>` first.
3. Build and run the full test suite (`<BUILD_TEST_CMD>`).
4. Fix to green, two ways: (a) adapt our code to the new version (call sites, configs, tests); (b) when Dependabot overshoots, keep the intended upgrade but pin the incompatible sub-component. See `<GOTCHAS>` for this repo's known ecosystem traps.
5. Confidence gate, two tiers:
    - Tier 1: the full suite must be green.
    - Tier 2: bumps CI cannot actually validate still need a human flag even when green. These include runtime base images (a JRE bump is never booted by CI), deploy/auth actions (AWS credential actions, ECR push), and external-service-version compatibility (SonarQube server, etc.). Record each one for the PR risk notes.
    - If a bump cannot go green without risky behavioral changes, hold it out of the batch and flag it. Do not let one bump block the others.
6. If a PR needed code/config fixes to go green, commit them AND push them to that PR's own origin branch (`git push origin HEAD:<dependabot-branch>`), so the PR is green and self-contained on origin. Fixes must not live only in your local worktree, otherwise the later GitHub merge brings the un-fixed origin branch.

## Phase 2 — Consolidate onto release/dependabot-<tag> (GitHub-first; never pre-merge locally)

The release branch is assembled through GitHub PR merges, one PR at a time. Do not `git merge` the PR branches into the release branch locally and push. Your local worktree is only for the final combined re-verify, never for assembling the merges.

1. Release branch: if it exists, `<WORKTREE_HELPER>_switch` and sync with latest `<BASE_BRANCH>`; otherwise `<WORKTREE_HELPER>_init` from latest `<BASE_BRANCH>`. Push it to origin so it exists remotely (`git push -u origin release/dependabot-<tag>`).
2. For each green PR, in turn:
     a. If you made fix commits, ensure they are pushed to that PR's own origin branch (Phase 1 step 6). The PR must be green on origin before merging.
     b. Re-target its base from `<BASE_BRANCH>` to the release branch: `gh pr edit <n> --base release/dependabot-<tag>`. Do this while the PR still has a real diff vs the release branch (before its commits land there). Confirm `mergeable=MERGEABLE`.
     c. Merge via GitHub: `gh pr merge <n> --merge`. Confirm state becomes MERGED with base = `release/dependabot-<tag>`.
3. After all PRs are merged: pull `origin/release/dependabot-<tag>` locally and run the full suite (`<BUILD_TEST_CMD>`). Commit any combined-only fixes directly to the release branch and push (normal push). Bumps that pass alone can fail together (e.g. a Gradle major bump forcing a Sonar-plugin bump plus an explicit JUnit Platform launcher that lived in no single Dependabot PR).

Note on duplicates / un-retargetable PRs: if a PR cannot be re-targeted because its commits are already in the release branch ("no new commits between base and head"), the consolidation order was wrong, you local-merged it. Do not paper over it with a comment; the PR will dangle on `<BASE_BRANCH>`. Fix the order, not the symptom.

## Phase 3 — Maintain and refresh the consolidated PR to base

1. **Ensure the consolidation PR exists and is current.** Maintain a single PR: `release/dependabot-<tag>` -> `<BASE_BRANCH>`. Prefix the title to signal review weight (e.g. `DANGER | Dependabot consolidation (<tag>)`). If new bumps landed this run, update the body. The body must list: every bump included, every Tier-2 bump with the manual check it needs, and any bump held out of the batch.

2. **Refresh it weekly so the CTO's auto-close cannot sweep it.** This step runs on every weekly invocation, including a week with no new bumps. Find the current tag's open consolidation PR:

    ```
    gh pr list --head release/dependabot-<tag> --base <BASE_BRANCH> --state open \
      --json number,createdAt,title,body
    ```

    If it is open and **6 or more days old** (one day of margin under the roughly weekly auto-close window; tune this if you learn the real window), refresh it. GitHub forbids two open PRs from the same head branch, so do it in this order:
    - a. Comment on the old PR, then close it: "Closing to refresh as a new PR and reset the stale-PR auto-close clock; replacement opening now." `gh pr close <old>`. (Closing a PR does NOT delete the release branch; the no-delete hard rule still holds.)
    - b. Open the replacement from the same branch, carrying the body forward and noting the lineage:
      `gh pr create --head release/dependabot-<tag> --base <BASE_BRANCH> --title 'DANGER | Dependabot consolidation (<tag>)' --body '<carried-forward body>\n\nRefresh of #<old>, reopened fresh to avoid the stale-PR auto-close.'`
    - c. A brand-new PR resets both the created and updated timestamps, so the staleness clock starts over. Record the `<old> -> <new>` swap for the report.

    If the PR is younger than the threshold, leave it in place; just keep its body current (step 1). Never close a PR that is mergeable and about to be reviewed for any reason other than this refresh.

3. **Never merge to `<BASE_BRANCH>`.** Leave the consolidation PR open for human review.

4. **Critical escape hatch:** if a security/critical bump must reach `<BASE_BRANCH>` ahead of the batch, run it alone through Phases 1-3 on `release/dependabot-critical-<tag>`.

5. **Stragglers from prior months:** if an earlier month's consolidation PR (`release/dependabot-<older-tag>`) is still open and unmerged, do not silently keep it alive forever, and do not let it rot either. This routine actively refreshes only the *current* tag's PR; surface any older open consolidation PR in the report as needing human action.

End every run with a short report: repo, PRs found, fixed, merged into the release branch, held out, the consolidation PR link, whether it was refreshed this run (`<old> -> <new>` PR number, and why), and any prior-month consolidation PRs still open that need human attention.

## Ecosystem gotchas (reference)

These are optional, hard-won hints, NOT required per-repo config. Step 0.5 resolves a repo's config on its own; consult the matching stack here for known traps, and pass the relevant note to each Phase 1 fix agent. When a run discovers a new trap, add it here (and, for a repeatedly-run repo whose green gate was ambiguous, the gate cache from Step 0.5 already remembers the command).

### Gradle / Java (e.g. my-service: `./gradlew test --rerun-tasks`, base `main`)
- A Maven or Docker base-image major bump can overshoot the JDK that Gradle can run on. Keep the intended upgrade but pin the builder JDK (e.g. temurin-21).
- A Gradle major bump can force a Sonar-plugin bump plus an explicit JUnit Platform launcher dependency that lives in no single Dependabot PR. These surface only on the combined release-branch re-verify (Phase 2 step 3).

### npm / legacy Next.js + React (e.g. myrepo: `npm ci && npm run build && npm test`, base `master`)
- On a legacy stack (e.g. Next 9.4.2, React 16.13.1) Dependabot majors overshoot it (next -> 14, react -> 18, uuid -> 14 which is ESM-only). Keep the security intent but pin to a version compatible with the pinned framework rather than taking the major. The jest suite is often thin, so `next build` is the real green gate: most bump breakage shows at build, not in tests.
- A `git+ssh://git@github.com/<org>/<pkg>.git` dependency (e.g. `@myorg/internal-lib`) makes `npm ci` need SSH access to github.com. Failures fetching it are infra noise, not code: retry, never edit code to chase it.
- The same package can arrive as two conflicting Dependabot PRs targeting different versions (e.g. axios 0.27.2 -> 0.32.0 vs -> 1.16.1). Dedup in Phase 0: pick one target, close the other. A widely-used lib taking a major (axios via the hooks layer) needs real validation.

### Mixed root vs subproject (the green-gate ambiguity trap)
- Some repos have one build system at the root and bumps in a different ecosystem inside subprojects (e.g. a Gradle root with npm bumps under `client/*`). Root auto-detection is wrong here; this is exactly the Step 0.5 ambiguity guard. Resolve the real gate (often a per-changed-subdirectory `npm ci && npm run build && npm test`) once, and it is cached for later runs.

## Run logging (visibility)

When this run finishes (success, partial, nothing-to-do, or failure), call the **a_sag_routine_logger** sub-agent once (Agent tool, `subagent_type: a_sag_routine_logger`) with `routine=<this skill's name from the frontmatter above>`, a `status`, and a one-line `summary` of what the run did. It appends a single dated line to `MyAutomations/ClaudeRoutines/<routine>/logs/<YYYY-MM>.md`, so the last run and what it did are visible at a glance. Keep the summary to ONE line. Logging is best-effort: if the mdnest CLI is unavailable (e.g. a headless cloud run) the logger no-ops; never let a logging failure abort the routine's real work.

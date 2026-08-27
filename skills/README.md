# Skills

Source of truth for portable Agent Skills used by Claude Code, Codex, and Gemini/AGY.
Each skill is a directory here, symlinked into `~/.claude/skills/` and `~/.agents/skills/` by
`install.sh`, so editing a file here updates every provider with no copied files to drift.

The symlink model, compatibility boundaries, and full naming glossary live in
[`AGENTS.md`](../AGENTS.md) and [`docs/multi-agent.md`](../docs/multi-agent.md).

**Naming, in one line:** `a_sk_<name>` is an on-demand skill; `a_r_<name>` is a routine that can
run in the cloud; `a_r_l_<name>` is a routine that must run locally. `l_` applies to routines
only, because a routine is the one kind that could run somewhere other than this machine. Never
write `a_sk_l_*`.

Routines are **parameterized** so a scheduled prompt can fill in the blanks, for example
`run a_r_l_dependabot_collector for repo=my-service`.

## Managing your agent setup

| Skill | What it does |
|-------|--------------|
| `a_sk_setup_agents` | Install or update the devkit across Claude Code, Codex, and Gemini/AGY, verify shared skills and generated guidance, and keep provider-specific boundaries explicit. |
| `a_sk_setup_claude` | Wire this machine's Claude to the devkit: detect the machine's state, run the installer, verify every link resolves, teach the global `CLAUDE.md` what it now has, and offer the overlay and brain layers. |
| `a_sk_tame_claude` | Turn a messy, unmanaged `~/.claude` into a managed one: audit every loaded file, adopt what is worth keeping into a repo, delete the dead, repair broken links, shrink a bloated `CLAUDE.md`, and scaffold a private brain repo. |
| `a_sk_teach_claude` | The self-learning loop. Take what a session taught you and record it in the right layer (brain / rules / skill), dated and committed, dropping what is not worth keeping. |

Background for all three: [`docs/managed-claude.md`](../docs/managed-claude.md).

## Routines (`a_r_` / `a_r_l_`)

| Skill | Runs | What it does |
|-------|------|--------------|
| `a_r_l_dependabot_collector` | local | A repo's open Dependabot PRs: fix red bumps to green, flag risky ones, batch the rest onto the current month's release branch, keep one consolidated PR open for review. Runs weekly onto a monthly release; refreshes the PR (new one, close old) so the org stale-PR auto-close can't sweep it. Param: `repo`. |
| `a_r_l_pr_review` | local | Review GitHub PRs in an isolated worktree with parallel agents, on a `review/pr-<N>` branch that tracks the PR source. Params: `repo`, `pr` (number / `mine`). |
| `a_r_l_staging_qa_sweep` | local | Unattended staging smoke-test that files only confirmed, reproducible bugs to a Jira epic (settle-and-reproduce gate, dedup-first). Params: `flow_skill`, `base_url`, `epic`. |
| `a_r_l_weekly_status_report` | local | Reconcile a task-flow workspace against real merge state, then generate the weekly report off the corrected state. Params: `workspace_dir`, `audience`, `report_dest`. |
| `a_r_l_worktree_cleaner` | local | Clean up one repo's git worktrees safely: remove only the provably-done ones (branch merged, PR merged, or remote branch gone with nothing unpushed), prune stale registrations, never touch the main checkout or anything with real work. Params: `dir`, `dry_run`, `force`. |

## On-demand skills (`a_sk_`)

| Skill | What it does |
|-------|--------------|
| `a_sk_message_writer` | Draft / sharpen professional work messages (Slack, email, escalations) from a VP of Engineering standpoint. |
| `a_sk_routine_instruction_writer` | Turn a rough task description into a clean, self-contained instruction prompt for an autonomous or scheduled routine. |
| `a_sk_review_pr` | Review a GitHub PR end-to-end from just its URL: resolve the repo to your existing local clone (cache, then a `cd_w` scan, never a duplicate clone, via `scripts/a_s_resolve_repo`), worktree the PR's real head branch updated to latest, run the project's `review-pr` (or the global `global-pr-reviewer`), auto-post the bar-clearing comments, then tear the worktree and local branch down (remote never touched). Params: `pr` (URL / `owner/repo#N`), `post`, `reviewer`. |
| `a_sk_commit` | Turn the current changes into a clean, convention-matching git commit (delegates the message to `a_sag_commit_writer`). |
| `a_sk_pr` | Open a GitHub PR for the current branch, filling the project's PR template (via `a_sag_pr_writer`), correct base, right permission posture. |
| `a_sk_sonarqube_coverage` | Drive new-code test coverage up to the SonarQube / CI gate: find the coverage command, test the uncovered changed lines in the project's testing style, re-run until green. |

## Adding a skill

1. Create `skills/<name>/SKILL.md` with YAML frontmatter `name` (must equal the directory name)
   and `description`. Write the description so the skill actually triggers: say what it does
   **and** when to use it, including the phrasings someone would really type.
2. Add supporting files alongside it (`references/`, `scripts/`, `evals/`).
3. If it genuinely depends on Claude-only paths or APIs, add `providers: claude` to its
   frontmatter. Portable is the default.
4. Run `./install.sh --link-only` (or `a_c_skills install <name>` for Claude only).
5. Commit. The installer auto-discovers any directory here containing a `SKILL.md`.

## Not in this repo

- **Personal-life skills** (OLX hunter, PSX advisor, the AI / Claude trackers, session digest,
  mdnest fix) live in a private personal overlay that reuses this repo's installers via
  `CLAUDE_SKILLS_SRC` / `CLAUDE_AGENTS_SRC`. Nothing is duplicated, and this repo stays generic
  and publicly shareable.
- **Work-specific skills** live in a private org overlay, same arrangement.
- **Runtime artifacts** (`*-workspace/`, `opt-results/`, `opt-report.html`, `opt-loop.log`) are
  gitignored.
- **Other systems' skills** are deliberately absent: framework skills installed from another
  source, marketplace skills symlinked from `.agents/skills` (`find-skills`, `sonarqube-fix`),
  and plugin-namespaced (`plugin:skill`) entries.

---
name: a_sk_setup_claude
providers: claude
description: Install agentic-devkit into this machine's Claude Code setup, guided rather than blind. Detects what is already here, runs the installer, verifies every skill and agent link resolves, turns the global ~/.claude/CLAUDE.md into a generated file (via a_c_claude_memory) so Claude knows what it now has and how to spawn the agents, gives the machine a name and identity it can introduce itself with, and offers to add private overlays and a private brain. Use for "install the devkit", "set up my Claude", "hook this repo into my Claude Code", "wire agentic-devkit on this machine", "new laptop, get my Claude working", or when someone has just cloned or forked the repo and asks what to do next. Verifies instead of assuming, and never overwrites hand-written config. Local (needs the filesystem, git, and ~/.claude).
---

# a_sk_setup_claude — wire this machine's Claude to the devkit

`./install.sh` already does the mechanical part: symlink every skill and agent into `~/.claude`,
wire the shell once. This skill is the part a script cannot do. It works out the state of the
machine first, runs the right thing, then **proves** the result and teaches Claude what it now
has.

Read `docs/managed-claude.md` for the model. Do not restate it here; link to it.

**Never** hand-copy a skill or agent into `~/.claude/`. Everything is a symlink into a repo.

## Step 1 — find out where you are

Run these before deciding anything.

```bash
REPO="$(git rev-parse --show-toplevel)"          # the devkit checkout you are in
echo "MY_WORKFLOW_DIR=${MY_WORKFLOW_DIR:-<unset>}"
ls -d ~/.claude 2>/dev/null || echo "no ~/.claude yet"
ls ~/.claude/skills ~/.claude/agents 2>/dev/null | head -50
command -v a_c_skills a_c_agents 2>/dev/null
```

Classify the machine into exactly one case and say which one you picked:

| Case | What you see | What to do |
|---|---|---|
| **Fresh** | no `~/.claude/skills`, `MY_WORKFLOW_DIR` unset | full install (step 2) |
| **Partial** | devkit links exist but `MY_WORKFLOW_DIR` unset, or new skills unlinked | full install; it is idempotent |
| **Moved** | links exist but point at a different or missing path | full install with `-f`, then re-verify |
| **Messy** | real (non-symlink) dirs or files sit in `~/.claude/skills` or `agents/` | **stop. Run `a_sk_tame_claude` first**, then come back |

If Claude Code has never run on this machine, `~/.claude` may not exist. The installer creates
what it needs; do not pre-create directories by hand.

## Step 2 — dry run, then install

Always show the dry run before changing anything. It is cheap and it catches a wrong
`MY_WORKFLOW_DIR` before it is written to a shell rc.

```bash
./install.sh -n          # preview: shows shell wiring + every link it would make
./install.sh             # do it
./install.sh -f          # only if step 1 found links pointing elsewhere
```

What it does, so you can explain it if asked:

1. **Shell** (once per machine): creates `~/my_settings/configs.profile` from the sample with
   `MY_WORKFLOW_DIR` pointed at this checkout, and appends one guarded `source` line to
   `~/.zshrc` or `~/.bashrc`. It never overwrites an existing config and never rewrites the rc.
2. **Claude**: `a_c_skills install` + `a_c_agents install`, symlinking every `skills/<dir>` with a
   `SKILL.md` and every `agents/*.md` into `~/.claude/`.

If a real directory already sits at a link target, the installer compares it: identical content
is replaced with a link, divergent content is backed up to `~/.claude/skills.backups/` (or
`agents.backups/`) first. Nothing is silently lost. If you see a backup line in the output, tell
the user the path and what was in it.

## Step 3 — verify (do not skip, do not assume)

A successful installer run is not proof. Check the links actually resolve:

```bash
# every managed link resolves?
for d in skills agents; do
  for f in ~/.claude/$d/*; do
    [ -L "$f" ] && [ ! -e "$f" ] && echo "BROKEN: $f -> $(readlink "$f")"
  done
done
echo "(no BROKEN lines above = clean)"

a_c_skills status        # per-skill link state
a_c_agents status        # per-agent link state
```

A broken link means the skill is simply gone from Claude with no error anywhere. That is the
failure this step exists to catch.

Then confirm the counts match the repo:

```bash
ls -d skills/*/ | wc -l          # skills in the repo
ls agents/*.md | grep -vc README # agents in the repo
```

Report the numbers. If they do not line up with `a_c_skills status`, find out why before moving
on.

## Step 4 — teach the global CLAUDE.md what it now has

The installer links files. It does not tell Claude they exist. **Do not hand-write that block.**
`a_c_claude_memory` owns the global rules file now: it composes the managed region from sources
in git (`memory/core-rules.md` here, plus machine identity / personal rules / glossary from a
private overlay). An older version of this skill wrote a `agentic-devkit hint` block by hand;
the build absorbs and removes it.

```bash
a_c_claude_memory status   # sources found, region present, in sync?
a_c_claude_memory diff     # exactly what the build would add or change
a_c_claude_memory build    # write it
```

Rules that still matter, and that the command enforces for you:

- **Show the diff before the first build.** Adopting an existing hand-written rules file keeps
  that text verbatim below the generated region, but the user should see it, not be told.
- **Never touch anything outside the markers.** Everything outside is hand-written and theirs,
  including another tool's managed block.
- **Short.** This file loads on every single request. Anything long belongs in a repo doc or the
  brain, reached by a pointer.

If the machine has no overlay yet, the build still works — it renders the core rules and the
pointers. Offer the overlay in step 6, then rebuild so the machine gets an identity and a
glossary.

To give this machine a name it can introduce itself with, set `A_MACHINE_NAME`,
`A_CLAUDE_OVERLAY_DIR`, and `A_CLAUDE_BRAIN_DIR` in `~/my_settings/configs.profile`, then create
`<overlay>/machine/<A_MACHINE_NAME>.md`. See `docs/managed-claude.md`.

## Step 5 — make the agents actually reachable

The point of installing is that these get spawned without ceremony. Confirm the user knows all
three ways in, and show real names from `agents/README.md` rather than placeholders:

- **By description.** Agents trigger on what they are for. "review this before I commit" reaches
  `a_sag_code_reviewer` with no name typed.
- **By name.** "use `a_sag_debugger` on this failing test".
- **In parallel.** Several agents in one message run at once; say so, because most people never
  try it.

Then run one live check so it is proven, not promised. Spawn a cheap read-only agent, for
example `a_sag_codebase_explorer` on a small directory, and confirm it returns. If agents are
not loading, the usual cause is that Claude Code has not restarted since the links were made.

## Step 6 — offer the layers, do not force them

Ask, then act. Do not create repos unprompted.

1. **A private overlay** for anything that must not be public (work-specific or personal-life
   skills). It is thin: its own `skills/`, `agents/`, and an `install.sh` that reuses this repo's
   installer through `CLAUDE_SKILLS_SRC` / `CLAUDE_AGENTS_SRC`. Never a second installer.
2. **A private brain** for knowledge rather than capability. If the user has ever re-explained
   the same project background to Claude twice, they want one. Hand off to
   `a_sk_tame_claude`, which scaffolds it properly.

## Step 7 — report

State plainly:

- Which case the machine was (fresh / partial / moved), and what changed.
- Counts: N skills, M agents linked. Zero broken links (or the exact ones still broken).
- Whether the shell needs activating. A script cannot change the calling shell, so if the rc was
  just wired, the user must run `source ~/.zshrc` themselves. Say the exact command.
- **Restart Claude Code** to load new skills and agents. Say this every time; a freshly linked
  skill will not appear in the running session.
- Anything backed up, with its path.
- What was offered and declined, so the next session knows not to re-ask.

## Failure modes worth naming

| Symptom | Cause | Fix |
|---|---|---|
| Skill missing, no error | broken symlink after a repo move or rename | `./install.sh -f`, then re-verify |
| `a_c_skills: command not found` | shell not sourced yet in this terminal | `source ~/.zshrc`, or call `scripts/a_c_skills` by path |
| Overlay installer refuses to run | core not installed, so `a_c_skills` is not on PATH | install the core first |
| Edits to a skill do nothing | edited a stale copy in `~/.claude/`, not the repo | delete the copy, re-link, edit the repo |
| New skill absent after `git pull` | installer not re-run | `./install.sh --link-only` |
| Skill still absent after install | Claude Code not restarted | restart it |

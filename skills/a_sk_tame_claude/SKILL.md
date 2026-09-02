---
name: a_sk_tame_claude
providers: claude
description: Turn a messy, unmanaged ~/.claude into a managed one that lives in git. Audits every file Claude loads (CLAUDE.md, skills, agents, commands, settings, hooks, MCP), classifies each as managed, adoptable, or junk, then adopts what is worth keeping into the right repo, deletes what is dead, repairs broken symlinks, and rewrites a bloated global CLAUDE.md into a short set of rules that point at real sources, and converts it from a hand-typed file into one generated from git (machine identity, personal rules, glossary) via a_c_claude_memory. Also recommends and scaffolds a PRIVATE GitHub brain repo (my_private_brain or a name the user picks) for durable knowledge (glossary, decisions, people, conventions) and wires it in, so memory stops living in one long file. Use for "my Claude config is a mess", "clean up ~/.claude", "make my Claude setup managed", "audit my Claude memory", "my CLAUDE.md is too long", "set up a second brain for Claude", "I keep re-explaining my projects to Claude", "organize my Claude skills", or after moving/renaming a repo that Claude links into. Never deletes without showing the user first. Local (needs the filesystem, git, and ~/.claude).
---

# a_sk_tame_claude — unmanaged Claude in, managed Claude out

An unmanaged `~/.claude` is a folder of hand-written files that nobody remembers writing, some of
which are still true. This skill turns it into a set of git repos plus symlinks, and gives the
knowledge in it a real home.

Read `docs/managed-claude.md` first. It defines managed vs unmanaged, the four layers, the brain
layout, and the health rules. This skill is the procedure; that doc is the model. Do not restate
it.

## Non-negotiables

1. **Back up before the first change.** `cp -R ~/.claude ~/.claude.backup.$(date +%Y%m%dT%H%M%S)`
   excluding the big runtime dirs. Tell the user the path.
2. **Show before you delete.** Print the exact list and get a yes. Never batch-delete on
   inference.
3. **Content is never lost.** Anything removed from `~/.claude` was first copied into a repo, or
   the user explicitly said to drop it.
4. **Do not touch runtime state.** `projects/`, `sessions/`, `history.jsonl`, `todos/`,
   `shell-snapshots/`, `file-history/`, `telemetry/`, `security/`, `session-env/`, `paste-cache/`,
   `statsig/`, `.credentials.json`. These are Claude Code's own; they are not config and are not
   yours to reorganize.
5. **Leave other tools' managed blocks alone.** If a `CLAUDE.md` block is marked auto-generated
   by another installer, keep it verbatim inside its markers.

## Phase 1 — audit

Take inventory before proposing anything.

```bash
cd ~/.claude
echo "=== global memory ==="
wc -l CLAUDE.md 2>/dev/null; ls -la CLAUDE.local.md 2>/dev/null
echo "=== skills ==="
for f in skills/*; do
  if   [ -L "$f" ] && [ -e "$f" ]; then echo "LINK-OK   $(basename "$f") -> $(readlink "$f")"
  elif [ -L "$f" ];                then echo "LINK-DEAD $(basename "$f") -> $(readlink "$f")"
  else                                  echo "REAL      $(basename "$f")"; fi
done
echo "=== agents ==="
for f in agents/*.md; do
  if   [ -L "$f" ] && [ -e "$f" ]; then echo "LINK-OK   $(basename "$f")"
  elif [ -L "$f" ];                then echo "LINK-DEAD $(basename "$f") -> $(readlink "$f")"
  else                                  echo "REAL      $(basename "$f")"; fi
done
echo "=== other config ==="
ls commands/ 2>/dev/null; ls *.json 2>/dev/null; ls *.md 2>/dev/null
```

Then put **every** item into exactly one bucket. Show this as a table before doing anything.

| Bucket | Means | Action |
|---|---|---|
| **Managed** | symlink into a git repo, resolves | leave alone |
| **Broken** | symlink whose target is gone or moved | repoint or remove (phase 2) |
| **Adoptable** | real file/dir with content worth keeping | move into a repo, replace with a link (phase 3) |
| **Foreign** | installed and owned by another tool | leave alone, list it so the user knows |
| **Junk** | empty, a duplicate, a workspace artifact, or superseded | propose deletion (phase 5) |

Judging **adoptable vs junk** is the actual work. Read the file. Ask:

- Does it duplicate something already managed? Diff them. If identical, it is junk. If it
  diverged, the local edit may be the better version. Show the diff and ask.
- Is it a runtime artifact? `*-workspace/`, `opt-results/`, `*.log`, `.DS_Store` are junk.
- Is it empty or a stub with only frontmatter? Junk.
- Does it reference paths, hosts, or tools that no longer exist? Show it and ask before keeping.

**Broken links deserve a specific check.** The common cause is a renamed or moved repo
directory. Before removing a dead link, look for the target's new home:

```bash
# a link pointing at .../repos/<old-name>/skills/<x> when the repo was renamed
readlink ~/.claude/skills/<x>
ls -d "$(dirname "$(dirname "$(readlink ~/.claude/skills/<x>)")")"/../* 2>/dev/null
```

If the repo just moved, repointing is right and deleting is wrong. Re-run that repo's
`install.sh -f` rather than fixing links by hand.

## Phase 2 — repair what is only broken

Fix the cheap things before any restructuring, because they change the picture.

```bash
# for each repo that owns links: re-link from source
cd <repo> && ./install.sh -f

# verify nothing dead is left
for d in skills agents; do
  for f in ~/.claude/$d/*; do
    [ -L "$f" ] && [ ! -e "$f" ] && echo "STILL BROKEN: $f -> $(readlink "$f")"
  done
done
```

If a repo no longer exists anywhere, that is a removal, not a repair. It goes in the phase 5
list.

## Phase 3 — adopt the real files into repos

For each adoptable item, route it with the rule in `docs/managed-claude.md`: work-specific to the
org overlay, personal-life to the personal overlay, everything else to agentic-devkit (the
default).

If the user has no repo for the layer an item needs, offer to create one rather than dumping it
in the wrong place. An overlay is small: `skills/`, `agents/`, `README.md`, and an `install.sh`
that reuses `a_c_skills` / `a_c_agents` via `CLAUDE_SKILLS_SRC` / `CLAUDE_AGENTS_SRC`. Copy the
shape from the existing overlay pattern; do not write a second installer.

Adoption for each item:

1. `git mv` or copy the file into `<repo>/skills/<name>/` or `<repo>/agents/<name>.md`.
2. Bring it up to house convention: rename to the `a_sk_*` / `a_r_*` / `a_sag_*` scheme, make the
   frontmatter `name:` match the directory or filename, and write a `description:` that actually
   says when to trigger. A skill with a vague description never fires and is dead weight.
3. Remove the original from `~/.claude`.
4. Re-run the repo's installer so a link replaces it.
5. Commit in that repo, with that repo's identity.

Do them one at a time and verify. A half-adopted skill (moved but not linked) is worse than one
left alone.

## Phase 4 — tame the global CLAUDE.md

This file loads on every request, so length is a real cost. Most unmanaged ones are long because
knowledge was written where rules belong.

**Sort first, then write to sources, not to the file.** The end state for this file is
*generated*: `a_c_claude_memory` composes a managed region from sources in git. So the output of
this phase is edits to those sources plus one `a_c_claude_memory build` — not a hand-edited
`~/.claude/CLAUDE.md`, which the next build would overwrite anyway.

| A rule that is... | Goes to |
|---|---|
| generic to any machine running the devkit | `agentic-devkit/memory/core-rules.md` |
| personal, always-on | `<overlay>/machine/rules.md` |
| about this machine (name, role, what runs here) | `<overlay>/machine/<A_MACHINE_NAME>.md` |
| a term whose meaning implies an action | `<overlay>/machine/glossary.md` |

Then `a_c_claude_memory diff`, show it, and `build`. Hand-written text outside the markers is
preserved, so anything you have not routed yet survives the transition — but say what is left
unrouted rather than leaving it silently.

If the machine has no overlay, the sorting below still applies; park personal rules in the
hand-written zone and offer to create an overlay (phase 3).

Read it line by line and sort every paragraph:

| Kind | Example | Where it goes |
|---|---|---|
| **Rule** | "never use em dashes", "never auto-post to Slack" | stays. This is what the file is for. |
| **Pointer** | "the glossary is at X, read it when Y" | stays, but as two lines, not twenty. |
| **Knowledge** | project lists, key mappings, who owns what, decisions | **move to the brain** (phase 6). Leave a pointer. |
| **Procedure** | a multi-step how-to | **move to a skill**. Leave nothing; the skill self-triggers. |
| **Dead** | tools no longer used, paths that no longer exist, contradicted advice | delete, after showing it. |

Then fix the structure:

- **Real headings, in a stable order.** Rules first, pointers after.
- **One fact, one home.** If a rule appears twice, keep the better wording and delete the other.
  Duplicated rules drift and then contradict each other.
- **Contradictions get resolved, not kept.** If two lines disagree, ask which is current. Do not
  guess and do not keep both.
- **Managed blocks stay between their markers.** Yours too: put anything this skill generates
  between clear start/end markers so the next run can update it in place instead of appending.
- **Collapse dead whitespace.** Long runs of blank lines are a sign of blocks removed by hand.
- **Verify every path and name you leave in.** A pointer to a file that does not exist, or an
  agent name with a typo, is worse than no pointer: it sends future sessions to nowhere. Check
  each one:

```bash
grep -oE '(/[A-Za-z0-9._-]+)+' ~/.claude/CLAUDE.md | sort -u | while read -r p; do
  [ -e "$p" ] || echo "MISSING PATH: $p"
done
grep -oE '\ba_(sk|r|sag|c|g|s)_[a-z0-9_]+' ~/.claude/CLAUDE.md | sort -u | while read -r n; do
  ls -d ~/.claude/skills/"$n" ~/.claude/agents/"$n".md >/dev/null 2>&1 \
    || command -v "$n" >/dev/null 2>&1 \
    || echo "UNKNOWN NAME: $n"
done
```

Fix every hit. A wrong agent name in the rules file means every session tries to spawn something
that does not exist.

## Phase 5 — delete, with consent

Present the junk list as a table: path, size, what it is, why it is junk. Get an explicit yes.
Then delete, and confirm the backup path is still there.

Anything the user is unsure about goes to the backup and stays out of `~/.claude`, rather than
being deleted or left in place.

## Phase 6 — the private brain

Recommend this whenever you find knowledge in the rules file, or the user has ever
re-explained the same background twice. Make the case in one sentence: **a private brain is where
Claude keeps what it knows about your work, so it stops living in a file that gets longer every
month.**

Ask for a name. `my_private_brain` is a fine default; many people prefer
`<something>-brain`. It must be **private**: it will hold project names, people, and internal
decisions.

Set it up:

```bash
mkdir -p <path>/<name> && cd <path>/<name> && git init
mkdir -p Glossary Decisions People Conventions Learned current_work
gh repo create <name> --private --source=. --remote=origin   # if gh is available
```

Write the folders and the entry-point `CLAUDE.md` per the layout in `docs/managed-claude.md`.
The entry point is the part that matters: it tells a session which folder answers which kind of
question, so Claude does not have to read the whole brain or guess.

**Seed it from what you already have.** Do not hand back empty folders. Everything you moved out
of the global `CLAUDE.md` in phase 4 goes in now, sorted into the right folder. Then mine the
session for more: project names the user has mentioned, repo-to-tracker mappings, people, stated
preferences. Ask before writing anything you inferred rather than were told.

Then wire it into the global `CLAUDE.md` with a short section that:

- names the absolute path,
- says to read the brain's own `CLAUDE.md` first,
- says to **skip silently** if the path is missing, so an unmounted volume or a second machine
  never blocks a session,
- says to **write back** when something durable is learned, naming `a_sk_teach_claude`.

That last line is what makes the setup self-learning. Without it the brain is written once and
rots.

If the user already has a brain, do not create a second one. Audit the one they have: does it
have an entry-point `CLAUDE.md`? Are the folders sorted by question type? Is the global file
pointing at it correctly? Fix those instead.

## Phase 7 — verify and report

```bash
# every skill and agent is a resolving symlink
for d in skills agents; do
  for f in ~/.claude/$d/*; do
    [ -L "$f" ] || echo "UNMANAGED (real file): $f"
    [ -L "$f" ] && [ ! -e "$f" ] && echo "BROKEN: $f"
  done
done
wc -l ~/.claude/CLAUDE.md
git -C <each repo> status --short
```

Report:

- Before and after: file counts, and `CLAUDE.md` line count before vs after.
- What was adopted, and into which repo.
- What was deleted.
- Any repo left with uncommitted changes, and the command to commit it.
- Whether a brain was created or improved, and its path.
- **Restart Claude Code.** Say it explicitly.
- Remaining unmanaged items you deliberately left, and why, so the next run does not re-litigate
  them.

## When not to use this

- The setup is already managed and only needs new links: use `a_sk_setup_claude`.
- One fact needs recording: use `a_sk_teach_claude`.
- The user wants a specific skill written: write the skill; do not restructure their machine.

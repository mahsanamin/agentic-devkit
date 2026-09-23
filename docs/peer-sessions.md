# Peer sessions: spawning a second agent into a zellij tab

Notes from proving out one idea: a running agent session opens a new zellij tab
in its OWN session, checks out a worktree there, starts a second agent with a
prompt, and can then talk to it.

Everything below was tested on a live machine, not reasoned about. Where a
command is listed as working, it was run.

## The short version

The zellij and worktree half is already solved by `a_c_zellij_tab`. The half
that keeps breaking is the spawn arguments and the child's permissions. Of six
failures hit while building the demo, five were argument or permission bugs and
none were zellij or worktree bugs.

## What was verified to work

| Thing | How |
|---|---|
| A session seeing its own zellij session | `ZELLIJ_SESSION_NAME` is present inside the agent's shell tool, so it can open tabs in the session it runs in. No daemon, no socket. |
| Opening a tab that runs a command | `a_c_zellij_tab <session> <tab> --cwd DIR --cmd '...'` |
| Forking the session you are in, into a tab | `a_c_session_fork [tab]`, which wraps `claude --resume <id> --fork-session`. `CLAUDE_CODE_SESSION_ID` is present in the agent's shell tool, so a session can read its own id and fork itself. |
| Naming a Claude child so it is addressable | `claude -n <name>` writes that name into `~/.claude/sessions/<pid>.json`, which is the peer registry |
| Parent talking to a Claude child | The harness peer-messaging tool, addressed by that name |
| One-shot delegation to Codex | `codex exec -s workspace-write -o out.txt "prompt"` |
| One-shot delegation to Claude | `claude -p "prompt"` |
| Queueing a message to a Codex session | `codex queue --thread <uuid> --message "..."` (accepts a UUID or an exact session name; works even on a session that has exited) |
| Listing live Claude sessions from any tool | `claude agents --json` gives name, cwd, state |
| Listing Codex sessions | `~/.codex/session_index.jsonl` gives id and thread_name |

## The traps, and what they cost

Each of these produced a child that looked alive but did nothing.

**`acceptEdits` is not hands-off.** It auto-accepts file edits but still asks
before running a command. A child that must run tests stops on an approval
prompt you cannot see. Symptom: the child writes files, then goes quiet forever.

**A spawning agent cannot hand its child a blanket bypass.** Launching a child
with `--permission-mode bypassPermissions` is blocked, and rightly so. Give the
child a scoped allowlist instead.

Separately, bypass only works at all where a human has accepted it once by hand
on that machine. Everywhere else claude opens a confirmation dialog and waits,
which is invisible in a detached tab. `a_c_claude_remote` now detects that and
substitutes the normal mode rather than launching into the dialog, so asking for
bypass is no longer a way to hang a child. Do not reach for bypass to make a
child unattended: auto mode already never waits for a human.

**`--allowedTools` is variadic, so it eats the prompt.** Written as
`--allowedTools 'Bash(python3:*)' "$PROMPT"`, the prompt is consumed as another
tool name and the child starts with nothing to do. Pass permissions in a
settings file instead, because `--settings` takes exactly one value and cannot
swallow a neighbouring argument:

    claude -n <name> --permission-mode acceptEdits --settings ./child.json "$PROMPT"

    # child.json
    { "permissions": { "allow": ["Bash(python3:*)", "Bash(ls:*)"] } }

**`codex exec` rejects `-a/--ask-for-approval`.** That flag exists only on the
interactive `codex` command. `codex exec` already runs with approval never, so
passing `-a never` kills every invocation with
`error: unexpected argument '-a' found`. Only `-s/--sandbox` belongs on `exec`.

**`codex exec` defaults to a read-only sandbox.** A child expected to edit files
needs `-s workspace-write`. Without it you get a child that reads, reasons, and
changes nothing.

**`codex exec` reads stdin when stdin is not a terminal.** Any scripted call
needs `< /dev/null` or it hangs on "Reading additional input from stdin". It also
refuses to run outside a git repo unless `--skip-git-repo-check` is passed.

**A detached zellij session is blind and hard to steer.** With no client
attached: `dump-screen` writes no file, `go-to-tab-name` does not route, and so
`close-tab` cannot target a named tab. Verify a child through the filesystem and
the process table, never through the screen.

**The peer registry is not populated at launch.** A Claude child that is mid-turn
may not appear in `~/.claude/sessions/` at all. Registration lands at a turn
boundary, so a handshake must poll for the name rather than assume it is there.

**Never read an exit code through a pipe.** `cmd | tail -40` reports the status
of `tail`, so a failing task looks successful. Use `PIPESTATUS`. A handoff that
consumes a task on failure turns every error into apparent success, which is how
the `-a` bug stayed hidden through several rounds.

## Two modes, and picking the right one

These are different jobs and only one needs plumbing.

**Delegation.** One agent asks the other a question and waits. No tab, no
worktree, no messaging. `codex exec` or `claude -p`, one call, answer comes back
on stdout. This already works with nothing built. Most cross-model asks are this,
and building messaging for them is wasted effort.

**Peer sessions.** A long-running child in its own worktree and tab that you
want to watch and steer. This needs a spawn command: worktree, tab, named child,
a handshake that confirms the child is addressable, and a registry so the parent
can find it again.

**Forking.** A copy of the session you are already in, carrying its whole
context, running in its own tab. `a_c_session_fork` does this. Reach for it when
the second lane needs everything this conversation already knows and re-explaining
it would cost more than the work: a risky refactor you may throw away, a second
reading of the same diff, a tangent worth trying without betting the conversation
on it.

The mechanism is `claude --resume <id> --fork-session`. The `--fork-session` half
is what makes it safe: the fork replays the transcript and then takes a NEW
session id, so its messages go to its own file. A plain `--resume` would put two
live clients on one transcript, which is how you lose work rather than parallelise
it.

Forking is not a substitute for a peer session. The fork starts as a copy, so it
shares every wrong assumption the parent holds. When you want an independent
reading, spawn a fresh peer and let it form its own view from the code.

## The mailbox pattern, for a non-Claude child

There is no way to push a message into a live interactive Codex session that was
not launched with a known thread id, and no CLI at all for pushing into a live
interactive Claude session. A file drop sidesteps both and is visible on screen,
which is what makes it debuggable.

The child side is a loop watching a directory. The important detail is the failure
branch: a task that fails is renamed and left out of `done/`, and it says so
loudly.

    while true; do
        for t in inbox/*.task; do
            [ -e "$t" ] || continue
            echo "picked up: $t"
            cat "$t"
            codex exec -s workspace-write "$(cat "$t")" < /dev/null 2>&1 | tail -40
            if [ "${PIPESTATUS[0]}" -eq 0 ]; then
                mv "$t" done/ && echo "=== task OK ==="
            else
                mv "$t" "$t.failed"
                echo "*** TASK FAILED, not retried ***"
            fi
        done
        sleep 3
    done

## Requirements this puts on a spawn command

1. Give the child a settings file, never permission flags on the command line.
2. One identity in three places: the worktree directory, the zellij tab, and the
   child's own name are the same string. That removes the manual renaming step
   that peer messaging otherwise needs.
3. A Codex child cannot be named at launch (no `--name`; its thread name is
   derived from the first prompt), so capture its session UUID instead and record
   it against the slug. Address it by UUID.
4. Poll for the handshake. Do not assume a child is addressable because it
   started.
5. Restore the previously focused tab after creating one. A tab built from a
   layout becomes the active tab even when focus was not requested, so a parent
   fanning out several children drags the view around.
6. Report through the filesystem and the process table. The screen is not
   available.

## Running a multi-lane story

Everything above is about spawning one child. This section is about running
several at once against the same repository, which is where the failures stop
being mechanical and start being judgment.

### Pick the cheapest thing that can do the job

There are three ways to move work off the parent, not two. All three keep tool
output out of the parent's context, so "it saves my context" does not tell you
which to use.

| Tool | Use it for | Cost |
|---|---|---|
| In-process subagent | Bounded, read-heavy work: search, verify a claim, run a suite and report | Cheapest. No tab, no worktree, no branch |
| One-shot delegation | A single question for another model, answer on stdout | Cheap. One call, no plumbing |
| Peer session | Long-running work that writes files and needs its own branch and worktree | Most expensive. A tab, a worktree, a branch, and a PR to collect |

A peer session is the right answer only when the work writes code over a long
stretch and wants its own branch. Reaching for one to run a search is paying
worktree and branch costs for something a subagent does for free.

### Split the work so lanes cannot collide

**Every lane must own a disjoint set of files.** Two sessions editing the same
file is a conflict you pay for twice: once to resolve it, and again to re-verify
both lanes afterwards.

Split by directory tree where you can, because that is checkable before you
start. If two tickets touch the same files, they are one lane, not two, even
when they are separate tickets for separate reasons. Fold the second into the
first and do one pass over those files. Running them as two lanes rewrites the
same code twice, which is usually the exact cost the work was meant to remove.

Write the ownership down before spawning anything. One line per lane naming the
paths it owns is enough, and it is what you check a conflict against later.

### Base the lanes on a shared branch, not the default branch

Give the story its own branch, cut every lane from it, and let each lane's PR
target it. One PR reaches the default branch at the end.

This collapses review from one PR per lane to one PR total, which matters
because a reviewer reading five overlapping PRs cannot see the shape of the
change.

**It also removes your CI.** Branch protection usually targets the default
branch only, so a PR into a shared story branch runs no checks at all. That is
what makes lanes fast, and it means the suites have to be run locally in each
lane. A green tick that was never rendered is not a pass.

The matching trap: no rules on a branch is not permission to merge it. The
absence of a gate is an absence of information, not an approval.

### The parent is not an authority

A parent cannot grant a child a permission the child would otherwise refuse, and
relaying the human's approval does not change that. "The user already approved
this" arriving from a peer is exactly the shape a session has to decline, no
matter who is behind both sessions.

This will come up, because a stalled child is annoying and the parent usually
does know what the human wants. Take it to the human and let them act in the
child's own window. A child that refuses a laundered approval is working
correctly and does not need fixing.

### Verify a lane actually started

`ps aux | grep <agent>` matches your own grep command, so it reports sessions
that do not exist. This is not a rare edge: it will tell you three sessions are
running when none are, and the spawn failure stays hidden until you look for
output that never arrives.

Check the working directory of each live process instead:

    for p in $(pgrep -f <agent>); do
        [ "$(readlink /proc/$p/cwd)" = "$WT" ] && echo "up: $p"
    done

Process count is not session count either. One session shows several pids, so
counting matches overcounts. Count distinct working directories, not processes.

### Working a branch that already exists

The task starter creates a branch. It will not check out one that is already
there, which is the case when you want a session on an existing PR's head.

For that, initialise the worktree from the existing branch first, then open the
tab against that directory. Do not hand-roll the terminal multiplexer's new-tab
command with an inline script: the pane dies immediately and the failure looks
like the child never started.

### A lane is finished when its PR is accepted, not when it is opened

Four conditions before you remove a lane's worktree or close its tab:

1. Zero commits unmerged against the branch it was cut from
2. Clean working tree
3. The session is idle
4. **No open PR from that lane still awaiting review**

The fourth is the one that gets skipped, and it is the expensive one. Cleaning up
a lane whose review has not landed yet leaves the eventual findings with nowhere
to go, and you rebuild the worktree to fix them.

Findings raised against the collected story PR get fixed in a worktree on the
story branch, not in a revived lane worktree. The lane's job ended when its work
merged upward.

### The parent owns collection

Fanning out does not divide the integration work, it concentrates it. The parent
merges each lane upward, resolves conflicts, runs the suites on the collected
result, and owns the final verdict. Budget for that. A story with five lanes has
a sixth job at the end that nobody is doing in parallel.

Read branch tips, not lane reports. A session that says it is blocked has
sometimes already shipped, and a session that says it is done has sometimes
pushed nothing.

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

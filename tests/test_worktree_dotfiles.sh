#!/usr/bin/env bash
#
# Behaviour fixture for a_s_copy_local_dotfiles, the rule that decides what travels
# from the main checkout into a new worktree.
#
# It matters because the failure is silent in both directions. Copy too little and the
# worktree will not run, which you find out in a minute. Copy too much and a file
# nobody meant to share rides into a branch, shows up in `git status` there, and is one
# `git add -A` away from a commit and a PR. The old loop copied every root dotfile, so
# it failed the second way every time somebody left a scratch file in the main clone.
#
# Falsification, since a fixture never seen failing is not evidence. Verified to FAIL
# when, in a_s_worktree_dotfiles.sh:
#   - the untracked branch copies instead of recording      (case: untracked stays)
#   - a skipped file inside a tracked directory goes unnamed (case: nested skip is silent)
#   - the check-ignore branch is dropped                    (cases: .env, .envrc)
#   - the tracked branch copies the whole directory         (case: no junk inside .claude)
#   - the partly-tracked recursion is removed               (case: settings.local.json)
#   - the denylist is emptied                               (case: .gradle)
#   - the denylist is split on "/" the bash-only way        (case: zsh nested denylist)
#   - --include-untracked is ignored                        (case: opt-in)
#
# Usage: bash tests/test_worktree_dotfiles.sh

set -uo pipefail

REPO_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
. "$REPO_ROOT/scripts/a_s_worktree_dotfiles.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf 'FAIL   %s\n' "$1"; }

# A main checkout with one of each kind of root dotfile.
SRC="$WORK/main"
mkdir -p "$SRC"
git -C "$SRC" init -q
git -C "$SRC" config user.email t@example.com
git -C "$SRC" config user.name Test

mkdir -p "$SRC/.claude" "$SRC/.github" "$SRC/.gradle/caches" "$SRC/.idea"
cat > "$SRC/.gitignore" <<'EOF'
.env
.envrc
.gradle/
.idea/
.claude/settings.local.json
.claude/.cache/
EOF
echo tracked          > "$SRC/.github/workflows.yml"
echo tracked          > "$SRC/.claude/settings.json"
echo "SECRET=1"       > "$SRC/.env"
echo "layout python"  > "$SRC/.envrc"
echo local            > "$SRC/.claude/settings.local.json"
echo cache            > "$SRC/.gradle/caches/big.bin"
mkdir -p "$SRC/.claude/.cache"
echo cache            > "$SRC/.claude/.cache/blob.bin"   # ignored, but still a cache
echo cache            > "$SRC/.idea/workspace.xml"
git -C "$SRC" add -A >/dev/null 2>&1
git -C "$SRC" commit -qm init

# The loose files land AFTER the commit, which is the situation being tested: someone
# left them in the main checkout and never committed them. Writing them earlier would
# put them in the commit, where they are tracked and the fixture proves nothing.
echo junk             > "$SRC/.claude/scratch-note.md"     # untracked, NOT ignored
echo "wip notes"      > "$SRC/.my-scratch"                 # untracked, NOT ignored

# The worktree as git leaves it: the committed tree, nothing else.
DEST="$WORK/wt"
mkdir -p "$DEST"
git -C "$SRC" worktree add -q --detach "$DEST" HEAD

echo "--- default: ignored local config travels, loose files do not ---"
out="$(a_s_copy_local_dotfiles "$SRC" "$DEST" 2>&1)"

[ -f "$DEST/.env" ]   && ok ".env copied (ignored local config)"   || bad ".env missing - the worktree cannot run"
[ -f "$DEST/.envrc" ] && ok ".envrc copied (ignored local config)" || bad ".envrc missing"
[ -f "$DEST/.claude/settings.local.json" ] \
  && ok "ignored file inside a tracked directory copied" \
  || bad ".claude/settings.local.json missing - partly-tracked directories are not handled"

[ -e "$DEST/.my-scratch" ] \
  && bad "untracked, non-ignored .my-scratch travelled into the worktree" \
  || ok "untracked, non-ignored root file stayed behind"
[ -e "$DEST/.claude/scratch-note.md" ] \
  && bad "untracked junk inside a tracked directory travelled (the cp -Rn merge)" \
  || ok "untracked junk inside a tracked directory stayed behind"

[ -e "$DEST/.gradle" ] && bad ".gradle cache copied" || ok ".gradle cache skipped"
# Nested: ignored, so the ignore branch would take it; denied, so it must not travel.
# This is the case a denylist that only looks at the top-level name gets wrong.
[ -e "$DEST/.claude/.cache" ] && bad "cache nested inside a tracked directory copied" \
                              || ok "cache nested inside a tracked directory skipped"
[ -e "$DEST/.idea" ]   && bad ".idea copied"         || ok ".idea skipped"

# The tracked content is git's to provide, and at the revision git chose.
[ -f "$DEST/.github/workflows.yml" ] && ok "tracked files present from the checkout" \
                                     || bad "checkout is missing tracked content"

case "$out" in
    *".my-scratch"*) ok "the skipped file is named in the output" ;;
    *)               bad "nothing told the user .my-scratch was left behind" ;;
esac
# The nested one has to be named too. A file skipped without a word is indistinguishable
# from a copy that failed, and the project it belongs to is the one that never gitignored
# its local settings.
case "$out" in
    *".claude/scratch-note.md"*) ok "the skipped file inside a tracked directory is named too" ;;
    *)                           bad "the nested skip was silent" ;;
esac

echo "--- a modified tracked file never travels ---"
echo "local edit" >> "$SRC/.github/workflows.yml"
DEST2="$WORK/wt2"; mkdir -p "$DEST2"
git -C "$SRC" worktree add -q --detach "$DEST2" HEAD
a_s_copy_local_dotfiles "$SRC" "$DEST2" >/dev/null 2>&1
grep -q "local edit" "$DEST2/.github/workflows.yml" \
  && bad "an uncommitted edit in the base checkout reached the worktree" \
  || ok "uncommitted edits to tracked files stay in the base checkout"

echo "--- --include-untracked is the opt-in ---"
DEST3="$WORK/wt3"; mkdir -p "$DEST3"
git -C "$SRC" worktree add -q --detach "$DEST3" HEAD
a_s_copy_local_dotfiles "$SRC" "$DEST3" --include-untracked >/dev/null 2>&1
[ -f "$DEST3/.my-scratch" ] && ok "--include-untracked takes the loose files" \
                            || bad "--include-untracked did not copy .my-scratch"
[ -f "$DEST3/.claude/scratch-note.md" ] && ok "--include-untracked reaches into tracked directories" \
                                        || bad "--include-untracked skipped the nested loose file"
[ -e "$DEST3/.gradle" ] && bad "--include-untracked also dragged in the cache denylist" \
                        || ok "--include-untracked still skips the cache denylist"

echo "--- a repo with no dotfiles at all ---"
BARE="$WORK/bare"; mkdir -p "$BARE"; git -C "$BARE" init -q
git -C "$BARE" config user.email t@example.com; git -C "$BARE" config user.name Test
echo hi > "$BARE/README.md"; git -C "$BARE" add -A >/dev/null; git -C "$BARE" commit -qm init
DEST4="$WORK/wt4"; mkdir -p "$DEST4"
git -C "$BARE" worktree add -q --detach "$DEST4" HEAD
a_s_copy_local_dotfiles "$BARE" "$DEST4" >/dev/null 2>&1 \
  && ok "no dotfiles is not an error" || bad "returned non-zero with nothing to copy"

echo "--- the same helper under zsh, which is what sources it interactively ---"
# Worth its own case: the helper is sourced into the user's login shell, and zsh does
# not word-split an unquoted expansion. A denylist written as a split-on-space string
# would check nothing there and pass every bash case above while copying every cache.
if command -v zsh >/dev/null 2>&1; then
    DEST5="$WORK/wt5"; mkdir -p "$DEST5"
    git -C "$SRC" worktree add -q --detach "$DEST5" HEAD
    zsh -c ". '$REPO_ROOT/scripts/a_s_worktree_dotfiles.sh'; a_s_copy_local_dotfiles '$SRC' '$DEST5'" >/dev/null 2>&1
    [ -f "$DEST5/.env" ] && ok "zsh: ignored local config copied" || bad "zsh: .env missing"
    [ -f "$DEST5/.claude/settings.local.json" ] && ok "zsh: partly-tracked directory handled" \
                                                || bad "zsh: settings.local.json missing"
    [ -e "$DEST5/.my-scratch" ] && bad "zsh: untracked file travelled" \
                               || ok "zsh: untracked file stayed behind"
    [ -e "$DEST5/.gradle" ] && bad "zsh: top-level denylist did not match" \
                           || ok "zsh: top-level denylist matched"
    [ -e "$DEST5/.claude/.cache" ] && bad "zsh: nested denylist did not match (word-splitting difference)" \
                                  || ok "zsh: nested denylist matched"
else
    echo "  skip  zsh not installed"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

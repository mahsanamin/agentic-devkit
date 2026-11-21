#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
export HOME="$TEST_DIR/home" SHELL=/bin/bash
unset A_ROOT_DIR DEVKIT_DIR MY_WORKFLOW_DIR A_AGENT_OVERLAY_DIR A_AGENT_ORG_OVERLAY_DIR
mkdir -p "$HOME/my_settings" "$TEST_DIR/overlay-source/skills"
printf '%s\n' '# test skill' > "$TEST_DIR/overlay-source/skills/example"
git -C "$TEST_DIR/overlay-source" init -q
git -C "$TEST_DIR/overlay-source" add .
git -C "$TEST_DIR/overlay-source" -c user.name=test -c user.email=test@example.invalid commit -qm fixture
PROFILE="$HOME/my_settings/a_configs.profile"
printf 'export A_ROOT_DIR=""\nexport MY_WORKFLOW_DIR="%s"\nsource "$MY_WORKFLOW_DIR/shell/bootstrap.profile"\n' "$REPO_ROOT" > "$PROFILE"
printf 'source "%s"\n' "$PROFILE" > "$HOME/.bashrc"

before="$(cksum "$PROFILE")"
printf '\n' | "$REPO_ROOT/scripts/a_c_doctor" set private overlay > "$HOME/skip.log"
[ "$before" = "$(cksum "$PROFILE")" ] || fail 'skip changed configuration'
grep -q 'A_AGENT_OVERLAY_REMOTE' "$HOME/skip.log" || fail 'prompt omitted the URL key'

DEST="$TEST_DIR/private overlay"
printf '%s\n%s\n' "$DEST" "$TEST_DIR/overlay-source" | "$REPO_ROOT/scripts/a_c_doctor" set private overlay > "$HOME/private.log" 2>&1
set +u
source "$PROFILE"
set -u
[ "$A_AGENT_OVERLAY_DIR" = "$DEST" ] || fail 'directory with spaces was saved incorrectly'
[ "$A_AGENT_OVERLAY_REMOTE" = "$TEST_DIR/overlay-source" ] || fail 'clone URL was not saved'
[ -d "$DEST/.git" ] || fail 'overlay was not cloned'
[ -n "$(find "$HOME/my_settings" -name '*.bak-*' -print)" ] || fail 'configuration was not backed up'

# Restoring the root uses A_ROOT_*; subsequent org configuration uses ORG_DEVKIT_*.
mkdir -p "$TEST_DIR/root-source"
cat > "$TEST_DIR/root-source/root.config" <<'CONFIG'
DEVKIT_DIR="${DEVKIT_DIR:-$REPO_ROOT}"
PRIVATE_DEVKIT_DIR="${PRIVATE_DEVKIT_DIR:-}"
ORG_DEVKIT_DIR="${ORG_DEVKIT_DIR:-}"
CONFIG
git -C "$TEST_DIR/root-source" init -q
git -C "$TEST_DIR/root-source" add .
git -C "$TEST_DIR/root-source" -c user.name=test -c user.email=test@example.invalid commit -qm fixture
ROOT_DEST="$TEST_DIR/restored-root"
printf '%s\n%s\n' "$ROOT_DEST" "$TEST_DIR/root-source" | "$REPO_ROOT/scripts/a_c_doctor" --configure root > "$HOME/root.log" 2>&1
set +u
source "$PROFILE"
set -u
[ "$A_ROOT_DIR" = "$ROOT_DEST" ] || fail 'root path was not saved'
[ "$A_ROOT_REMOTE" = "$TEST_DIR/root-source" ] || fail 'root URL was not saved'
printf 'organization\n%s\n%s\n' "$TEST_DIR/org-overlay" "$TEST_DIR/overlay-source" | "$REPO_ROOT/scripts/a_c_doctor" --configure overlay > "$HOME/org.log" 2>&1
source "$ROOT_DEST/root.local.config"
[ "$ORG_DEVKIT_DIR" = "$TEST_DIR/org-overlay" ] || fail 'org overlay used the wrong directory key'
[ "$ORG_DEVKIT_REMOTE" = "$TEST_DIR/overlay-source" ] || fail 'org overlay used the wrong URL key'
grep -q 'ORG_DEVKIT_REMOTE' "$HOME/org.log" || fail 'root-aware prompt used the wrong URL key'

# When two dead source paths need recovery, the role selector lets each one save
# to a different key pair instead of defaulting both to private.
printf 'private\n%s\n%s\n' "$TEST_DIR/second-private" "$TEST_DIR/overlay-source" | "$REPO_ROOT/scripts/a_c_doctor" --configure overlay > "$HOME/second-private.log" 2>&1
[ -f "$TEST_DIR/second-private/skills/example" ] || fail 'second repo was not restored'
grep -q 'PRIVATE_DEVKIT_DIR' "$HOME/second-private.log" || fail 'private role used the wrong setting'
grep -q 'ORG_DEVKIT_DIR' "$ROOT_DEST/root.local.config" || fail 'organization setting was overwritten by private recovery'

# A configured missing root continues to warn; skip must not suppress it.
export A_ROOT_DIR="$TEST_DIR/missing-root"
for run in 1 2; do
    "$REPO_ROOT/scripts/a_c_doctor" --offline > "$HOME/warnings-$run.log" 2>&1 || true
    grep -q 'A_ROOT_DIR=.*has no root.config' "$HOME/warnings-$run.log" || fail 'missing root warning disappeared'
    grep -q 'a_c_doctor --configure root' "$HOME/warnings-$run.log" || fail 'root warning omitted guided repair'
done

# If doctor still has a role's configured path, report only that role's command.
mkdir -p "$HOME/.claude/skills"
ln -s "$TEST_DIR/known-private/skills/example" "$HOME/.claude/skills/a_private_example"
ln -s "$TEST_DIR/known-org/skills/example" "$HOME/.claude/skills/a_org_example"
export MY_WORKFLOW_DIR="$REPO_ROOT" A_AGENT_OVERLAY_DIR="$TEST_DIR/known-private" A_AGENT_ORG_OVERLAY_DIR="$TEST_DIR/known-org"
"$REPO_ROOT/scripts/a_c_doctor" --offline > "$HOME/roles.log" 2>&1 || true
grep -q 'fix: a_c_doctor set private overlay' "$HOME/roles.log" || fail 'private source was not mapped to its own command'
grep -q 'fix: a_c_doctor set org overlay' "$HOME/roles.log" || fail 'organization source was not mapped to its own command'
if [ "$(grep -c 'fix: a_c_doctor set ' "$HOME/roles.log")" -ne 2 ]; then
    fail 'known overlay sources received duplicate role suggestions'
fi

# Repairable install drift should lead with the one command that reconciles links
# and generated guidance, rather than making the user choose between separate fixes.
unset A_AGENT_OVERLAY_DIR A_AGENT_ORG_OVERLAY_DIR
mkdir -p "$TEST_DIR/old-copy/skills/a_sk_commit" "$HOME/.agents/skills"
ln -s "$TEST_DIR/old-copy/skills/a_sk_commit" "$HOME/.claude/skills/a_sk_commit"
ln -s "$TEST_DIR/old-copy/skills/a_sk_commit" "$HOME/.agents/skills/a_sk_commit"
"$REPO_ROOT/scripts/a_c_doctor" --offline > "$HOME/repair-hints.log" 2>&1 || true
grep -Fq "fix: \"$REPO_ROOT/install.sh\"" "$HOME/repair-hints.log" \
    || fail 'missing installs did not recommend the exact installer command'
if [ "$(grep -Fc "fix: \"$REPO_ROOT/install.sh\"" "$HOME/repair-hints.log")" -lt 3 ]; then
    fail 'old-copy links and stale guidance did not also recommend the same exact installer command'
fi
echo 'PASS: doctor prompts for correct keys, clones local fixtures, preserves skips and repeats warnings'

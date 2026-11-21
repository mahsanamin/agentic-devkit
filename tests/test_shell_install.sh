#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

for shell_bin in /bin/bash /bin/zsh; do
    [ -x "$shell_bin" ] || continue
    export HOME="$TEST_DIR/$(basename "$shell_bin")"
    export SHELL="$shell_bin"
    unset A_ROOT_DIR DEVKIT_DIR MY_WORKFLOW_DIR A_AGENT_OVERLAY_DIR A_AGENT_ORG_OVERLAY_DIR
    mkdir -p "$HOME/my_settings"
    rc="$HOME/.$(basename "$shell_bin")rc"
    cat > "$HOME/my_settings/a_configs.profile" <<'PROFILE'
export A_ROOT_DIR="$HOME/missing-root"
if [ -f "$A_ROOT_DIR/root.config" ]; then
    source "$A_ROOT_DIR/root.config"
    source "$DEVKIT_DIR/shell/bootstrap.profile"
fi
PROFILE
    printf 'source "%s/my_settings/a_configs.profile"\n' "$HOME" > "$rc"
    # Correct inherited variables must not hide a broken startup profile.
    export MY_WORKFLOW_DIR="$REPO_ROOT"
    if "$REPO_ROOT/scripts/a_c_doctor" --offline --shell-only > "$HOME/before.log" 2>&1; then
        fail "doctor accepted a profile that does not load commands"
    fi
    before="$(cksum "$rc")"
    "$REPO_ROOT/install.sh" --shell-only --dry-run > "$HOME/dry-run.log"
    [ "$before" = "$(cksum "$rc")" ] || fail "dry run changed the rc"
    "$REPO_ROOT/scripts/a_c_doctor" --fix --offline --shell-only > "$HOME/repair.log" 2>&1 \
        || { cat "$HOME/repair.log"; fail "doctor could not repair shell wiring"; }
    grep -q 'fresh .* loads this checkout' "$HOME/repair.log" || fail "repair omitted verification"
    [ -n "$(find "$HOME" -maxdepth 1 -name '.*rc.bak-*' -print)" ] || fail "repair omitted backup"
    [ ! -e "$HOME/.claude" ] || fail "shell-only repair installed agent assets"
    before="$(cksum "$rc")"
    "$REPO_ROOT/install.sh" --shell-only > "$HOME/reinstall.log" 2>&1
    [ "$before" = "$(cksum "$rc")" ] || fail "reinstall was not idempotent"
    # A stale hook must be replaced, rather than accumulating a second handoff.
    sed 's|export MY_WORKFLOW_DIR=.*|export MY_WORKFLOW_DIR=/missing-checkout|' "$rc" > "$rc.tmp"
    mv "$rc.tmp" "$rc"
    "$REPO_ROOT/install.sh" --shell-only > "$HOME/moved.log" 2>&1
    [ "$(grep -c '^# >>> agentic-devkit shell hook >>>$' "$rc")" = 1 ] \
        || fail "repair duplicated the managed hook"
    # Repair must also work before any settings profile exists.
    export HOME="$TEST_DIR/fresh-$(basename "$shell_bin")"
    mkdir -p "$HOME"
    "$REPO_ROOT/scripts/a_c_doctor" --fix --offline --shell-only > "$HOME/fresh.log" 2>&1 \
        || { cat "$HOME/fresh.log"; fail "doctor could not repair a fresh home"; }
    echo "PASS: $(basename "$shell_bin") detects, repairs and verifies broken shell wiring"
done

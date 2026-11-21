#!/usr/bin/env bash
# Repos moved to a new folder: the relocator finds them and repoints the config.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(cd -P "$(mktemp -d)" && pwd)"
trap 'rm -rf "$TEST_DIR"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
export HOME="$TEST_DIR/home"
unset A_ROOT_DIR DEVKIT_DIR MY_WORKFLOW_DIR A_AGENT_OVERLAY_DIR A_AGENT_ORG_OVERLAY_DIR \
      PERSONAL_REPOS_DIR ORG_REPOS_DIR GLOBAL_REPOS_DIR a_dir_p_repos a_dir_w_repos a_dir_g_repos

# The new home of every repo: one folder, with the devkit in it.
NEW="$TEST_DIR/setup"
mkdir -p "$HOME/my_settings" "$NEW/devkit/scripts" "$NEW/my_root" "$NEW/my_overlay/skills" \
         "$NEW/org_overlay/agents" "$TEST_DIR/old/work" "$TEST_DIR/old/personal"
cp "$REPO_ROOT/scripts/a_s_relocate_repos" "$NEW/devkit/scripts/"
touch "$NEW/devkit/install.sh" "$NEW/devkit/scripts/a_c_doctor"
RELOCATE="$NEW/devkit/scripts/a_s_relocate_repos"
cat > "$NEW/my_root/root.config" <<'CONFIG'
ROOT_DIR="${ROOT_DIR:-}"
DEVKIT_DIR="${DEVKIT_DIR:-}"
PRIVATE_DEVKIT_DIR="${PRIVATE_DEVKIT_DIR:-}"
ORG_DEVKIT_DIR="${ORG_DEVKIT_DIR:-}"
CONFIG
cat > "$NEW/my_root/root.local.config" <<EOF
ROOT_DIR="$TEST_DIR/old/work/my_root"
DEVKIT_DIR="$TEST_DIR/old/personal/devkit"
PRIVATE_DEVKIT_DIR="$TEST_DIR/old/personal/my_overlay"
ORG_DEVKIT_DIR="$TEST_DIR/old/work/org_overlay"
EOF
PROFILE="$HOME/my_settings/a_configs.profile"
printf 'export A_ROOT_DIR="%s"\n# keep me\n' "$TEST_DIR/old/work/my_root" > "$PROFILE"

# --list names every moved repo and where it is now, without changing anything.
before="$(cksum "$PROFILE")"
list="$("$RELOCATE" --list)" && fail '--list exited 0 with repos missing'
[ "$before" = "$(cksum "$PROFILE")" ] || fail '--list changed the profile'
for key in A_ROOT_DIR ROOT_DIR DEVKIT_DIR PRIVATE_DEVKIT_DIR ORG_DEVKIT_DIR; do
    printf '%s\n' "$list" | grep -q "^$key	" || fail "--list did not report $key"
done
printf '%s\n' "$list" | grep -q "^PRIVATE_DEVKIT_DIR	.*	$NEW/my_overlay\$" || fail '--list did not find the moved overlay'

# --apply rewrites each one, keeps backups, and leaves other lines alone.
"$RELOCATE" --apply > "$HOME/apply.log" || { cat "$HOME/apply.log"; fail '--apply left repos missing'; }
grep -qx "export A_ROOT_DIR=\"$NEW/my_root\"" "$PROFILE" || fail 'A_ROOT_DIR was not repointed'
grep -qx '# keep me' "$PROFILE" || fail 'unrelated profile lines were lost'
L="$NEW/my_root/root.local.config"
grep -qx "DEVKIT_DIR=\"$NEW/devkit\"" "$L" || fail 'DEVKIT_DIR was not repointed'
grep -qx "PRIVATE_DEVKIT_DIR=\"$NEW/my_overlay\"" "$L" || fail 'PRIVATE_DEVKIT_DIR was not repointed'
grep -qx "ORG_DEVKIT_DIR=\"$NEW/org_overlay\"" "$L" || fail 'ORG_DEVKIT_DIR was not repointed'
grep -qx "ROOT_DIR=\"$NEW/my_root\"" "$L" || fail 'ROOT_DIR was not repointed'
ls "$PROFILE".bak-* >/dev/null 2>&1 || fail 'profile was not backed up'
ls "$L".bak-* >/dev/null 2>&1 || fail 'root.local.config was not backed up'
"$RELOCATE" --list >/dev/null || fail 'a second run still found missing repos'

# Two copies with the same name: --apply does not guess, --list shows both.
mkdir -p "$TEST_DIR/old/work/other/org_overlay/skills" "$NEW/more/org_overlay/skills"
sed -i.tmp "s|^ORG_DEVKIT_DIR=.*|ORG_DEVKIT_DIR=\"$TEST_DIR/old/work/gone/org_overlay\"|" "$L"
rm -rf "$NEW/org_overlay"
"$RELOCATE" --apply >/dev/null && fail '--apply guessed between two copies'
grep -q "gone/org_overlay" "$L" || fail '--apply rewrote an ambiguous path'
out="$("$RELOCATE" --list || true)"
case "$(printf '%s\n' "$out" | grep "^ORG_DEVKIT_DIR	")" in *"|"*) ;; *) fail '--list did not show both copies' ;; esac

echo 'PASS: relocator finds moved repos, repoints them with backups, and never guesses'

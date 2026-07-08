#!/usr/bin/env bash
# probe.sh
# Read-only snapshot of the user's current Claude toolkit plus the latest available
# Claude Code version. Prints a markdown report to stdout. No mdnest, no writes, no
# network mutations. The a_r_l_claude_watch skill reads this report, diffs it against the
# tracker's _state.md, and updates the StayUptoDate/Claude files.
#
# Every probe is guarded so a single missing path or offline network never aborts the run.
# Env overrides (with sane fallbacks for Ahsan's machines):
#   AA_FRAMEWORK_DIR, MY_WORKFLOW_DIR, CLAUDE_CONFIG_DIR
set -uo pipefail

CC_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Resolve a dir from a list of candidates, picking the first whose <name> subdir exists.
# Env vars can be set but stale (point at a moved path), so verify rather than trust.
resolve_dir() { # resolve_dir <subdir-that-must-exist> <candidate1> [candidate2 ...]
  local sub="$1"; shift
  local c
  for c in "$@"; do
    [ -n "$c" ] && [ -d "$c/$sub" ] && { printf '%s' "$c"; return; }
  done
  printf '%s' "$1"  # fall back to first candidate even if missing, so the report shows the path it tried
}

AA_DIR="$(resolve_dir skills "${AA_FRAMEWORK_DIR:-}" $HOME/repos/ai-awareness-framework)"
MW_DIR="$(resolve_dir skills "${MY_WORKFLOW_DIR:-}" $HOME/repos/my_setup)"

# list_dir <path> : print child dir/file names one per "- name" line, or a "(none)" note.
list_dir() {
  local d="$1"
  if [ -d "$d" ]; then
    local found=0
    for entry in "$d"/*; do
      [ -e "$entry" ] || continue
      printf -- "- %s\n" "$(basename "$entry")"
      found=1
    done
    [ "$found" -eq 1 ] || echo "- (empty)"
  else
    echo "- (path not found: $d)"
  fi
}

# list_skills <skills-dir> : like list_dir but only real skill directories.
# Skips eval/optimizer artifacts (*-workspace) and stray files (README.md), which are
# NOT features and would pollute terms.md Part A if listed.
list_skills() {
  local d="$1"
  if [ -d "$d" ]; then
    local found=0
    for entry in "$d"/*; do
      [ -d "$entry" ] || continue
      local name; name="$(basename "$entry")"
      case "$name" in
        *-workspace) continue ;;
      esac
      printf -- "- %s\n" "$name"
      found=1
    done
    [ "$found" -eq 1 ] || echo "- (none)"
  else
    echo "- (path not found: $d)"
  fi
}

# list_plugins : print installed plugin names from installed_plugins.json (.plugins keys),
# not the raw plugins/ dir, which is full of internal files (cache, blocklist.json, ...).
list_plugins() {
  local f="$CC_DIR/plugins/installed_plugins.json"
  if [ -f "$f" ]; then
    python3 -c 'import json,sys
try:
    d=json.load(open(sys.argv[1]))
    ks=sorted((d.get("plugins") or {}).keys())
    print("\n".join("- "+k for k in ks) if ks else "- (none installed)")
except Exception:
    print("- (could not parse installed_plugins.json)")' "$f"
  else
    echo "- (no installed_plugins.json)"
  fi
}

json_field() { # json_field <file> <key>
  python3 -c 'import json,sys
try:
    print(json.load(open(sys.argv[1])).get(sys.argv[2],"?"))
except Exception:
    print("?")' "$1" "$2" 2>/dev/null || echo "?"
}

echo "# Claude toolkit probe"
echo
echo "_Read-only snapshot. Versions and lists below are live from this machine; news and upcoming features are NOT here, research those separately._"
echo

# ---------------------------------------------------------------------------
echo "## Versions"
installed_cc="$(claude --version 2>/dev/null | head -1 | tr -d '\n' || true)"
echo "- Installed Claude Code: ${installed_cc:-unknown}"

latest_cc="$(curl -fsS --max-time 12 https://registry.npmjs.org/@anthropic-ai/claude-code/latest 2>/dev/null \
  | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("version","?"))
except Exception: print("?")' 2>/dev/null || true)"
echo "- Latest Claude Code (npm @anthropic-ai/claude-code): ${latest_cc:-unknown}"

if [ -f "$AA_DIR/config_hints.json" ]; then
  echo "- aa-framework version: $(json_field "$AA_DIR/config_hints.json" framework_version)"
else
  echo "- aa-framework version: (config_hints.json not found at $AA_DIR)"
fi
echo

# ---------------------------------------------------------------------------
echo "## aa-framework ($AA_DIR)"
echo "### skills"
list_skills "$AA_DIR/skills"
echo "### agents"
list_dir "$AA_DIR/agents"
echo "### rules"
list_dir "$AA_DIR/rules"
echo

# ---------------------------------------------------------------------------
echo "## Global ~/.claude ($CC_DIR)"
echo "### skills"
list_skills "$CC_DIR/skills"
echo "### plugins"
list_plugins
echo "### scheduled routines"
if [ -d "$CC_DIR/scheduled-tasks" ]; then
  list_dir "$CC_DIR/scheduled-tasks"
else
  echo "- (no scheduled-tasks dir)"
fi
echo

# ---------------------------------------------------------------------------
echo "## my_setup skills ($MW_DIR/skills)"
list_skills "$MW_DIR/skills"
echo

echo "_End of probe. Build terms.md Part A (\"what I use\") from the lists above; do not invent entries._"

#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_HOME="$(mktemp -d)"
trap 'rm -rf "$TEST_HOME"' EXIT

export HOME="$TEST_HOME"
export MY_WORKFLOW_DIR="$REPO_ROOT"
export SHELL=/bin/bash

fail() { echo "FAIL: $*" >&2; exit 1; }

# A dry run must not create provider directories.
"$REPO_ROOT/install.sh" --link-only --dry-run >/dev/null
[ ! -e "$HOME/.claude" ] || fail "dry run created ~/.claude"
[ ! -e "$HOME/.agents" ] || fail "dry run created ~/.agents"
[ ! -e "$HOME/.gemini" ] || fail "dry run created ~/.gemini"

# The all-provider install shares skills but keeps custom subagents Claude-only.
"$REPO_ROOT/install.sh" --link-only >/dev/null
[ -L "$HOME/.claude/skills/a_sk_commit" ] || fail "Claude skill was not linked"
[ -L "$HOME/.agents/skills/a_sk_commit" ] || fail "shared skill was not linked"
[ -L "$HOME/.gemini/config/skills/a_sk_commit" ] || fail "Antigravity IDE skill was not linked"
[ -L "$HOME/.gemini/antigravity-cli/skills/a_sk_commit" ] || fail "AGY CLI skill was not linked"
[ ! -e "$HOME/.agents/skills/a_sk_setup_claude" ] || fail "Claude-only skill leaked into shared skills"
[ -L "$HOME/.claude/skills/a_sk_setup_claude" ] || fail "Claude-only setup skill was not linked for Claude"
[ -L "$HOME/.claude/agents/a_sag_implementer.md" ] || fail "Claude subagent was not linked"
[ ! -e "$HOME/.codex/agents/a_sag_implementer.md" ] || fail "Claude subagent leaked into Codex"

# One source renders into native provider filenames and preserves handwritten text.
mkdir -p "$HOME/.claude" "$HOME/.codex" "$HOME/.gemini"
printf '%s\n' '# personal Claude note' > "$HOME/.claude/CLAUDE.md"
printf '%s\n' '# personal Codex note' > "$HOME/.codex/AGENTS.md"
printf '%s\n' '# personal Gemini note' > "$HOME/.gemini/GEMINI.md"
"$REPO_ROOT/scripts/a_c_agent_memory" build >/dev/null

for target in \
  "$HOME/.claude/CLAUDE.md" \
  "$HOME/.codex/AGENTS.md" \
  "$HOME/.gemini/GEMINI.md"; do
  grep -q 'agentic-devkit: managed memory' "$target" || fail "managed block missing from $target"
  grep -q '# personal ' "$target" || fail "handwritten content lost from $target"
done

"$REPO_ROOT/scripts/a_c_agent_memory" check >/dev/null
echo "ok: multi-agent install and guidance"

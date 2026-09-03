#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Resolve the interpreter BEFORE HOME is redirected, and resolve it to the REAL binary rather
# than a version-manager shim. A shim (asdf, pyenv) reads its data dir from $HOME, so under the
# override it exits 126 with no message and the whole test dies silently. tomllib needs 3.11+,
# so the system python on macOS is not a usable fallback.
PYTHON_BIN="$(python3 -c 'import sys, tomllib; print(sys.executable)' 2>/dev/null || true)"
if [ -z "$PYTHON_BIN" ]; then
  echo "FAIL: need a python3 with tomllib (3.11+) to validate the generated TOML" >&2
  exit 1
fi

TEST_HOME="$(mktemp -d)"
trap 'rm -rf "$TEST_HOME"' EXIT

export HOME="$TEST_HOME"
export MY_WORKFLOW_DIR="$REPO_ROOT"
export SHELL=/bin/bash
unset A_AGENT_OVERLAY_DIR A_AGENT_ORG_OVERLAY_DIR

fail() { echo "FAIL: $*" >&2; exit 1; }

# A dry run must not create provider directories.
"$REPO_ROOT/install.sh" --link-only --dry-run >/dev/null
[ ! -e "$HOME/.claude" ] || fail "dry run created ~/.claude"
[ ! -e "$HOME/.agents" ] || fail "dry run created ~/.agents"
[ ! -e "$HOME/.gemini" ] || fail "dry run created ~/.gemini"

# The all-provider install shares canonical skills and installs native subagents.
"$REPO_ROOT/install.sh" --link-only >/dev/null
[ -L "$HOME/.claude/skills/a_sk_commit" ] || fail "Claude skill was not linked"
[ -L "$HOME/.agents/skills/a_sk_commit" ] || fail "shared skill was not linked"
[ -L "$HOME/.gemini/config/skills/a_sk_commit" ] || fail "AGY skill was not linked"
[ ! -e "$HOME/.agents/skills/a_sk_setup_claude" ] || fail "Claude-only skill leaked into shared skills"
[ -L "$HOME/.claude/skills/a_sk_setup_claude" ] || fail "Claude-only setup skill was not linked for Claude"
[ -L "$HOME/.claude/agents/a_sag_implementer.md" ] || fail "Claude subagent was not linked"
[ -f "$HOME/.codex/agents/a_sag_implementer.toml" ] || fail "Codex subagent was not generated"
[ ! -L "$HOME/.codex/agents/a_sag_implementer.toml" ] || fail "Codex adapter must not be a Claude symlink"
[ -f "$HOME/.gemini/config/agents/a_sag_implementer.md" ] || fail "AGY subagent was not generated"
[ -f "$HOME/.gemini/agents/a_sag_implementer.md" ] || fail "Gemini CLI subagent was not generated"
[ -f "$HOME/.claude/CLAUDE.md" ] || fail "default install omitted Claude global guidance"
[ -f "$HOME/.codex/AGENTS.md" ] || fail "default install omitted Codex global guidance"
[ -f "$HOME/.gemini/GEMINI.md" ] || fail "default install omitted Gemini global guidance"

grep -q 'model = "gpt-5.6"' "$HOME/.codex/agents/a_sag_implementer.toml" \
  || fail "Claude opus tier was not mapped to the Codex demanding tier"
grep -q 'model = "gpt-5.6-luna"' "$HOME/.codex/agents/a_sag_searcher.toml" \
  || fail "Claude haiku tier was not mapped to the Codex fast tier"
grep -q '^model: pro$' "$HOME/.gemini/config/agents/a_sag_implementer.md" \
  || fail "Claude opus tier was not mapped to AGY pro"
grep -q '^model: flash$' "$HOME/.gemini/config/agents/a_sag_searcher.md" \
  || fail "Claude haiku tier was not mapped to AGY flash"
grep -q '^  - grep_search$' "$HOME/.gemini/config/agents/a_sag_searcher.md" \
  || fail "Claude tools were not translated to AGY tools"
grep -q '^subagent: true$' "$HOME/.gemini/config/agents/a_sag_searcher.md" \
  || fail "AGY adapter is not invokable as a subagent"
[ "$(grep -c '^---$' "$HOME/.gemini/config/agents/a_sag_pr_writer.md")" -gt 2 ] \
  || fail "renderer dropped Markdown separators from the canonical agent body"

# Every canonical definition must produce valid Codex TOML.
"$PYTHON_BIN" - "$HOME/.codex/agents" <<'PY'
import pathlib
import sys
import tomllib

for path in pathlib.Path(sys.argv[1]).glob("*.toml"):
    with path.open("rb") as handle:
        data = tomllib.load(handle)
    assert data["name"] and data["description"] and data["developer_instructions"]
PY

source_count="$(find "$REPO_ROOT/agents" -maxdepth 1 -name 'a_sag_*.md' | wc -l | tr -d ' ')"
codex_count="$(find "$HOME/.codex/agents" -maxdepth 1 -name 'a_sag_*.toml' | wc -l | tr -d ' ')"
agy_count="$(find "$HOME/.gemini/config/agents" -maxdepth 1 -name 'a_sag_*.md' | wc -l | tr -d ' ')"
[ "$source_count" = "$codex_count" ] || fail "Codex agent count differs from canonical source"
[ "$source_count" = "$agy_count" ] || fail "AGY agent count differs from canonical source"

# Reinstalling is idempotent, and unmanaged provider files are preserved.
before="$(cksum "$HOME/.codex/agents/a_sag_searcher.toml")"
"$REPO_ROOT/install.sh" --link-only >/dev/null
after="$(cksum "$HOME/.codex/agents/a_sag_searcher.toml")"
[ "$before" = "$after" ] || fail "reinstall changed a current generated adapter"
printf '%s\n' '# personal agent' > "$HOME/.codex/agents/personal.toml"
"$REPO_ROOT/scripts/a_c_agents" --provider codex uninstall personal >/dev/null
grep -q 'personal agent' "$HOME/.codex/agents/personal.toml" || fail "uninstall removed an unmanaged agent"

# A provider-specific install must not spill into another provider's agent path.
ISOLATED_HOME="$TEST_HOME/codex-only"
mkdir -p "$ISOLATED_HOME"
HOME="$ISOLATED_HOME" "$REPO_ROOT/install.sh" --link-only --provider codex >/dev/null
[ -f "$ISOLATED_HOME/.codex/agents/a_sag_searcher.toml" ] || fail "Codex-only install omitted Codex agents"
[ ! -e "$ISOLATED_HOME/.claude/agents/a_sag_searcher.md" ] || fail "Codex-only install wrote Claude agents"
[ ! -e "$ISOLATED_HOME/.gemini/config/agents/a_sag_searcher.md" ] || fail "Codex-only install wrote AGY agents"

# The core installer includes configured overlays and passes the same provider
# scope without letting each overlay rebuild global memory independently.
FAKE_HOME="$TEST_HOME/with-overlay"
FAKE_OVERLAY="$TEST_HOME/fake-overlay"
mkdir -p "$FAKE_HOME" "$FAKE_OVERLAY"
cat > "$FAKE_OVERLAY/install.sh" <<'SH'
#!/bin/sh
printf '%s|%s\n' "${AGENT_SKIP_MEMORY:-}" "$*" > "$HOME/overlay-call"
SH
chmod +x "$FAKE_OVERLAY/install.sh"
A_AGENT_OVERLAY_DIR="$FAKE_OVERLAY" HOME="$FAKE_HOME" \
  "$REPO_ROOT/install.sh" --link-only >/dev/null
grep -q '^1|--provider all$' "$FAKE_HOME/overlay-call" \
  || fail "configured overlay did not receive the all-provider install scope"

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

grep -q 'rendered for \*\*Claude Code\*\*, made by \*\*Anthropic\*\*' "$HOME/.claude/CLAUDE.md" \
  || fail "Claude global guidance has the wrong runtime identity"
grep -q 'rendered for \*\*Codex\*\*, made by \*\*OpenAI\*\*' "$HOME/.codex/AGENTS.md" \
  || fail "Codex global guidance has the wrong runtime identity"
grep -q 'rendered for \*\*Gemini\*\*, made by \*\*Google\*\*' "$HOME/.gemini/GEMINI.md" \
  || fail "Gemini global guidance has the wrong runtime identity"
! grep -q 'rendered for \*\*Claude Code\*\*' "$HOME/.codex/AGENTS.md" \
  || fail "Claude runtime identity leaked into Codex guidance"
echo "ok: multi-agent install and guidance"

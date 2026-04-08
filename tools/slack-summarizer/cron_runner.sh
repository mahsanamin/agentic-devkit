#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# cron_runner.sh — Wrapper for crontab that sets up the right PATH
#
# Cron runs with a minimal environment. This ensures python3, claude, and
# curl are all available. Edit the PATH below if your tools are elsewhere.
# ─────────────────────────────────────────────────────────────────────────────

export HOME="${HOME:-$(eval echo ~)}"
export PATH="$HOME/.nvm/versions/node/$(ls "$HOME/.nvm/versions/node/" 2>/dev/null | tail -1)/bin:$HOME/.asdf/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/summarizer" sendSummary

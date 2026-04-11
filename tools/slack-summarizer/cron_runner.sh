#!/usr/bin/env bash
# Cron wrapper — sets up PATH and runs sendSummary
export HOME="${HOME:-$(eval echo ~)}"
NVM_LATEST="$HOME/.nvm/versions/node/$(ls -r "$HOME/.nvm/versions/node/" 2>/dev/null | head -1)/bin"
export PATH="$NVM_LATEST:$HOME/.asdf/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/summarizer" sendSummary

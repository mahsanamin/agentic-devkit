#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# publish.sh — Pluggable publish layer for summaries
#
# Source this file to get publish_read / publish_write / publish_enabled.
# Supports three modes (set PUBLISH_MODE in config.env):
#
#   local   — Writes to PUBLISH_DIR (default: $DATA_DIR/published/)
#   mdnest  — Publishes via mdnest CLI (requires MDNEST_SERVER + MDNEST_NS)
#   none    — Skip publishing entirely
#
# Usage:
#   source "$SCRIPT_DIR/publish.sh"
#
#   if publish_enabled; then
#       publish_read "slack/latest.md" > existing.md
#       publish_write "slack/latest.md" < updated.md
#   fi
# ─────────────────────────────────────────────────────────────────────────────

PUBLISH_MODE="${PUBLISH_MODE:-local}"
PUBLISH_DIR="${PUBLISH_DIR:-${DATA_DIR:-$HOME/.slack_summaries_data}/published}"

# Check if publishing is configured and available
publish_enabled() {
    case "$PUBLISH_MODE" in
        none|"") return 1 ;;
        local) return 0 ;;
        mdnest)
            if ! command -v mdnest &>/dev/null; then
                echo "WARNING: PUBLISH_MODE=mdnest but mdnest not found on PATH" >&2
                return 1
            fi
            if [[ -z "${MDNEST_SERVER:-}" || -z "${MDNEST_NS:-}" ]]; then
                echo "WARNING: PUBLISH_MODE=mdnest but MDNEST_SERVER or MDNEST_NS not set" >&2
                return 1
            fi
            return 0
            ;;
        *)
            echo "WARNING: Unknown PUBLISH_MODE '$PUBLISH_MODE' (use: local, mdnest, none)" >&2
            return 1
            ;;
    esac
}

# Read a published file. Output to stdout. Returns 1 if not found.
# Usage: publish_read "slack/latest.md" > output.md
publish_read() {
    local path="$1"
    case "$PUBLISH_MODE" in
        local)
            local file="$PUBLISH_DIR/$path"
            if [[ -f "$file" ]]; then
                cat "$file"
            else
                return 1
            fi
            ;;
        mdnest)
            mdnest read "$MDNEST_SERVER/$MDNEST_NS/$path" 2>/dev/null || return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# Write content from stdin to a published path.
# Usage: echo "content" | publish_write "slack/latest.md"
#    or: publish_write "slack/latest.md" < file.md
publish_write() {
    local path="$1"
    case "$PUBLISH_MODE" in
        local)
            local file="$PUBLISH_DIR/$path"
            mkdir -p "$(dirname "$file")"
            cat > "$file"
            ;;
        mdnest)
            mdnest write "$MDNEST_SERVER/$MDNEST_NS/$path" - 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

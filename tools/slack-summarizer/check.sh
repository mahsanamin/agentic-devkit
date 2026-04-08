#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# check.sh — Validate configuration and connectivity
#
# Checks: config.env exists, required vars set, proxy reachable, API key valid,
# Claude authenticated, channels accessible, DM channel valid.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { echo -e "  ${GREEN}OK${NC}  $*"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}FAIL${NC}  $*"; FAIL=$((FAIL + 1)); }
warn() { echo -e "  ${YELLOW}WARN${NC}  $*"; WARN=$((WARN + 1)); }
section() { echo ""; echo "── $* ──"; }

# ── Config file ──────────────────────────────────────────────────────────────
section "Config"

if [[ -f "$SCRIPT_DIR/config.env" ]]; then
    pass "config.env exists"
    source "$SCRIPT_DIR/config.env"
else
    fail "config.env not found — run: cp config.env.sample config.env"
    echo ""
    echo "Cannot continue without config.env."
    exit 1
fi

# ── Required variables ───────────────────────────────────────────────────────
section "Required Settings"

check_var() {
    local name="$1"
    local val="${!name:-}"
    local placeholder="${2:-}"
    if [[ -z "$val" ]]; then
        fail "$name is not set"
    elif [[ -n "$placeholder" && "$val" == "$placeholder" ]]; then
        fail "$name is still the placeholder value"
    else
        pass "$name = ${val:0:40}$([ ${#val} -gt 40 ] && echo '...' || true)"
    fi
}

check_var SLACK_PROXY_URL
check_var SLACK_PROXY_API_KEY "your-proxy-api-key-here"
check_var MY_SLACK_USER_ID "U0000000000"
check_var MY_SLACK_USER_NAME "Your Name"
check_var SLACK_WORKSPACE_URL "https://your-workspace.slack.com"
check_var SLACK_DM_CHANNEL "D000000000"

if [[ ${#CHANNELS[@]} -eq 0 ]]; then
    fail "CHANNELS array is empty — add at least one channel"
else
    pass "CHANNELS has ${#CHANNELS[@]} channel(s) configured"
fi

# ── Proxy connectivity ───────────────────────────────────────────────────────
section "Slack Proxy"

API_BASE="${SLACK_PROXY_URL:-}"
API_KEY="${SLACK_PROXY_API_KEY:-}"

if [[ -n "$API_BASE" && "$API_KEY" != "your-proxy-api-key-here" ]]; then
    PROXY_RESP=$(curl -sk --max-time 10 -w "%{http_code}" -o /tmp/slack_check_$$.json \
        -H "X-API-Key: ${API_KEY}" \
        "${API_BASE}/api/mentions/all?count=1" 2>&1) || PROXY_RESP="000"

    if [[ "$PROXY_RESP" == "200" ]]; then
        pass "Proxy reachable at $API_BASE (HTTP 200)"

        # Check if response has expected format
        if python3 -c "
import json, sys
d = json.load(open('/tmp/slack_check_$$.json'))
assert d.get('success') is True, 'success != true'
assert 'data' in d, 'no data field'
" 2>/dev/null; then
            pass "Proxy returns valid JSON format"
        else
            warn "Proxy responded but format may be unexpected"
        fi
    elif [[ "$PROXY_RESP" == "401" || "$PROXY_RESP" == "403" ]]; then
        fail "Proxy returned $PROXY_RESP — check SLACK_PROXY_API_KEY"
    elif [[ "$PROXY_RESP" == "000" ]]; then
        fail "Cannot connect to proxy at $API_BASE — is it running?"
    else
        warn "Proxy returned HTTP $PROXY_RESP"
    fi
    rm -f /tmp/slack_check_$$.json
else
    warn "Skipping proxy check (URL or API key not configured)"
fi

# ── Channel access ───────────────────────────────────────────────────────────
if [[ -n "$API_BASE" && "$API_KEY" != "your-proxy-api-key-here" && ${#CHANNELS[@]} -gt 0 ]]; then
    section "Channels"

    CHAN_OK=0
    CHAN_FAIL=0
    for ch in "${CHANNELS[@]}"; do
        IFS=':' read -r ch_id ch_name ch_tier <<< "$ch"
        RESP=$(curl -sk --max-time 10 -w "%{http_code}" -o /dev/null \
            -H "X-API-Key: ${API_KEY}" \
            "${API_BASE}/api/channels/${ch_id}/recent-messages?count=1" 2>&1) || RESP="000"

        if [[ "$RESP" == "200" ]]; then
            pass "#${ch_name} (${ch_id}) — ${ch_tier}"
            CHAN_OK=$((CHAN_OK + 1))
        else
            fail "#${ch_name} (${ch_id}) — HTTP $RESP"
            CHAN_FAIL=$((CHAN_FAIL + 1))
        fi
    done
fi

# ── DM channel ───────────────────────────────────────────────────────────────
if [[ -n "$API_BASE" && "$API_KEY" != "your-proxy-api-key-here" && "${SLACK_DM_CHANNEL:-}" != "D000000000" ]]; then
    section "DM Channel"

    DM_RESP=$(curl -sk --max-time 10 -w "%{http_code}" -o /dev/null \
        -H "X-API-Key: ${API_KEY}" \
        "${API_BASE}/api/channels/${SLACK_DM_CHANNEL}/recent-messages?count=1" 2>&1) || DM_RESP="000"

    if [[ "$DM_RESP" == "200" ]]; then
        pass "DM channel $SLACK_DM_CHANNEL accessible"
    else
        fail "DM channel $SLACK_DM_CHANNEL — HTTP $DM_RESP"
    fi
fi

# ── Claude CLI ───────────────────────────────────────────────────────────────
section "Claude CLI"

if command -v claude &>/dev/null; then
    pass "claude found at $(which claude)"

    if [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" || -n "${ANTHROPIC_API_KEY:-}" ]]; then
        pass "Auth token available"
    else
        # Try keychain extraction (same as summarizer does)
        KEYCHAIN_TOKEN=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
            | python3 -c "import json,sys; print(json.load(sys.stdin).get('claudeAiOauth',{}).get('accessToken',''))" 2>/dev/null || true)
        if [[ -n "$KEYCHAIN_TOKEN" ]]; then
            pass "Auth token extractable from Keychain"
        else
            fail "No auth token — run: claude /login"
        fi
    fi
else
    fail "claude not found — install: npm install -g @anthropic-ai/claude-code"
fi

# ── Python ───────────────────────────────────────────────────────────────────
section "Python"

if command -v python3 &>/dev/null; then
    pass "python3 found ($(python3 --version 2>&1))"
else
    fail "python3 not found — install: brew install python3"
fi

# ── Publishing ───────────────────────────────────────────────────────────────
section "Publishing"

source "$SCRIPT_DIR/publish.sh"
PUBLISH_MODE="${PUBLISH_MODE:-local}"

if [[ "$PUBLISH_MODE" == "none" ]]; then
    warn "PUBLISH_MODE=none — summaries won't be published as living docs"
elif [[ "$PUBLISH_MODE" == "local" ]]; then
    pass "PUBLISH_MODE=local — docs go to ${PUBLISH_DIR:-$DATA_DIR/published}/"
elif [[ "$PUBLISH_MODE" == "mdnest" ]]; then
    if command -v mdnest &>/dev/null; then
        pass "PUBLISH_MODE=mdnest — mdnest found"
        if [[ -n "${MDNEST_SERVER:-}" && -n "${MDNEST_NS:-}" ]]; then
            pass "mdnest target: $MDNEST_SERVER/$MDNEST_NS/"
        else
            fail "MDNEST_SERVER or MDNEST_NS not set"
        fi
    else
        fail "PUBLISH_MODE=mdnest but mdnest not installed"
    fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────"
echo -e "  ${GREEN}$PASS passed${NC}  ${RED}$FAIL failed${NC}  ${YELLOW}$WARN warnings${NC}"
echo "─────────────────────────────────"

if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "Fix the failures above before running ./summarizer sendSummary"
    exit 1
else
    echo ""
    echo "Ready to go. Try: ./summarizer sendSummary"
fi

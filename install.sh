#!/usr/bin/env bash
#
# install.sh - bootstrap my_setup on this machine, in one command.
#
#   ./install.sh              Wire the shell (once) + link all skills & agents
#   ./install.sh --link-only  Skip shell wiring; just (re)link skills & agents
#   ./install.sh -n           Dry run: print what would change, touch nothing
#   ./install.sh -f           Force: repoint skill/agent links that point elsewhere
#   ./install.sh -h           Show this help
#
# It is idempotent: safe to re-run any time (e.g. after `git pull`) to pick up
# new skills/agents. It NEVER overwrites an existing shell config and only ever
# APPENDS a single guarded source line to your shell rc - your personal config
# is left intact.
#
# Two layers get installed:
#   1. Shell   - MY_WORKFLOW_DIR + the profile that puts scripts/ on PATH and
#                loads sourced/ functions. One-time per machine.
#   2. Claude  - every repo skill -> ~/.claude/skills, every agent -> ~/.claude/agents,
#                as symlinks back into this repo (edit here = live, no reinstall).

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; DIM='\033[2m'; NC='\033[0m'

# Resolve this script's real location -> repo root (handles being symlinked).
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
REPO_ROOT="$(cd -P "$(dirname "$SOURCE")" && pwd)"

LINK_ONLY=false
DRY_RUN=false
FORCE=false

usage() { sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; /^set -euo/d'; }

while [ "$#" -gt 0 ]; do
    case "$1" in
        --link-only)   LINK_ONLY=true ;;
        -n|--dry-run)  DRY_RUN=true ;;
        -f|--force)    FORCE=true ;;
        -h|--help)     usage; exit 0 ;;
        *) echo -e "${RED}Unknown arg: $1${NC}"; echo "Try: ./install.sh --help"; exit 1 ;;
    esac
    shift
done

say()  { echo -e "$@"; }
step() { echo -e "\n${BLUE}==>${NC} $*"; }

# ---------------------------------------------------------------------------
# 1. Shell wiring (once per machine). Detect-or-create; never destructive.
# ---------------------------------------------------------------------------
wire_shell() {
    step "Shell wiring"

    # (a) Already wired in this shell? Then there is nothing to do.
    if [ -n "${MY_WORKFLOW_DIR:-}" ]; then
        say "  ${GREEN}●${NC} already wired ${DIM}(MY_WORKFLOW_DIR=$MY_WORKFLOW_DIR)${NC}"
        if [ "$(cd -P "$MY_WORKFLOW_DIR" 2>/dev/null && pwd)" != "$REPO_ROOT" ]; then
            say "  ${YELLOW}▲${NC} it points at a different checkout than this one ($REPO_ROOT)"
        fi
        return
    fi

    # Pick the shell rc to wire.
    local rc
    case "$(basename "${SHELL:-/bin/zsh}")" in
        bash) rc="$HOME/.bashrc" ;;
        *)    rc="$HOME/.zshrc" ;;
    esac

    # (b) Does the rc already source a my_settings profile? Assume that wires us.
    if [ -f "$rc" ] && grep -Eq 'my_settings/.*\.profile' "$rc"; then
        say "  ${GREEN}●${NC} $rc already sources a my_settings profile ${DIM}(leaving it untouched)${NC}"
        say "  ${DIM}open a new shell (or 'source $rc') if you haven't since it was added${NC}"
        return
    fi

    # (c) Is there an existing config profile we should just hook up, not create?
    local existing=""
    if [ -d "$HOME/my_settings" ]; then
        local f
        for f in "$HOME"/my_settings/*.profile; do
            [ -f "$f" ] || continue
            if grep -q 'MY_WORKFLOW_DIR' "$f"; then existing="$f"; break; fi
        done
    fi

    local profile
    if [ -n "$existing" ]; then
        profile="$existing"
        say "  ${GREEN}●${NC} found existing config ${DIM}$profile${NC} (not overwriting)"
    else
        # (d) Create a fresh minimal config from the sample, with MY_WORKFLOW_DIR
        #     pointed at THIS checkout. Other values keep sample placeholders for
        #     you to edit.
        profile="$HOME/my_settings/configs.profile"
        if $DRY_RUN; then
            say "  ${DIM}would create${NC} $profile ${DIM}from shell/configs.profile.sample (MY_WORKFLOW_DIR=$REPO_ROOT)${NC}"
        else
            mkdir -p "$HOME/my_settings"
            # Copy sample, then hard-set MY_WORKFLOW_DIR to the real path.
            sed "s|^export MY_WORKFLOW_DIR=.*|export MY_WORKFLOW_DIR='$REPO_ROOT'|" \
                "$REPO_ROOT/shell/configs.profile.sample" > "$profile"
            say "  ${GREEN}created${NC}   $profile ${DIM}(MY_WORKFLOW_DIR set; edit the rest to taste)${NC}"
        fi
    fi

    # (e) Append the source line to the rc, only if it isn't there already.
    local src_line="source \"$profile\""
    if [ -f "$rc" ] && grep -Fq "$src_line" "$rc"; then
        say "  ${GREEN}●${NC} $rc already sources it"
    elif $DRY_RUN; then
        say "  ${DIM}would append${NC} to $rc: $src_line"
    else
        printf '\n# my_setup\n%s\n' "$src_line" >> "$rc"
        say "  ${GREEN}wired${NC}     $rc ${DIM}-> sources $profile${NC}"
        say "  ${YELLOW}!${NC} run ${GREEN}source $rc${NC} (or open a new terminal) to activate this shell"
    fi
}

# ---------------------------------------------------------------------------
# 2. Link skills + agents (delegates to the granular installers).
# ---------------------------------------------------------------------------
link_claude() {
    local flags=()
    $DRY_RUN && flags+=(--dry-run)
    $FORCE   && flags+=(--force)

    # ${arr[@]+...} guards against "unbound variable" on an empty array under
    # `set -u` with macOS's bundled bash 3.2.
    step "Skills"
    "$REPO_ROOT/scripts/a_c_skills" install ${flags[@]+"${flags[@]}"}

    step "Agents"
    "$REPO_ROOT/scripts/a_c_agents" install ${flags[@]+"${flags[@]}"}
}

main() {
    say "${BLUE}my_setup install${NC} ${DIM}($REPO_ROOT)${NC}"
    $DRY_RUN && say "${YELLOW}(dry run - nothing will change)${NC}"

    $LINK_ONLY || wire_shell
    link_claude

    say "\n${GREEN}Done.${NC} ${DIM}Skills + agents linked from $REPO_ROOT.${NC}"
    say "${DIM}Restart Claude Code (or start a new session) to pick up new skills/agents.${NC}"
}

main

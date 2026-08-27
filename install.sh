#!/usr/bin/env bash
#
# install.sh - bootstrap my_setup on this machine, in one command.
#
#   ./install.sh              Wire shell + install Claude, Codex, and Gemini assets
#   ./install.sh --provider X Install all, claude, codex, agy, gemini-cli, or gemini
#   ./install.sh --link-only  Skip shell wiring; just (re)link agent assets
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
#   2. Agents  - shared skills plus provider-native subagents for Claude, Codex,
#                AGY/Antigravity, and Gemini CLI.

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
PROVIDER=all

usage() { sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; /^set -euo/d'; }

while [ "$#" -gt 0 ]; do
    case "$1" in
        --link-only)   LINK_ONLY=true ;;
        --provider|--providers)
            [ "$#" -ge 2 ] || { echo -e "${RED}$1 needs a value${NC}"; exit 1; }
            PROVIDER="$2"; shift ;;
        -n|--dry-run)  DRY_RUN=true ;;
        -f|--force)    FORCE=true ;;
        -h|--help)     usage; exit 0 ;;
        *) echo -e "${RED}Unknown arg: $1${NC}"; echo "Try: ./install.sh --help"; exit 1 ;;
    esac
    shift
done

case "$PROVIDER" in
    all|claude|codex|agy|gemini|gemini-cli) ;;
    *) echo -e "${RED}Unknown provider: $PROVIDER${NC}"; exit 1 ;;
esac

say()  { echo -e "$@"; }
step() { echo -e "\n${BLUE}==>${NC} $*"; }

# The shell rc we wire / tell the user to re-source. One source of truth.
detect_rc() {
    case "$(basename "${SHELL:-/bin/zsh}")" in
        bash) echo "$HOME/.bashrc" ;;
        *)    echo "$HOME/.zshrc" ;;
    esac
}

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
    local rc; rc="$(detect_rc)"

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
has_provider() {
    [ "$PROVIDER" = all ] || [ "$PROVIDER" = "$1" ] \
        || { [ "$PROVIDER" = gemini ] && { [ "$1" = agy ] || [ "$1" = gemini-cli ]; }; }
}

link_agents() {
    local flags=()
    $DRY_RUN && flags+=(--dry-run)
    $FORCE   && flags+=(--force)

    # ${arr[@]+...} guards against "unbound variable" on an empty array under
    # `set -u` with macOS's bundled bash 3.2.
    if has_provider claude; then
        step "Skills (Claude Code)"
        AGENT_SKILL_PROVIDER=claude CLAUDE_SKILLS_DIR="$HOME/.claude/skills" \
            "$REPO_ROOT/scripts/a_c_skills" install ${flags[@]+"${flags[@]}"}

        step "Subagents (Claude Code)"
        "$REPO_ROOT/scripts/a_c_agents" --provider claude install ${flags[@]+"${flags[@]}"}
    fi

    # Codex and Google's agents support the open Agent Skills location. Install
    # it once when any of them is selected; they share the same symlinks.
    if has_provider codex || has_provider agy || has_provider gemini-cli; then
        step "Skills (Codex + Gemini CLI)"
        AGENT_SKILL_PROVIDER=portable CLAUDE_SKILLS_DIR="$HOME/.agents/skills" \
            "$REPO_ROOT/scripts/a_c_skills" install ${flags[@]+"${flags[@]}"}
    fi

    if has_provider codex; then
        step "Subagents (Codex)"
        "$REPO_ROOT/scripts/a_c_agents" --provider codex install ${flags[@]+"${flags[@]}"}
    fi

    # Antigravity 2.0 and AGY CLI share the global customizations directory.
    if has_provider agy; then
        step "Skills (AGY / Antigravity)"
        AGENT_SKILL_PROVIDER=portable CLAUDE_SKILLS_DIR="$HOME/.gemini/config/skills" \
            "$REPO_ROOT/scripts/a_c_skills" install ${flags[@]+"${flags[@]}"}

        step "Subagents (AGY / Antigravity)"
        "$REPO_ROOT/scripts/a_c_agents" --provider agy install ${flags[@]+"${flags[@]}"}
    fi

    if has_provider gemini-cli; then
        step "Subagents (Gemini CLI)"
        "$REPO_ROOT/scripts/a_c_agents" --provider gemini-cli install ${flags[@]+"${flags[@]}"}
    fi
}

# ---------------------------------------------------------------------------
# 3. Tell the user about the optional always-on bits.
#
# Deliberately NOT auto-installed: these are background services (a launchd job,
# a listening port), and installing one behind someone's back on a fresh machine
# is not ours to decide. But an unmentioned feature is an unused feature, so
# print what exists, whether it is already running here, and the exact command.
# ---------------------------------------------------------------------------
suggest_extras() {
    command -v python3 > /dev/null 2>&1 || return 0
    local label="com.ahsan.claude-sessions-web"
    local agent="$HOME/Library/LaunchAgents/$label.plist"
    local daemon="/Library/LaunchDaemons/$label.plist"

    say ""
    say "${BLUE}Optional: the Claude sessions dashboard${NC}"
    say "${DIM}One live web page listing every Claude Code session on this machine, with${NC}"
    say "${DIM}its session id and a ready-to-run resume command, plus a search over every${NC}"
    say "${DIM}session on disk so one you closed by mistake can be found again.${NC}"

    if [ -f "$daemon" ]; then
        say "  ${GREEN}already installed${NC} ${DIM}as a boot daemon (starts before login)${NC}"
        return 0
    fi
    if [ -f "$agent" ]; then
        say "  ${GREEN}already installed${NC} ${DIM}as a login agent${NC}"
        say "    ${GREEN}sudo a_c_claude_sessions --install-boot-daemon${NC}  ${DIM}start at boot instead, no login needed${NC}"
        return 0
    fi
    say "    ${GREEN}a_c_claude_sessions${NC}                            ${DIM}one-off snapshot, nothing installed${NC}"
    say "    ${GREEN}a_c_claude_sessions --find \"what you remember\"${NC}   ${DIM}recover a closed session${NC}"
    say "    ${GREEN}a_c_claude_sessions --serve --tailscale${NC}         ${DIM}live page on your tailnet, this shell only${NC}"
    say "    ${GREEN}a_c_claude_sessions --install-web-agent${NC}         ${DIM}keep it running, starts at login${NC}"
    say "    ${GREEN}sudo a_c_claude_sessions --install-boot-daemon${NC}  ${DIM}starts at boot, survives an unattended reboot${NC}"
    say "${DIM}Details, including what is exposed on the network: docs/claude-sessions.md${NC}"
}

main() {
    say "${BLUE}my_setup install${NC} ${DIM}($REPO_ROOT)${NC}"
    $DRY_RUN && say "${YELLOW}(dry run - nothing will change)${NC}"

    $LINK_ONLY || wire_shell
    link_agents

    say "\n${GREEN}Done.${NC} ${DIM}Agent assets linked from $REPO_ROOT (provider: $PROVIDER).${NC}"

    # Global memory. Two cases, and the difference matters:
    #  - Already adopted (the markers are there): a pull can change memory/core-rules.md,
    #    so rebuild, or the rules file silently goes stale. This is the whole point of
    #    re-running install.sh after a pull.
    #  - Not adopted yet: never rewrite a hand-written rules file behind someone's back.
    #    Point at the command, which shows a diff first.
    if ! $DRY_RUN && [ -x "$REPO_ROOT/scripts/a_c_agent_memory" ]; then
        if grep -qs 'agentic-devkit: managed memory' "$HOME/.claude/CLAUDE.md" 2>/dev/null \
            || grep -qs 'agentic-devkit: managed memory' "$HOME/.codex/AGENTS.md" 2>/dev/null \
            || grep -qs 'agentic-devkit: managed memory' "$HOME/.gemini/GEMINI.md" 2>/dev/null; then
            say ""
            say "${BLUE}Global agent guidance${NC}"
            "$REPO_ROOT/scripts/a_c_agent_memory" build --provider "$PROVIDER" 2>&1 | sed 's/^/  /'
        elif [ -n "${A_MACHINE_NAME:-}" ]; then
            say ""
            say "${YELLOW}Your global agent guidance is not managed yet.${NC}"
            say "    ${GREEN}a_c_agent_memory diff${NC}   ${DIM}see what it would add${NC}"
            say "    ${GREEN}a_c_agent_memory build${NC}  ${DIM}adopt it (hand-written text is kept)${NC}"
        fi
    fi
    if ! $DRY_RUN && has_provider claude; then
        suggest_extras
    fi

    if $DRY_RUN; then
        :
    elif [ -n "${MY_WORKFLOW_DIR:-}" ]; then
        say "${DIM}Shell already active in this terminal.${NC} ${DIM}Restart your agent CLI to reload instructions and skills.${NC}"
    else
        local rc; rc="$(detect_rc)"
        say ""
        say "${YELLOW}Next step - activate it in this terminal:${NC}"
        say "    ${GREEN}source $rc${NC}   ${DIM}(or just open a new terminal)${NC}"
        say "${DIM}A script runs in its own subshell and can't change your current shell,${NC}"
        say "${DIM}so this one line is yours to run. Then restart your agent CLI to reload its assets.${NC}"
    fi
}

main

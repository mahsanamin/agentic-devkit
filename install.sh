#!/usr/bin/env bash
#
# install.sh - bootstrap agentic-devkit on this machine, in one command.
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
            # The line may be indented (it sits inside the standalone branch of the
            # sample), so match leading whitespace and put it back.
            sed "s|^\([[:space:]]*\)export MY_WORKFLOW_DIR=.*|\1export MY_WORKFLOW_DIR='$REPO_ROOT'|" \
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
        printf '\n# agentic-devkit\n%s\n' "$src_line" >> "$rc"
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

# Configured overlays are part of the same agent environment. Installing the
# core from Claude, Codex, or Gemini must not leave another provider or an
# overlay behind. Overlay installers receive the same explicit scope and flags.
install_configured_overlays() {
    local flags=() overlay seen=""
    $DRY_RUN && flags+=(--dry-run)
    $FORCE   && flags+=(--force)

    for overlay in "${A_AGENT_OVERLAY_DIR:-}" "${A_AGENT_ORG_OVERLAY_DIR:-}"; do
        [ -n "$overlay" ] || continue
        [ -x "$overlay/install.sh" ] || continue
        [ "$(cd -P "$overlay" 2>/dev/null && pwd)" != "$REPO_ROOT" ] || continue
        case " $seen " in *" $overlay "*) continue ;; esac
        seen="$seen $overlay"
        step "Configured overlay ($(basename "$overlay"))"
        AGENT_SKIP_MEMORY=1 "$overlay/install.sh" --provider "$PROVIDER" \
            ${flags[@]+"${flags[@]}"}
    done
}

memory_provider() {
    case "$PROVIDER" in
        agy|gemini|gemini-cli) echo gemini ;;
        *) echo "$PROVIDER" ;;
    esac
}

# ---------------------------------------------------------------------------
# Machine config for a shell that has not loaded the profile yet.
#
# On a brand new machine install.sh runs before the profile was ever sourced, so
# nothing is exported: no machine name, no overlays, no brains. The guidance build
# then refuses once per provider. Read the same files the profile would read, and
# ask for the machine name when none is configured. The name is typed by the
# user, never derived from the hostname.
# ---------------------------------------------------------------------------

# Last `[export ]KEY=value` assignment of KEY in FILE, quotes stripped. No eval.
read_assignment() {
    local key="$1" file="$2" line
    [ -f "$file" ] || return 0
    line="$(grep -E "^[[:space:]]*(export[[:space:]]+)?$key=" "$file" | tail -n 1)" || true
    line="${line#*=}"
    line="${line%%#*}"
    line="$(printf '%s' "$line" | sed -e 's/[[:space:]]*$//' -e "s/^[\"']//" -e "s/[\"']\$//")"
    printf '%s' "${line/#\~/$HOME}"
}

# The personal profile this machine sources (root-repo form first).
settings_profile() {
    local f
    for f in "$HOME/my_settings/a_configs.profile" "$HOME/my_settings/configs.profile"; do
        [ -f "$f" ] && { echo "$f"; return; }
    done
}

load_machine_config() {
    local profile root
    profile="$(settings_profile)"
    root="${A_ROOT_DIR:-}"
    [ -n "$root" ] || root="$(read_assignment A_ROOT_DIR "${profile:-/dev/null}")"

    if [ -n "$root" ] && [ -f "$root/root.config" ]; then
        export A_ROOT_DIR="$root"
        # Already loaded by the shell? Then the exports below are already right.
        [ -n "${MY_WORKFLOW_DIR:-}" ] && return 0
        # Same order and mapping as shell/bootstrap.profile: local first, then root.config.
        set +u
        [ -f "$root/root.local.config" ] && source "$root/root.local.config"
        source "$root/root.config"
        set -u
        export A_AGENT_OVERLAY_DIR="${PRIVATE_DEVKIT_DIR:-${A_AGENT_OVERLAY_DIR:-}}"
        export A_AGENT_ORG_OVERLAY_DIR="${ORG_DEVKIT_DIR:-${A_AGENT_ORG_OVERLAY_DIR:-}}"
        export A_AGENT_ORG_BRAIN_DIR="${ORG_BRAIN_DIR:-${A_AGENT_ORG_BRAIN_DIR:-}}"
        export A_AGENT_BRAIN_DIR="${PRIVATE_BRAIN_DIR:-${A_AGENT_BRAIN_DIR:-}}"
        export A_MACHINE_NAME="${MACHINE_NAME:-${A_MACHINE_NAME:-}}"
    elif [ -z "${A_MACHINE_NAME:-}" ] && [ -n "$profile" ]; then
        # Standalone profile: the name is set by hand in it.
        local name; name="$(read_assignment A_MACHINE_NAME "$profile")"
        [ -n "$name" ] && export A_MACHINE_NAME="$name"
    fi
    return 0
}

# Where the machine name is stored on this machine, for messages and for saving.
machine_name_home() {
    if [ -n "${A_ROOT_DIR:-}" ] && [ -f "$A_ROOT_DIR/root.config" ]; then
        echo "$A_ROOT_DIR/root.local.config"
    else
        settings_profile
    fi
}

# Write KEY="value" into FILE: replace the existing line, or append one.
save_assignment() {
    local key="$1" value="$2" file="$3" prefix="$4" tmp
    if [ -f "$file" ] && grep -Eq "^[[:space:]]*(export[[:space:]]+)?$key=" "$file"; then
        tmp="$(mktemp)"
        sed -E "s|^([[:space:]]*)(export[[:space:]]+)?$key=.*|\1\2$key=\"$value\"|" "$file" > "$tmp"
        cat "$tmp" > "$file" && rm -f "$tmp"
    else
        printf '%s%s="%s"\n' "$prefix" "$key" "$value" >> "$file"
    fi
}

# Make sure A_MACHINE_NAME is set, asking for it if needed. Returns 1 to skip the build.
ensure_machine_name() {
    [ -n "${A_MACHINE_NAME:-}" ] && return 0

    local home; home="$(machine_name_home)"
    local is_root=false
    [ -n "${A_ROOT_DIR:-}" ] && [ -f "$A_ROOT_DIR/root.config" ] && is_root=true

    say "  ${YELLOW}!${NC} This machine has no name yet. Agents use it to say which machine they are on."
    if $DRY_RUN; then
        say "  ${DIM}would ask for it, save it to ${home:-your profile}, and build the guidance${NC}"
        return 1
    fi
    if [ ! -t 0 ]; then
        say "  Skipping the guidance build. Set the name, then build:"
        if $is_root; then
            say "    ${GREEN}echo 'MACHINE_NAME=\"<name>\"' >> $home${NC}"
        else
            say "    ${GREEN}set A_MACHINE_NAME in ${home:-~/my_settings/configs.profile}${NC}"
        fi
        say "    ${GREEN}$REPO_ROOT/install.sh --link-only${NC}"
        return 1
    fi

    say "  ${DIM}Pick any name you like, for example WORK-LAPTOP. It does not have to match the hostname.${NC}"
    say "  ${DIM}Letters, digits, dots, dashes and underscores. Press Enter to skip for now.${NC}"
    local name=""
    while :; do
        read -r -p "  Machine name: " name || name=""
        [ -z "$name" ] && break
        [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] && break
        say "  ${RED}Only letters, digits, dots, dashes and underscores.${NC}"
    done
    if [ -z "$name" ]; then
        say "  Skipped. Run ${GREEN}$REPO_ROOT/install.sh --link-only${NC} again when you have a name."
        return 1
    fi

    export A_MACHINE_NAME="$name"
    if $is_root; then
        if [ ! -f "$home" ]; then
            {
                echo "# This machine only. Never committed. Overrides root.config."
                echo "# Loaded BEFORE root.config, whose keys are all \${KEY:-default}, so these win and"
                echo "# every path derived from it follows."
                echo ""
            } > "$home"
        fi
        save_assignment MACHINE_NAME "$name" "$home" ""
        say "  ${GREEN}saved${NC}     MACHINE_NAME=\"$name\" ${DIM}in $home${NC}"
    elif [ -n "$home" ]; then
        save_assignment A_MACHINE_NAME "$name" "$home" "export "
        say "  ${GREEN}saved${NC}     A_MACHINE_NAME=\"$name\" ${DIM}in $home${NC}"
    else
        say "  ${YELLOW}!${NC} no profile to save it in, so it is used for this run only."
        say "    ${DIM}Add export A_MACHINE_NAME=\"$name\" to your shell profile to keep it.${NC}"
    fi
    return 0
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
    say "${BLUE}agentic-devkit install${NC} ${DIM}($REPO_ROOT)${NC}"
    $DRY_RUN && say "${YELLOW}(dry run - nothing will change)${NC}"

    $LINK_ONLY || wire_shell
    load_machine_config
    link_agents
    install_configured_overlays

    # A setup run adopts or refreshes managed global guidance for the selected
    # scope. The memory engine preserves all handwritten content outside its
    # markers and refuses a rebuild that would silently drop configured sources.
    if [ -x "$REPO_ROOT/scripts/a_c_agent_memory" ]; then
        say ""
        say "${BLUE}Global agent guidance${NC}"
        if ! ensure_machine_name; then
            :
        elif $DRY_RUN; then
            MY_WORKFLOW_DIR="$REPO_ROOT" "$REPO_ROOT/scripts/a_c_agent_memory" build --dry-run \
                --provider "$(memory_provider)" 2>&1 | sed 's/^/  /'
        else
            MY_WORKFLOW_DIR="$REPO_ROOT" "$REPO_ROOT/scripts/a_c_agent_memory" build \
                --provider "$(memory_provider)" 2>&1 | sed 's/^/  /'
        fi
    fi
    say "\n${GREEN}Done.${NC} ${DIM}Agent assets and guidance installed (provider: $PROVIDER).${NC}"
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

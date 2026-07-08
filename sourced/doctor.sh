#!/bin/bash
# my_setup doctor: verifies this shell is correctly wired to MY_WORKFLOW_DIR
# and that loaded functions match the on-disk source (catches stale shells and
# rogue clones).

a_c_workflow_doctor() {
    local GREEN='\033[0;32m' YELLOW='\033[1;33m' RED='\033[0;31m' BLUE='\033[0;34m' NC='\033[0m'
    local ok=0 warn=0 err=0

    _doc_ok()   { echo -e " ${GREEN}✓${NC} $1"; ok=$((ok+1)); }
    _doc_warn() { echo -e " ${YELLOW}!${NC} $1"; warn=$((warn+1)); }
    _doc_err()  { echo -e " ${RED}✗${NC} $1"; err=$((err+1)); }

    echo -e "${BLUE}my_setup doctor${NC}"
    echo "─────────────────────────────────────────────────────────────"

    # 1. MY_WORKFLOW_DIR set and valid
    if [ -z "$MY_WORKFLOW_DIR" ]; then
        _doc_err "MY_WORKFLOW_DIR is not set"
        echo "   Fix: set it in ~/my_settings/configs.profile"
        echo "─────────────────────────────────────────────────────────────"
        echo -e "${GREEN}$ok ok${NC}  ${YELLOW}$warn warn${NC}  ${RED}$err err${NC}"
        unset -f _doc_ok _doc_warn _doc_err
        return 1
    elif [ ! -d "$MY_WORKFLOW_DIR" ]; then
        _doc_err "MY_WORKFLOW_DIR points to missing directory: $MY_WORKFLOW_DIR"
    else
        _doc_ok "MY_WORKFLOW_DIR = $MY_WORKFLOW_DIR"
    fi

    # 2. Find the rc file and the configs.profile it sources.
    # Accepts any *configs.profile under ~/my_settings/ (e.g. configs.profile,
    # a_configs.profile) — the filename is user choice, the wiring is what matters.
    local rcfile=""
    if [ -n "$ZSH_VERSION" ] && [ -f "$HOME/.zshrc" ]; then
        rcfile="$HOME/.zshrc"
    elif [ -f "$HOME/.bashrc" ]; then
        rcfile="$HOME/.bashrc"
    fi

    local sourced_profile=""
    if [ -n "$rcfile" ]; then
        # Extract the path that rc file sources from ~/my_settings/
        sourced_profile=$(grep -E '^[[:space:]]*(source|\.)[[:space:]]+.*my_settings/[^ ]*\.profile' "$rcfile" \
            | head -1 \
            | sed -E 's/^[[:space:]]*(source|\.)[[:space:]]+//; s/["'\'']//g' \
            | sed "s|^~|$HOME|; s|\$HOME|$HOME|; s|\${HOME}|$HOME|")
    fi

    if [ -n "$sourced_profile" ] && [ -f "$sourced_profile" ]; then
        _doc_ok "$rcfile sources $sourced_profile"
        local cfg_wf
        cfg_wf=$(grep -E '^[[:space:]]*export[[:space:]]+MY_WORKFLOW_DIR' "$sourced_profile" | tail -1)
        if [ -n "$cfg_wf" ]; then
            echo "   declares: $cfg_wf"
        else
            _doc_warn "$sourced_profile does not export MY_WORKFLOW_DIR"
        fi
    elif [ -n "$sourced_profile" ]; then
        _doc_err "$rcfile sources $sourced_profile but that file does not exist"
    elif [ -n "$rcfile" ]; then
        # Fall back to looking for any configs.profile under ~/my_settings/
        local found_profile
        found_profile=$(ls "$HOME"/my_settings/*configs.profile 2>/dev/null | head -1)
        if [ -n "$found_profile" ]; then
            _doc_err "$rcfile does not source $found_profile"
            echo "   Fix: echo 'source $found_profile' >> $rcfile"
        else
            _doc_err "No configs.profile found in ~/my_settings/ and $rcfile sources none"
            echo "   Fix: cp $MY_WORKFLOW_DIR/shell/configs.profile.sample ~/my_settings/configs.profile"
            echo "        echo 'source ~/my_settings/configs.profile' >> $rcfile"
        fi
    else
        _doc_warn "Could not locate shell rc file (~/.zshrc or ~/.bashrc)"
    fi

    # 4. Git state of the clone
    if [ -d "$MY_WORKFLOW_DIR/.git" ]; then
        local head branch dirty
        head=$(git -C "$MY_WORKFLOW_DIR" rev-parse --short HEAD 2>/dev/null)
        branch=$(git -C "$MY_WORKFLOW_DIR" branch --show-current 2>/dev/null)
        _doc_ok "Clone is a git repo (HEAD $head on ${branch:-detached})"

        dirty=$(git -C "$MY_WORKFLOW_DIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
        if [ "$dirty" -gt 0 ]; then
            _doc_warn "Clone has $dirty uncommitted change(s)"
        fi

        # Offline behind-check against cached upstream ref
        local behind
        behind=$(git -C "$MY_WORKFLOW_DIR" rev-list --count "HEAD..@{u}" 2>/dev/null)
        if [ -n "$behind" ] && [ "$behind" -gt 0 ]; then
            _doc_warn "Clone is behind upstream by $behind commit(s) (local refs only; run: git -C \"$MY_WORKFLOW_DIR\" fetch && git -C \"$MY_WORKFLOW_DIR\" pull)"
        fi
    else
        _doc_err "$MY_WORKFLOW_DIR is not a git repository"
    fi

    # 5. PATH contains the scripts directory
    case ":$PATH:" in
        *":$MY_WORKFLOW_DIR/scripts:"*)
            _doc_ok "scripts/ is on PATH"
            ;;
        *)
            _doc_err "scripts/ is NOT on PATH — generic.profile did not load in this shell"
            echo "   Fix: source ~/my_settings/configs.profile  (or open a new terminal)"
            ;;
    esac

    # 6. Critical: loaded function matches on-disk version.
    # This catches the case where the shell loaded an older copy from a different
    # clone (wrong MY_WORKFLOW_DIR earlier in the session, or a stale file).
    echo ""
    echo -e "${BLUE}Function drift check (loaded vs on-disk):${NC}"
    _doc_check_func() {
        local fn="$1"
        local marker="$2"
        local file="$3"
        if ! typeset -f "$fn" > /dev/null 2>&1; then
            _doc_err "$fn is not defined in this shell"
            return
        fi
        if typeset -f "$fn" | grep -q "$marker"; then
            _doc_ok "$fn matches expected source in $(basename "$file")"
        else
            _doc_err "$fn in memory is STALE (missing marker: $marker)"
            echo "   Loaded from somewhere other than $file."
            echo "   Fix: source \"$file\"   (or open a new terminal after confirming configs.profile is correct)"
        fi
    }

    _doc_check_func "a_g_worktree_init" \
        "Usage: a_g_worktree_init <branch-name>" \
        "$MY_WORKFLOW_DIR/sourced/worktree.sh"

    _doc_check_func "a_g_worktree_remove" \
        "a_g_worktree_remove" \
        "$MY_WORKFLOW_DIR/sourced/worktree.sh"

    unset -f _doc_check_func

    # 7. Resolve how the shell would run the command.
    # Shows PATH copies separately from the function — duplicate scripts on PATH
    # from other clones are a common cause of "it works on one machine, not another".
    echo ""
    echo -e "${BLUE}Resolution order for 'a_g_worktree_init':${NC}"
    if typeset -f a_g_worktree_init > /dev/null 2>&1; then
        echo "   1. function defined in this shell (wins — PATH is not consulted)"
    fi
    local path_copies
    path_copies=$(which -a a_g_worktree_init 2>/dev/null | grep -v '^[a-z_]* is a' | grep '^/')
    if [ -n "$path_copies" ]; then
        local n=0
        while IFS= read -r line; do
            n=$((n+1))
            echo "   $((n+1)). $line"
        done <<< "$path_copies"
        local copy_count
        copy_count=$(echo "$path_copies" | wc -l | tr -d ' ')
        if [ "$copy_count" -gt 1 ]; then
            echo -e "   ${YELLOW}! Multiple copies on PATH — stale clones can hijack the script.${NC}"
        fi
    fi

    echo "─────────────────────────────────────────────────────────────"
    echo -e "${GREEN}$ok ok${NC}  ${YELLOW}$warn warn${NC}  ${RED}$err err${NC}"
    unset -f _doc_ok _doc_warn _doc_err

    [ "$err" -eq 0 ]
}

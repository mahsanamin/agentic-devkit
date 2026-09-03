#!/bin/zsh
#
# bootstrap.profile - the one shell file that wires a machine to this devkit.
#
# It holds LOGIC and no values. Every path comes from the root instruction repo's
# root.config (and root.local.config for what differs on this machine), so moving a
# repo is a change there, not an edit here.
#
# The caller (a tiny hand written file in $HOME, sourced by .zshrc) does exactly two
# things before sourcing this: export A_ROOT_DIR, and nothing else.
#
# With no root repo present, every fallback below keeps a machine working, so this
# file never hard depends on the root repo existing.

########################### System limits ####
# macOS defaults to 256 open files, which crashes zellij and other long-running tools.
ulimit -n 10240 2>/dev/null || true

########################### The root repo: paths and machine values ####
if [ -n "${A_ROOT_DIR:-}" ] && [ -f "$A_ROOT_DIR/root.config" ]; then
    # local FIRST: every key in root.config is ${KEY:-default}, so a value set here survives
    # and the paths derived from it follow. The other order expands them before the override.
    [ -f "$A_ROOT_DIR/root.local.config" ] && source "$A_ROOT_DIR/root.local.config"
    source "$A_ROOT_DIR/root.config"
fi

########################### Roles -> the variable names the tooling expects ####
# The left side is what scripts already read. The right side is the role in root.config.
# Keep this mapping here, so a rename on either side is one edit in one file.
export MY_WORKFLOW_DIR="${DEVKIT_DIR:-${MY_WORKFLOW_DIR:-}}"
export A_C_WORKFLOW_DIR="$MY_WORKFLOW_DIR"
export A_ORG_OVERLAY_DIR="${ORG_DEVKIT_DIR:-}"
export A_PERSONAL_OVERLAY_DIR="${PRIVATE_DEVKIT_DIR:-}"

# Sources for the generated global guidance (a_c_agent_memory reads these).
export A_AGENT_OVERLAY_DIR="$A_PERSONAL_OVERLAY_DIR"
export A_AGENT_ORG_OVERLAY_DIR="$A_ORG_OVERLAY_DIR"
export A_AGENT_ORG_BRAIN_DIR="${ORG_BRAIN_DIR:-}"
export A_AGENT_BRAIN_DIR="${PRIVATE_BRAIN_DIR:-}"
export A_MACHINE_NAME="${MACHINE_NAME:-}"

# Machine and org identity, used to find the org shell profile below.
export a_company_name="${ORG_SLUG:-${a_company_name:-}}"
export a_machine_type="${MACHINE_TYPE:-${a_machine_type:-}}"

# Repo tiers, which become the cd_p / cd_w / cd_g aliases in generic.profile.
export a_dir_w_repos="${ORG_REPOS_DIR:-${a_dir_w_repos:-}}"
export a_dir_p_repos="${PERSONAL_REPOS_DIR:-${a_dir_p_repos:-}}"
export a_dir_g_repos="${GLOBAL_REPOS_DIR:-${a_dir_g_repos:-}}"

# Optional machine directories. Empty is normal; the alias simply is not defined.
export a_dir_gd="${GDRIVE_DIR:-${a_dir_gd:-}}"
export a_dir_gc="${GDRIVE_CHATS_DIR:-${a_dir_gc:-}}"

########################### Shared aliases, exports and commands ####
if [ -n "$MY_WORKFLOW_DIR" ] && [ -f "$MY_WORKFLOW_DIR/shell/generic.profile" ]; then
    source "$MY_WORKFLOW_DIR/shell/generic.profile"
else
    echo "bootstrap.profile: MY_WORKFLOW_DIR is not usable ($MY_WORKFLOW_DIR)" >&2
fi

########################### Org overlay wiring ####
# The org shell profile and the org project scripts live in the org overlay, not under
# the public core. Guarded: absent overlay is a no-op, not an error.
if [ -n "$A_ORG_OVERLAY_DIR" ] && [ -d "$A_ORG_OVERLAY_DIR" ]; then
    if [ -n "$a_company_name" ] && [ -n "$a_machine_type" ]; then
        _a_org="$A_ORG_OVERLAY_DIR/shell/${a_company_name}.${a_machine_type}.profile"
        [ -f "$_a_org" ] && source "$_a_org"
        unset _a_org
    fi
    [ -d "$A_ORG_OVERLAY_DIR/project_scripts" ] \
        && export PATH="$A_ORG_OVERLAY_DIR/project_scripts:$PATH"
fi

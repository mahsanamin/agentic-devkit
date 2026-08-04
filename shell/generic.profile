########################### Derived Paths ####
# MY_WORKFLOW_DIR must be set before sourcing this file
if [ -z "$MY_WORKFLOW_DIR" ]; then
    echo "Error: MY_WORKFLOW_DIR is not set. Set it in your configs.profile."
    return 1
fi

########################### Global Path Additions ####
# Add your own PATH entries here or in your org profile
# export PATH=$PATH:/path/to/your/tools

########################### Organization-Specific Profile ####
if [ -n "$a_company_name" ] && [ -n "$a_machine_type" ]; then
    export a_org_profile="${MY_WORKFLOW_DIR}/shell/${a_company_name}.${a_machine_type}.profile"
    # A missing org profile is benign: the generic core ships none, and an overlay
    # (e.g. a company overlay) sources its own org profile after this file loads.
    [ -f "$a_org_profile" ] && source "$a_org_profile"
fi

########################### Directory Aliases ####
# cd_p = personal repos, cd_w = work repos, cd_g = global/shared repos
# Define more in your org profile (e.g., cd_be, cd_api, etc.)
if [ -n "$a_dir_p_repos" ]; then
    alias cd_p="cd ${a_dir_p_repos}"
fi
if [ -n "$a_dir_w_repos" ]; then
    alias cd_w="cd ${a_dir_w_repos}"
fi
if [ -n "$a_dir_g_repos" ]; then
    alias cd_g="cd ${a_dir_g_repos}"
fi
alias cd_wf="cd ${MY_WORKFLOW_DIR}"

########################### Secrets & Keys ####
# Source local secrets files if they exist (never commit these)
[ -f ~/.aws_keys ] && source ~/.aws_keys
[ -f ~/.my_secrets ] && source ~/.my_secrets

########################### Clear Shadowing Aliases ####
# zsh refuses to define a function whose name is already an alias, and the parse
# error kills the REST of that file - every definition after it is silently lost.
# An alias left behind by an older generation of this setup is the usual culprit,
# so clear our own namespace before defining anything in it.
if [ -n "$ZSH_VERSION" ]; then
    unalias -m 'a_g_*' 'a_c_*' 'a_s_*' 2>/dev/null
else
    for a_stale_alias in $(alias 2>/dev/null | sed -n 's/^alias \(a_[gcs]_[a-zA-Z0-9_]*\)=.*/\1/p'); do
        unalias "$a_stale_alias" 2>/dev/null
    done
    unset a_stale_alias
fi

########################### Sourced Functions ####
source "$MY_WORKFLOW_DIR/sourced/process.sh"
source "$MY_WORKFLOW_DIR/sourced/worktree.sh"
source "$MY_WORKFLOW_DIR/sourced/git.sh"
source "$MY_WORKFLOW_DIR/sourced/doctor.sh"
source "$MY_WORKFLOW_DIR/sourced/task.sh"
# Transitional back-compat aliases for renamed commands (old muscle-memory names).
[ -f "$MY_WORKFLOW_DIR/sourced/compat.sh" ] && source "$MY_WORKFLOW_DIR/sourced/compat.sh"

########################### Scripts on PATH ####
chmod +x "$MY_WORKFLOW_DIR/scripts/"* 2>/dev/null
export PATH="$MY_WORKFLOW_DIR/scripts:$PATH"

# Project-specific wrappers (thin scripts that bake a repo's specifics around the
# generic a_* commands). Same treatment as scripts/, so they work from the
# terminal; tether widgets get this dir on PATH via the launchd agents.
if [ -d "$MY_WORKFLOW_DIR/project_scripts" ]; then
  chmod +x "$MY_WORKFLOW_DIR/project_scripts/"* 2>/dev/null
  export PATH="$MY_WORKFLOW_DIR/project_scripts:$PATH"
fi

########################### Development Environment Setup ####
# Uncomment the tools you use:

## pyenv
# export PYENV_ROOT="$HOME/.pyenv"
# export PATH="$PYENV_ROOT/bin:$PATH"
# if command -v pyenv 1>/dev/null 2>&1; then
#   eval "$(pyenv init --path)"
# fi

## asdf
# if [ -f "/opt/homebrew/opt/asdf/libexec/asdf.sh" ]; then
#     source "/opt/homebrew/opt/asdf/libexec/asdf.sh"
# fi

## nvm
# export NVM_DIR="$HOME/.nvm"
# [ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"
# [ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"

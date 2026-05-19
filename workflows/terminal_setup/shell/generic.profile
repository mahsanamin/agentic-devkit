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
# Org profiles are per-machine, local, and gitignored — see .gitignore.
# Path acts as a hint: if the file exists we source it; if not, silent.
if [ -n "$a_company_name" ] && [ -n "$a_machine_type" ]; then
    export a_org_profile="${MY_WORKFLOW_DIR}/shell/${a_company_name}.${a_machine_type}.profile"
    [ -f "$a_org_profile" ] && source "$a_org_profile"
fi

########################### Directory Aliases ####
# cd_p = personal repos, cd_w = work repos
# Define more in your org profile (e.g., cd_be, cd_api, etc.)
if [ -n "$a_dir_p_repos" ]; then
    alias cd_p="cd ${a_dir_p_repos}"
fi
if [ -n "$a_dir_w_repos" ]; then
    alias cd_w="cd ${a_dir_w_repos}"
fi
alias cd_wf="cd ${MY_WORKFLOW_DIR}"

########################### Secrets & Keys ####
# Source local secrets files if they exist (never commit these)
[ -f ~/.aws_keys ] && source ~/.aws_keys
[ -f ~/.my_secrets ] && source ~/.my_secrets

########################### Sourced Functions ####
source "$MY_WORKFLOW_DIR/sourced/process.sh"
source "$MY_WORKFLOW_DIR/sourced/worktree.sh"
source "$MY_WORKFLOW_DIR/sourced/git.sh"
source "$MY_WORKFLOW_DIR/sourced/doctor.sh"

########################### Scripts on PATH ####
chmod +x "$MY_WORKFLOW_DIR/scripts/"* 2>/dev/null
export PATH="$MY_WORKFLOW_DIR/scripts:$PATH"

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

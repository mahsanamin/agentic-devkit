#!/bin/zsh
#
# prompt.sh - show MACHINE_NAME in grey at the start of the shell prompt.
#
# For zsh and bash prompts that are not starship (install.sh configures starship
# itself). It runs as a hook just before each prompt is drawn, so it lands after
# oh-my-zsh, a theme, or a hand-written PROMPT line in .zshrc, whatever order the
# rc file loads them in. It reads MACHINE_NAME at that moment, so a name set late
# in the profile still shows.
#
# Idempotent: the prefix is added once and swapped out if the name changes.
# Turn it off with A_PROMPT_MACHINE_NAME=0.

[[ $- == *i* ]] || return 0

# Starship draws its own prompt and gets the name from its [custom.machine] module.
_a_prompt_machine_skip() {
    [ "${A_PROMPT_MACHINE_NAME:-1}" = 0 ] || [ -n "${STARSHIP_SHELL:-}" ] || [ -z "${MACHINE_NAME:-}" ]
}

if [ -n "${ZSH_VERSION:-}" ]; then
    _a_prompt_machine_precmd() {
        local prefix="%F{8}@${MACHINE_NAME}%f "
        if _a_prompt_machine_skip; then
            [ -n "${_A_PROMPT_PREFIX:-}" ] && PROMPT="${PROMPT#"$_A_PROMPT_PREFIX"}"
            _A_PROMPT_PREFIX=""
            return 0
        fi
        # Strip the previous prefix first, then add the current one.
        [ -n "${_A_PROMPT_PREFIX:-}" ] && PROMPT="${PROMPT#"$_A_PROMPT_PREFIX"}"
        PROMPT="${prefix}${PROMPT}"
        _A_PROMPT_PREFIX="$prefix"
        # Stay last, so a theme's own precmd that rebuilds PROMPT runs before this one.
        precmd_functions=(${precmd_functions:#_a_prompt_machine_precmd} _a_prompt_machine_precmd)
    }
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd _a_prompt_machine_precmd
elif [ -n "${BASH_VERSION:-}" ]; then
    _a_prompt_machine_prompt_command() {
        local prefix="\[\e[90m\]@${MACHINE_NAME}\[\e[0m\] "
        [ -n "${_A_PROMPT_PREFIX:-}" ] && PS1="${PS1#"$_A_PROMPT_PREFIX"}"
        if _a_prompt_machine_skip; then
            _A_PROMPT_PREFIX=""
            return 0
        fi
        PS1="${prefix}${PS1}"
        _A_PROMPT_PREFIX="$prefix"
    }
    case ";${PROMPT_COMMAND:-};" in
        *";_a_prompt_machine_prompt_command;"*) ;;
        *) PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}_a_prompt_machine_prompt_command" ;;
    esac
fi

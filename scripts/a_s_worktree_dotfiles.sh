#!/usr/bin/env bash
#
# a_s_worktree_dotfiles.sh, one rule for what travels from the main checkout into a
# new worktree. Sourced by a_g_worktree_init and a_g_worktree_review, which both used
# to carry their own copy of the loop.
#
# WHY THE COPY EXISTS. `git worktree add` gives you the committed tree and nothing
# else, so the local config a project deliberately never commits (.env, .envrc,
# .claude/settings.local.json) is absent in a fresh worktree and the project will not
# run there until someone copies it in.
#
# WHY IT NEEDED A RULE. The old loop copied every dotfile in the main checkout. That
# also carried across the things nobody wants a second copy of: a scratch file someone
# left at the root and never committed, a machine-specific .idea/ full of absolute
# paths into the main checkout, and a multi-gigabyte .gradle/ cache. Worse, it landed
# unnoticed: `cp -Rn` refuses to overwrite a FILE that already exists, but on a
# DIRECTORY it merges, so untracked junk inside a tracked directory was copied in
# beside the tracked files and looked like part of the branch.
#
# THE RULE, per root dotfile entry:
#   tracked            skip. The checkout already produced it, at the right revision.
#   ignored            copy. This is the local config the whole copy exists for.
#   neither            skip, and say so. Untracked and not ignored is loose work
#                      sitting in the base checkout; it belongs to whoever left it
#                      there, not to a branch that is about to be reviewed.
#   partly tracked dir copy only the ignored files inside it, so .claude/ still hands
#                      over settings.local.json without handing over anything else.
# A denylist drops ignored-but-worthless state (editor and build caches) on top of
# that: copying it costs minutes and disk, and some of it is wrong in a new path.
#
# Modified tracked files never travel under any setting. They are uncommitted work in
# the base checkout, and the worktree is built from a commit.
#
# Usage:  a_s_copy_local_dotfiles <src-root> <dest-root> [--include-untracked]
# Exit:   always 0. A copy problem is reported, never fatal: the worktree exists by
#         the time this runs, and failing here would strand it half-built.

# Ignored state that is never worth copying. Matched on the entry's own name and on
# every path component below it, so .claude/.gradle/ is dropped too.
A_WT_DOTFILE_DENY=(
    .git .DS_Store
    .gradle .m2 .cargo .tox .nox
    .idea .vscode-server .history
    .venv .direnv .env.d
    .mypy_cache .pytest_cache .ruff_cache .cache .ccls-cache .clangd
    .terraform .turbo .next .nuxt .svelte-kit .angular .dart_tool
    .parcel-cache .sass-cache .npm .yarn .pnpm-store .bundle
)

# True when any component of the path is on the denylist. Pattern-matched rather than
# split on "/", because zsh does not word-split an unquoted expansion and a split-based
# version would silently check nothing there.
a_s_wt_is_denied() {
    local path="$1" deny
    for deny in "${A_WT_DOTFILE_DENY[@]}"; do
        case "/$path/" in
            */"$deny"/*) return 0 ;;
        esac
    done
    return 1
}

a_s_copy_local_dotfiles() {
    local src="$1" dest="$2" include_untracked="${3:-}"
    local copied=0 skipped_state=0
    local left_behind=() entry name

    [ -d "$src" ] && [ -d "$dest" ] || return 0

    # Colors are the caller's; fall back to empty so the helper also works standalone.
    local C_GREEN="${GREEN:-}" C_YELLOW="${YELLOW:-}" C_OFF="${NC:-}"

    for entry in "$src"/.*; do
        name="$(basename "$entry")"
        [ "$name" = "." ] && continue
        [ "$name" = ".." ] && continue

        # .git is the repo itself, not something anyone chose to leave lying around,
        # so it is dropped without being counted as skipped state.
        [ "$name" = ".git" ] && continue

        if a_s_wt_is_denied "$name"; then
            skipped_state=$((skipped_state + 1))
            continue
        fi

        if git -C "$src" ls-files --error-unmatch -- "$name" >/dev/null 2>&1; then
            # Tracked, or a directory holding tracked files. The worktree checkout
            # already has that content. Hand over only the ignored files inside it.
            [ -d "$entry" ] || continue
            local member
            while IFS= read -r member; do
                [ -z "$member" ] && continue
                a_s_wt_is_denied "$member" && { skipped_state=$((skipped_state + 1)); continue; }
                [ -e "$dest/$member" ] && continue
                mkdir -p "$(dirname "$dest/$member")" 2>/dev/null || continue
                if cp -R "$src/$member" "$dest/$member" 2>/dev/null; then
                    copied=$((copied + 1))
                fi
            done < <(git -C "$src" ls-files -z --others --ignored --exclude-standard -- "$name" 2>/dev/null | tr '\0' '\n')
            # Untracked and not ignored inside that directory gets the same treatment as
            # at the root, including being named. Silently dropping it is how someone
            # loses a settings file in a project that never gitignored it.
            while IFS= read -r member; do
                [ -z "$member" ] && continue
                a_s_wt_is_denied "$member" && continue
                [ -e "$dest/$member" ] && continue
                if [ "$include_untracked" = "--include-untracked" ]; then
                    mkdir -p "$(dirname "$dest/$member")" 2>/dev/null || continue
                    cp -R "$src/$member" "$dest/$member" 2>/dev/null && copied=$((copied + 1))
                else
                    left_behind+=("$member")
                fi
            done < <(git -C "$src" ls-files -z --others --exclude-standard -- "$name" 2>/dev/null | tr '\0' '\n')
            continue
        fi

        if git -C "$src" check-ignore -q -- "$name" 2>/dev/null; then
            # Ignored on purpose: this is the local config the copy exists for.
            if cp -Rn "$entry" "$dest/" 2>/dev/null; then
                copied=$((copied + 1))
            fi
            continue
        fi

        # Untracked and not ignored: loose work in the base checkout.
        if [ "$include_untracked" = "--include-untracked" ]; then
            if cp -Rn "$entry" "$dest/" 2>/dev/null; then
                copied=$((copied + 1))
            fi
        else
            left_behind+=("$name")
        fi
    done

    [ "$copied" -gt 0 ] && echo -e "${C_GREEN}✓ Copied $copied local config file(s) to the worktree${C_OFF}"
    [ "$skipped_state" -gt 0 ] && echo "  (skipped $skipped_state cache/state director$([ "$skipped_state" -eq 1 ] && echo y || echo ies))"

    if [ "${#left_behind[@]}" -gt 0 ]; then
        echo -e "${C_YELLOW}Left behind, untracked in the base checkout and not ignored:${C_OFF}"
        local shown=0
        for name in "${left_behind[@]}"; do
            if [ "$shown" -ge 8 ]; then
                echo "    …and $(( ${#left_behind[@]} - shown )) more"
                break
            fi
            echo "    $name"
            shown=$((shown + 1))
        done
        echo "  Re-run with --include-untracked to take them, or copy the one you need by hand."
    fi

    return 0
}

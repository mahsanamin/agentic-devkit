# shellcheck shell=bash
# a_s_link_common.sh - shared rules for the skill and agent installers.
#
# Sourced by a_c_skills and a_c_agents. Decides when a symlink that points
# "elsewhere" is a leftover this tooling may repoint without --force.

# The repos whose links are never repointed without --force: this devkit and
# every configured overlay. Prints one resolved path per line.
a_s_known_repos() {
    local d
    for d in "${REPO_ROOT:-}" "${A_AGENT_OVERLAY_DIR:-}" "${A_AGENT_ORG_OVERLAY_DIR:-}" \
             "${PRIVATE_DEVKIT_DIR:-}" "${ORG_DEVKIT_DIR:-}"; do
        [ -n "$d" ] && [ -d "$d" ] && (cd -P "$d" && pwd)
    done
}

# a_s_is_leftover_link <link> <entry-name> <kind-dir>
#   kind-dir is "skills" or "agents"; entry-name is the skill dir or agent file name.
# True when the link is safe to replace: it is dangling, or it has the shape this
# installer creates (.../<kind-dir>/<entry-name>) and points outside every known
# repo, which is what a moved or retired checkout leaves behind.
a_s_is_leftover_link() {
    local link="$1" name="$2" kind="$3" cur parent r
    [ -L "$link" ] || return 1
    [ -e "$link" ] || return 0
    cur="$(readlink "$link")"
    [ "$(basename "$cur")" = "$name" ] || return 1
    parent="$(cd -P "$(dirname "$cur")" 2>/dev/null && pwd)" || return 0
    [ "$(basename "$parent")" = "$kind" ] || return 1
    while IFS= read -r r; do
        case "$parent/" in "$r"/*) return 1 ;; esac
    done < <(a_s_known_repos)
    return 0
}

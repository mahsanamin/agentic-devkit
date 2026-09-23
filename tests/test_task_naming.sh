#!/usr/bin/env bash
#
# Behaviour fixture for the task naming helpers in a_s_task_common.sh: the name a
# task's zellij tab and its Claude session share, <prefix>-<ticket>-<feature>.
#
# The name has to be the same on every run for the same repo and ticket, because
# that is how a re-run finds the tab it made. A name that drifts opens a second
# tab and a second Claude in the same worktree. It also has to degrade to the bare
# ticket rather than fail, since a naming problem must never stop a task start.
#
# Runs every case under bash and zsh, because the library is sourced into the
# user's zsh shell and zsh does not word-split an unquoted variable.
#
# Usage: bash tests/test_task_naming.sh

set -uo pipefail

REPO_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/scripts/a_s_task_common.sh"

pass=0; fail=0

# check <shell> <description> <expected> <snippet run after sourcing the library>
check() {
    local sh="$1" desc="$2" want="$3" code="$4" got
    got="$(env -i HOME="$HOME" PATH="$PATH" "$sh" -c ". '$LIB' >/dev/null 2>&1; $code" 2>&1)"
    if [ "$got" = "$want" ]; then
        pass=$((pass+1)); printf '  ok   [%s] %s\n' "$sh" "$desc"
    else
        fail=$((fail+1)); printf 'FAIL   [%s] %s: want "%s", got "%s"\n' "$sh" "$desc" "$want" "$got"
    fi
}

shells="bash"
command -v zsh >/dev/null 2>&1 && shells="bash zsh"

for sh in $shells; do
    check "$sh" "short repo name is used as is" "api-abc-123" \
        'a_task_session_name ABC-123 "$(a_task_repo_prefix api)"'
    check "$sh" "repo name is lowercased and cleaned" "my-app-abc-123" \
        'a_task_session_name ABC-123 "$(a_task_repo_prefix My_App)"'
    check "$sh" "long multi-word repo name becomes its initials" "lbsn" \
        'a_task_repo_prefix long-backend-service-name'
    check "$sh" "long single-word repo name is cut to the cap" "averyverylon" \
        'a_task_repo_prefix averyverylongname'
    check "$sh" "A_TASK_PREFIX_MAX changes the cap" "abcd" \
        'A_TASK_PREFIX_MAX=4 a_task_repo_prefix abcdefgh'
    check "$sh" "alias overrides the derived prefix" "ios-abc-123" \
        'A_TASK_PREFIX_ALIASES="some-mobile-app-swift=ios other=x"; a_task_session_name ABC-123 "$(a_task_repo_prefix some-mobile-app-swift)"'
    check "$sh" "alias list may use commas, and matching ignores case" "android" \
        'A_TASK_PREFIX_ALIASES="a=b,Some-Android-App=android"; a_task_repo_prefix some-android-app'
    check "$sh" "the last alias for a repo wins, so a later layer can override" "second" \
        'A_TASK_PREFIX_ALIASES="app=first app=second"; a_task_repo_prefix app'
    check "$sh" "an alias is cleaned and capped like a derived prefix" "my-alias" \
        'A_TASK_PREFIX_ALIASES="app=My_Alias"; a_task_repo_prefix app'
    check "$sh" "no prefix falls back to the bare ticket, unchanged" "ABC-123" \
        'a_task_session_name ABC-123 ""'
    check "$sh" "a repo name with nothing usable falls back to the bare ticket" "ABC-123" \
        'a_task_session_name ABC-123 "$(a_task_repo_prefix ___)"'
    check "$sh" "same input gives the same name every time" "same" \
        'a="$(a_task_session_name ABC-1 "$(a_task_repo_prefix x-y-z-long-name-here)")"; b="$(a_task_session_name ABC-1 "$(a_task_repo_prefix x-y-z-long-name-here)")"; [ "$a" = "$b" ] && echo same'
    check "$sh" "the tab name matches the session name" "ios-abc-123-add-login-page" \
        'a_task_zellij_tab_name ABC-123 ios add-login-page'
    check "$sh" "the feature part follows the ticket" "ios-abc-123-list-filter" \
        'a_task_session_name ABC-123 ios list-filter'
    check "$sh" "a long feature slug keeps only the whole words that fit" "api-abc-123-accept-bucketing" \
        'a_task_session_name ABC-123 api accept-bucketing-id-header'
    check "$sh" "a first word longer than the cap is cut" "abcdefghijklmnop" \
        'a_task_short_feature abcdefghijklmnopqrstuvwxyz-more'
    check "$sh" "A_TASK_NAME_FEATURE_MAX changes the feature cap" "add" \
        'A_TASK_NAME_FEATURE_MAX=5 a_task_short_feature add-login-page'
    check "$sh" "a free-text label is cleaned like a slug" "ios-abc-123-list-filter" \
        'a_task_session_name ABC-123 ios "List Filter!"'
    check "$sh" "a feature with no prefix still names the task" "abc-123-list-filter" \
        'a_task_session_name ABC-123 "" list-filter'
    check "$sh" "a ticket-only branch has no feature part" "ios-abc-123" \
        'a_task_session_name ABC-123 ios ""'
done

echo ""
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]

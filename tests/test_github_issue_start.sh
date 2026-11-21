#!/usr/bin/env bash
# The old launcher name must preserve the current launcher's arguments and status.
set -euo pipefail
root="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp "$root/scripts/a_c_github_issue_start" "$work/a_c_github_issue_start"
printf '%s\n' '#!/bin/bash' 'printf "[%s]\n" "$@"' 'exit 17' > "$work/a_c_github_issue_fix"
rc=0
out="$(bash "$work/a_c_github_issue_start" 'owner/repo#42' 'two words' -y -- --model test-model)" || rc=$?
[ "$rc" -eq 17 ]
expected=$'[owner/repo#42]\n[two words]\n[-y]\n[--]\n[--model]\n[test-model]'
[ "$out" = "$expected" ]
printf '%s\n' 'PASS: compatibility launcher preserves arguments and exit status'

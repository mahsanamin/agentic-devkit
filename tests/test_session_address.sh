#!/usr/bin/env bash
#
# Behaviour fixture for scripts/a_s_session_address: finding the uds: address of a live
# Claude session by name, from the sessions registry when it has an entry and from the
# process table when it does not.
#
# Everything is faked: the process list is a file (A_CC_PS_FILE), the registry and the
# socket dir are temp dirs, and the sockets are real unix sockets bound in that temp dir.
# Nothing on the machine is read.
#
# Usage: bash tests/test_session_address.sh

set -uo pipefail

REPO_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUT="$REPO_ROOT/scripts/a_s_session_address"

command -v python3 >/dev/null 2>&1 || { echo "skip: python3 is needed to create test sockets"; exit 0; }

# Short base path: a unix socket path is limited to about 104 bytes.
T="$(mktemp -d /tmp/sa.XXXXXX)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/sessions" "$T/socks" "$T/other"

# mksock <path>: create a unix socket file at path.
mksock() { python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$1"; }

L="Fri Sep 25 15:56:52 2026"
cat > "$T/ps" <<EOF
  101 $L /usr/local/bin/claude -n alpha do the thing
  102 $L claude --name beta a prompt that mentions -n decoy
  103 $L claude --name=gamma
  104 $L claude -n dup first
  105 Fri Sep 25 16:10:00 2026 claude -n dup second
  106 $L claude -n nosock
  107 $L vim -n alpha
  108 $L claude -n alpha-long prefix check
  109 $L node /opt/lib/claude-code/cli.js -n nodey
  201 $L claude --resume abc
  202 $L claude -n oldname
EOF
for p in 101 102 103 104 105 107 108 109 201 202; do mksock "$T/socks/$p.sock"; done

# Registry entries: 201 is live with a name only here, 202 is live and named in both
# places (the registry name wins), 300 is a dead pid.
mksock "$T/other/201.sock"
printf '{"pid":201,"messagingSocketPath":"%s","name":"registered","nameSource":"derived"}\n' "$T/other/201.sock" > "$T/sessions/201.json"
printf '{"pid":202,"messagingSocketPath":"%s","name":"renamed","nameSource":"user"}\n' "$T/socks/202.sock" > "$T/sessions/202.json"
printf '{"pid":300,"messagingSocketPath":"%s","name":"ghost"}\n' "$T/socks/300.sock" > "$T/sessions/300.json"

run() {
    env -i HOME="$T" PATH="$PATH" A_CC_PS_FILE="$T/ps" A_CC_SESSIONS_DIR="$T/sessions" \
        A_CC_SOCK_DIR="$T/socks" bash "$SUT" "$@"
}

pass=0; fail=0

# check <description> <expected exit> <expected stdout> <args...>
check() {
    local desc="$1" want_rc="$2" want="$3" got rc
    shift 3
    got="$(run "$@" 2>/dev/null)"; rc=$?
    if [ "$rc" = "$want_rc" ] && [ "$got" = "$want" ]; then
        pass=$((pass+1)); printf '  ok   %s\n' "$desc"
    else
        fail=$((fail+1)); printf 'FAIL   %s: want rc=%s "%s", got rc=%s "%s"\n' "$desc" "$want_rc" "$want" "$rc" "$got"
    fi
}

# check_grep <description> <expected exit> <pattern expected in stdout+stderr> <args...>
check_grep() {
    local desc="$1" want_rc="$2" pat="$3" got rc
    shift 3
    got="$(run "$@" 2>&1)"; rc=$?
    if [ "$rc" = "$want_rc" ] && printf '%s\n' "$got" | grep -q -- "$pat"; then
        pass=$((pass+1)); printf '  ok   %s\n' "$desc"
    else
        fail=$((fail+1)); printf 'FAIL   %s: want rc=%s and /%s/, got rc=%s:\n%s\n' "$desc" "$want_rc" "$pat" "$rc" "$got"
    fi
}

check "-n <name> resolves from the process table" 0 "uds:$T/socks/101.sock" alpha
check "--name <name> resolves, and a later -n in the prompt is ignored" 0 "uds:$T/socks/102.sock" beta
check "--name=<name> resolves" 0 "uds:$T/socks/103.sock" gamma
check "node running a claude entry point counts as claude" 0 "uds:$T/socks/109.sock" nodey
check "the registry name resolves to its own socket path" 0 "uds:$T/other/201.sock" registered
check "a pid in both sources uses the registry name" 0 "uds:$T/socks/202.sock" renamed
check "the command-line name of a registered pid is not listed twice" 1 "" oldname
check "a name is matched exactly, not as a prefix" 1 "" alpha-lo
check "a session with no socket is not reported" 1 "" nosock
check "a registry entry for a dead pid is not reported" 1 "" ghost
check "the prompt text is not read as a name" 1 "" decoy
check_grep "several matches exit 3 and list each with pid" 3 "uds:$T/socks/105.sock  pid 105  started Fri Sep 25 16:10:00 2026" dup
check_grep "no match lists the live named sessions" 1 "alpha " missing
check_grep "--list shows registry sessions" 0 "registered .*uds:$T/other/201.sock .*(registry)" --list
check_grep "--list shows process sessions" 0 "alpha .*uds:$T/socks/101.sock .*(process)" --list
check_grep "an unknown option is a usage error" 2 "unknown option" --bogus
check_grep "no argument is a usage error" 2 "Usage"

# A_CC_SOCK_DIR unset: the dir of CLAUDE_CODE_MESSAGING_SOCKET is used.
got="$(env -i HOME="$T" PATH="$PATH" A_CC_PS_FILE="$T/ps" A_CC_SESSIONS_DIR="$T/sessions" \
    CLAUDE_CODE_MESSAGING_SOCKET="$T/socks/999.sock" bash "$SUT" alpha 2>/dev/null)"
if [ "$got" = "uds:$T/socks/101.sock" ]; then
    pass=$((pass+1)); echo "  ok   the socket dir comes from CLAUDE_CODE_MESSAGING_SOCKET"
else
    fail=$((fail+1)); echo "FAIL   the socket dir comes from CLAUDE_CODE_MESSAGING_SOCKET: got \"$got\""
fi

echo ""
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]

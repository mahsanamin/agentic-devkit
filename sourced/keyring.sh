#!/bin/bash
# keyring.sh: keep a locked GNOME login keyring from hanging tools on a Linux
# machine with no desktop login. Details in scripts/a_c_keyring_unlock.
#
# Two parts:
# 1. When an interactive shell starts and the keyring is locked, ask for the
#    password once (a_c_keyring_unlock). The first terminal after a boot does it.
#    Set A_KEYRING_AUTO_UNLOCK=0 to turn this off.
# 2. Wrap acli so a locked keyring fails straight away with a clear message
#    instead of hanging. This also covers non-interactive shells, such as the
#    ones agents run commands in.
#
# Does nothing on macOS or on a Linux machine without gnome-keyring.

if [ "$(uname -s)" = "Linux" ] && command -v gnome-keyring-daemon >/dev/null 2>&1; then
  # Full path: this file is sourced before scripts/ is put on PATH.
  _a_keyring_cmd="$MY_WORKFLOW_DIR/scripts/a_c_keyring_unlock"

  case $- in
    *i*)
      if [ "${A_KEYRING_AUTO_UNLOCK:-1}" != "0" ] && [ -t 0 ] \
         && ! bash "$_a_keyring_cmd" --check 2>/dev/null; then
        bash "$_a_keyring_cmd"
      fi
      ;;
  esac

  acli() {
    if ! bash "$MY_WORKFLOW_DIR/scripts/a_c_keyring_unlock" --check 2>/dev/null; then
      echo "acli: the login keyring is locked, so acli would hang reading its token." >&2
      echo "Run a_c_keyring_unlock in a terminal, then try again." >&2
      return 1
    fi
    command acli "$@"
  }
fi

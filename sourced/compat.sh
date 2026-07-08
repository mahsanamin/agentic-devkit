#!/bin/bash
# compat.sh: transitional back-compat aliases for commands renamed in the
# a_ -> a_c_ / a_s_ / a_g_ naming refactor. Lets old muscle-memory names keep
# working after consolidating the shell onto this repo. Safe to delete once the
# old names are unlearned; nothing here is a dependency.

# Non-git command functions (were a_process* / a_restart_login / a_workflow_doctor).
alias a_processList='a_c_process_list'
alias a_processKill='a_c_process_kill'
alias a_process_kill_on_port='a_c_process_kill_on_port'
alias a_restart_login='a_c_restart_login'
alias a_workflow_doctor='a_c_workflow_doctor'

# Git helper renamed (same behavior: print the origin remote url).
alias a_g_remote='a_g_origin_url'

# Renamed scripts on PATH.
alias a_slack_inbox='a_c_slack_inbox'
alias a_time_range.sh='a_s_time_range.sh'
alias a_uninstall_app.sh='a_c_uninstall_app.sh'

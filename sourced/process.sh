#!/bin/bash
function a_processList() {
    if [[ $1 != "" ]]; then
            processName="$1"
        else
            echo "Process Name is must"
            return 1
    fi
    ps aux | grep $processName
    processName
}

function a_processKill() {
    if [[ $1 != "" ]]; then
        processName="$1"
    else
        echo "Process Name is must \n"
        return 1
    fi

    echo "Process List\n"
    ps aux | grep $processName | grep -v grep | awk '{print $2}'

    echo "Kill Processes List\n"
    kill -9 $(ps aux | grep $processName | grep -v grep | awk '{print $2}')
}

alias a_restart_login="sudo killall loginwindow"

function a_process_kill_on_port() {
  local port=$1

  if [[ -z $port ]]; then
    echo "Usage: kill_process_on_port <port>"
    return 1
  fi

  local process_ids=$(lsof -ti :$port)

  if [[ -z $process_ids ]]; then
    echo "No process found running on port $port"
    return 0
  fi

  echo "Will kill Process List:"
  echo $process_ids

  # Kill the process(es)
  if kill -9 $(lsof -ti :$port); then
    echo "Processes $process_ids killed successfully"
  else
    echo "Failed to kill processes $process_ids"
  fi
}

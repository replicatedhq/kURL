#!/usr/bin/env bash

source /opt/kurl-testgrid/common.sh

function runJoinCommand() 
{
  joinCommand=$(get_join_command)
  primaryJoin=$(echo "$joinCommand" | sed 's/{.*primaryJoin":"*\([0-9a-zA-Z=]*\)"*,*.*}/\1/' | base64 -d)
  eval $primaryJoin
  KURL_EXIT_STATUS=$?
}

function runAirgapJoinCommand()
{
  curl -sSL -o install.tar.gz "$KURL_URL"
  tar -xzf install.tar.gz
  joinCommand=$(get_join_command)
  primaryJoin=$(echo "$joinCommand" | sed 's/{.*primaryJoin":"*\([0-9a-zA-Z=]*\)"*,*.*}/\1/' | base64 -d)
  eval $primaryJoin
  KURL_EXIT_STATUS=$?
}

function main()
{
  green "setup runner"
  setup_runner

  green "report node in waiting for join command"
  report_status_update "waitJoinCommand"

  green "wait for join command"
  wait_for_join_commandready
  
  green "run join command"
  if [ "$(is_airgap)" = "1" ]; then
    runAirgapJoinCommand 
  else
    runJoinCommand
  fi
  
  if [ $KURL_EXIT_STATUS -ne 0 ]; then
    report_status_update "failed"
    send_logs
    exit 1
  fi
  
  green "report success join"
  report_status_update "success"
  send_logs
}

main

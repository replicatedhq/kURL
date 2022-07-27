#!/usr/bin/env bash

source /opt/kurl-testgrid/common.sh

function runJoinCommand() 
{
  joinCommand=$(get_join_command)
  secondaryJoin=$(echo "$joinCommand" | sed 's/{.*secondaryJoin":"*\([0-9a-zA-Z=]*\)"*,*.*}/\1/' | base64 -d)
  eval $secondaryJoin
  KURL_EXIT_STATUS=$?
}

function runAirgapJoinCommand()
{
  curl -sSL -o install.tar.gz "$KURL_URL"
  tar -xzf install.tar.gz
  joinCommand=$(get_join_command)
  secondaryJoin=$(echo "$joinCommand" | sed 's/{.*secondaryJoin":"*\([0-9a-zA-Z=]*\)"*,*.*}/\1/' | base64 -d)
  eval $secondaryJoin
  KURL_EXIT_STATUS=$?
}

function main() 
{
  green "setup runner"
  setup_runner
  
  green "report node in waiting for join command"
  report_status_update "waiting_join_command"

  green "wait for join command"
  secondaryJoin=$(wait_for_join_commandready)
  green "$secondaryJoin"
  
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

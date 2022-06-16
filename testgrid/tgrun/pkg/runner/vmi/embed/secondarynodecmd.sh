#!/usr/bin/env bash

source /opt/kurl-testgrid/common.sh

function runJoinCommand() 
{
  joinCommand=$(get_join_command)
  secondaryJoin=$(echo "$joinCommand" | sed 's/{.*secondaryJoin":"*\([0-9a-zA-Z=]*\)"*,*.*}/\1/' | base64 -d)
  eval $secondaryJoin
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
  runJoinCommand
  if [ $KURL_EXIT_STATUS -ne 0 ]; then
    report_status_update "failed"
    send_logs
    exit 1
  fi

  green "report success join"
  report_status_update "joined"

  green "send logs after join"
  send_logs

  green "wait till initprimary is done"
  wait_for_initprimary_done
  
  green "send log"
  send_logs

  report_status_update "success"
}

main

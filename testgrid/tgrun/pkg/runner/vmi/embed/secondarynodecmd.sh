#!/usr/bin/env bash

set -x

function green()
{
  text="${1:-}"
  echo -e "\033[32m$text\033[0m"
}

function setup_runner() {
    setenforce 0 || true # rhel variants
    sysctl vm.overcommit_memory=1
    sysctl kernel.panic=10
    sysctl kernel.panic_on_oops=1

    echo "$TEST_ID" > /tmp/testgrid-id

    if [ ! -c /dev/urandom ]; then
        /bin/mknod -m 0666 /dev/urandom c 1 9 && /bin/chown root:root /dev/urandom
    fi

    echo "OS INFO:"
    cat /etc/*-release
    echo ""
}

function get_join_command()
{
  joinCommand=$(curl -X GET -f "$TESTGRID_APIENDPOINT/v1/instance/$TEST_ID/join-command")
  echo "${joinCommand}" 
}

function send_logs() 
{
    curl -X PUT -f --data-binary "@/var/log/cloud-init-output.log" "$TESTGRID_APIENDPOINT/v1/instance/$NODE_ID/node-logs"
}

function wait_for_join_commandready()
{
  i=0
  while true
    do
        joinCommand=$(get_join_command)
        secondaryJoin=$(echo "$joinCommand" | sed 's/{.*secondaryJoin":"*\([0-9a-zA-Z]*\)"*,*.*}/\1/')
        if [ "$secondaryJoin" != "" ]; then
            echo "$secondaryJoin"
            break
        fi
        i=$((i+1))
        if [ $i -gt 10 ]; then
            report_status_update "failed"
            send_logs
            exit 0
        fi
        sleep 120
    done
  echo 
}

function remove_first_element()
{
  local list=("$@")
  local rest_of_list=("${list[@]:1}")
  echo "${rest_of_list[@]}"
}

function runJoinCommand() 
{
  joinCommand=$(get_join_command)
  secondaryJoin=$(echo "$joinCommand" | sed 's/{.*secondaryJoin":"*\([0-9a-zA-Z=]*\)"*,*.*}/\1/' | base64 -d)
  eval $secondaryJoin
}

function report_status_update()
{
  curl -X PUT -f -H "Content-Type: application/json" -d "{\"status\": \"$1\"}" "$TESTGRID_APIENDPOINT/v1/instance/$NODE_ID/node-status"
}

function wait_for_initprimary_done()
{
  i=0
  while true
    do
        response=$(curl -X GET -f "$TESTGRID_APIENDPOINT/v1/instance/$TEST_ID/status")
        runStatus=$(echo "$response" | sed 's/{.*isSuccess":"*\([0-9a-zA-Z]*\)"*,*.*}/\1/')
        if [[ "$runStatus" = "true" ]]; then
            echo "initprimary status finsihed the test"
            break
        fi
        i=$((i+1))
        if [ $i -gt 10 ]; then
            report_status_update "failed"
            send_logs
            exit 0
        fi
        sleep 100
    done
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

  green "report success join"
  report_status_update "joined" 

  green "send logs after join"
  send_logs

  green "wait till initprimary is done"
  wait_for_initprimary_done
  
  green "send log"
  send_logs
}

main

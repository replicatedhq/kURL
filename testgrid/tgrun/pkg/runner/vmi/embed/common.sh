#!/usr/bin/env bash

set -x

function green()
{
  text="${1:-}"
  echo -e "\033[32m$text\033[0m"
}

function command_exists() 
{
    command -v "$@" > /dev/null 2>&1
}

function setup_runner() 
{
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

function send_logs() 
{
  cat /var/log/cloud-init-output.log | grep -v '"__CURSOR" :' > /tmp/testgrid-node-logs # strip junk
  curl -X PUT -f --data-binary "@/tmp/testgrid-node-logs" "$TESTGRID_APIENDPOINT/v1/instance/$NODE_ID/node-logs"
}

function report_status_update()
{
  curl -X PUT -f -H "Content-Type: application/json" -d "{\"status\": \"$1\"}" "$TESTGRID_APIENDPOINT/v1/instance/$NODE_ID/node-status"
}

function get_initprimary_status()
{
  primaryNodeId="${TEST_ID}-initialprimary"
  response=$(curl -X GET -f "$TESTGRID_APIENDPOINT/v1/instance/$primaryNodeId/node-status")
  primaryNodeStatus=$(echo "$response" | sed 's/{.*status":"*\([0-9a-zA-Z]*\)"*,*.*}/\1/')
  echo "$primaryNodeStatus"
}
function get_join_command()
{
  joinCommand=$(curl -X GET -f "$TESTGRID_APIENDPOINT/v1/instance/$TEST_ID/join-command")
  echo "${joinCommand}" 
}

function wait_for_join_commandready()
{
  i=0
  while true
    do
        primaryNodeStatus=$(get_initprimary_status)
        if [[ "$primaryNodeStatus" = "joinCommandStored" ]] ; then
            echo "join command is ready"
            break
        elif [[ "$primaryNodeStatus" = "failed" ]] ; then
            report_status_update "failed"
            send_logs
            exit 1    
        fi
        i=$((i+1))
        if [ $i -gt 20 ]; then
            report_status_update "failed"
            send_logs
            exit 1
        fi
        sleep 60
    done
  echo 
}

function wait_for_initprimary_done()
{
  i=0
  while true
    do
        primaryNodeStatus=$(get_initprimary_status)
        if [[ "$primaryNodeStatus" = "success" ]]; then
            echo "initprimary status finsihed the test"
            break
        elif [[ "$primaryNodeStatus" = "failed" ]] ; then
          report_status_update "failed"
          send_logs
          exit 1 
        fi
        i=$((i+1))
        if [ $i -gt 20 ]; then
            report_status_update "failed"
            send_logs
            exit 1
        fi
        sleep 60
    done
}

function is_airgap()
{
  airgap=
  if echo "$KURL_URL" | grep -q "\.tar\.gz$" ; then
      airgap=1
  fi
  echo $airgap
}

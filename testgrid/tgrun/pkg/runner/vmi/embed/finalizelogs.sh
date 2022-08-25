#!/usr/bin/env bash

function send_logs()
{
  cat /var/log/cloud-init-output.log | grep -v '"__CURSOR" :' > /tmp/testgrid-node-logs # strip junk
  curl -X PUT -f --data-binary "@/tmp/testgrid-node-logs" "$TESTGRID_APIENDPOINT/v1/instance/$NODE_ID/node-logs"
}

send_logs

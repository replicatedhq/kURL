#!/usr/bin/env bash

function adddate() 
{
  while IFS= read -r line; do
      printf '%s %s\n' "$(date --rfc-3339=seconds)" "$line";
  done
}

function main()
{
  chmod +x /opt/kurl-testgrid/runcmd.sh
  /opt/kurl-testgrid/runcmd.sh | adddate
}

main

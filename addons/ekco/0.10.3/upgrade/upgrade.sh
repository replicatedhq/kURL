#!/bin/sh

set -e

export KUBECONFIG=/etc/kubernetes/admin.conf

if [ ! -f /opt/ekco/upgrades.txt ]; then
    touch /opt/ekco/upgrades.txt
fi

latest=$(curl -I $KURL_URL/$INSTALLER_ID | grep -i 'X-Kurl-Hash' | awk '{ print $2 }' | tr -d '\r')
last=$(tail -n1 /opt/ekco/upgrades.txt | awk '{ print $NF }')

if [ "$last" = "$latest" ]; then
    echo "No kurl upgrades available"
    exit 0
fi

cd /tmp
curl -L $KURL_URL/$INSTALLER_ID | sudo bash -s yes auto-upgrades-enabled
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") $latest" >> /opt/ekco/upgrades.txt

echo "Kurl upgrade applied"

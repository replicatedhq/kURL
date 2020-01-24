#!/bin/bash
sed -i 's/localhost:8800/###_HOSTNAME_###/g' /web/dist/index.html

/kotsadm api
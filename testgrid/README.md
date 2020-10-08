# Testgrid

Testgrid is a testing solution for kurl, and is intended to be used to validate that a given installer configuration runs to completion successfully.
It can be accessed at https://testgrid.kurl.sh, and runs specs defined at <TODO>.

## Server

The Testgrid runner runs as a binary on a server with k8s and kubevirt installed.
The following systemctl service is sufficient:
```
[Unit]
Description=tgrun

[Service]
Type=simple
RestartSec=5s
StandardOutput=syslog
StandardError=syslog
WorkingDirectory=/root
SyslogIdentifier=tgrund
Environment="KUBECONFIG=/etc/kubernetes/admin.conf"
Environment="HOME=/root"
Environment="PATH=/root/.krew/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/root/tgrun run

[Install]
WantedBy=multi-user.target
```
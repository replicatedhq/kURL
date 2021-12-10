INSTALLER_YAML="apiVersion: cluster.kurl.sh/v1beta1
kind: Installer
metadata:
  name: 49d8de4
spec:
  kurl:
    ipv6: true
  kubernetes:
    version: 1.19.15
  containerd:
    version: 1.4.6
  antrea:
    version: 1.2.1
  rook:
    version: 1.5.12
  kotsadm:
    version: 1.58.1
  ekco:
    version: 0.12.0
    enableInternalLoadBalancer: true
  registry:
    version: 2.7.1
"

## Troubleshooting

Problem: nodes in cluster can't ping6 each other.
Symptom: `ip -6 route` shows no default route
Solution: `sudo ip -6 route add default dev ens5`

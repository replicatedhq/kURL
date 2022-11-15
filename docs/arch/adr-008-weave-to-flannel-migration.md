# ADR 8: Weave to Flannel Migration

## Context

As proposed in ADR 6, the future CNI of kURL will be Flannel.
However, almost all existing installations are running Weave.

A migration path must be provided for those instances.

There were two general proposals for a migration path.
One was to use Multus-CNI to allow using both Flannel and Weave at the same time before stripping out Weave, allowing an upgrade while only taking down one node at once.
The other was to run a migration that removed Weave from all instances simultaneously before installing Flannel.
This would be far simpler, not require an additional IP range, and not require Multus to remain in the cluster going forwards.
It would also require 'stopping the world' and cause downtime.
In testing, this downtime was under 5 minutes when running commands manuall on a 3 node cluster.

## Decision

Provide a stop-the-world migration path to move from Weave to Flannel.

## Solution

Create a script to do the following:

1. Synchronize execution on all cluster nodes to minimize downtime
2. Uninstall weave, removing iptables rules and host files
3. Edit kubeadm.conf on all primary nodes and run kubeadm init (or potentially edit config files directly)
4. Install flannel
5. Stop kubelet, flush iptables, restart containerd and start kubelet
6. Wait for nodes to be ready, and then recreate cluster-networking pods (kube-system, then CSI, then everything else)
7. Run an inter-container (and inter-node) networking check

This script would be able to be called explicitly from `tasks.sh` or after opt-in from the user as part of the kURL upgrade process.

## Status

Accepted

## Consequences

Users will be able to move from Weave to Flannel, but downtime will need to be scheduled to do so.

A failed migration may result in a cluster down scenario.
Manual remediation would be required.
If failures were frequent (either in testing or after deployment) an automatic remediation/rollback script could be created.

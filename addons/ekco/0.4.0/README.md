
[Embedded Kurl cluster operator (EKCO)](https://github.com/replicatedhq/ekco) is responsible for performing various operations to maintain the health of a Kurl cluster. For more information see the documentation [here](https://github.com/replicatedhq/ekco).

This addon deploys it to the `kurl` namespace.

## Options

- `ekco-node-unreachable-toleration-duration`: How long a Node must be unreachable before considered dead (default 5m).
- `ekco-should-enable-purge-nodes`: Watch the cluster for dead nodes and remove them
- `ekco-min-ready-master-node-count`: Don't purge the node if it will result in less than this many ready masters.
   Only applicable if node purging is enabled.
- `ekco-min-ready-worker-node-count`: Don't purge the node if it will result in less than this many ready workers
   Only applicable if node purging is enabled.
- `ekco-should-disable-clear-nodes`: Don't force delete pods on unreachable stuck in the terminating state
- `ekco-disable-should-maintain-rook-storage-nodes`: Whether to maintain the list of nodes to use in the CephCluster config.
   This also enables control of the replication factor of ceph pools, scaling up and down with the number of nodes in the cluster.
- `ekco-disable-should-install-reboot-service`: Whether to disable the reboot service, responsible for graceful node termination.
- `rook-version`: Version of Rook to manage

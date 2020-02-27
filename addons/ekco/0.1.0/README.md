
[Embedded Kurl cluster operator (EKCO)](https://github.com/replicatedhq/ekco) is responsible for performing various operations to maintain the health of a Kurl cluster. For more information see the documentation [here](https://github.com/replicatedhq/ekco).

This addon deploys it to the `kurl` namespace.

## Options

- `ekco-node-unreachable-toleration-duration`: How long a Node must be unreachable before considered dead (default 1h).
- `ekco-min-ready-master-node-count`: Don't purge the node if it will result in less than this many ready masters
- `ekco-min-ready-worker-node-count`: Don't purge the node if it will result in less than this many ready workers
- `ekco-disable-should-maintain-rook-storage-nodes`: Whether to maintain the list of nodes to use in the CephCluster config.
   This also enables control of the replication factor of ceph pools, scaling up and down with the number of nodes in the cluster.

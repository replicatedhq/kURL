# ADR 9: OpenEBS to OpenEBS + Rook Migration

## Context

Single node installs should not use Rook, as doing so adds complexity, increases resource usage, and invites disk corruption.
Multi node installs very often require distributed storage, best provided by Rook.

Many customers will move from a single-node install to a multi-node install as circumstances change.
This migration should be as simple as possible.
Vendors generally should also not need to specify multiple installer specs for single and multi-node installs.

## Decision

Provide a migration path from OpenEBS to OpenEBS + Rook, triggered by the presence of 3+ nodes.

## Solution

A new field, `rook.minimumNodeCount`, will be added to the rook config. When set to a value of 2 or more (requires openebs localpv to be present), the rook operator will be installed on single node installs, but no ceph cluster will be created.
When unset or set to a value of 1, the Rook storage class will function as at does today, backed by Rook-Ceph.

An example spec is provided below:

```yaml
spec:
  rook:
    version: "1.10.x"
    storageClassName: "scaling"
    minimumNodeCount: 3
  openebs:
    version: "3.4.x"
    isLocalPVEnabled: true
    localPVStorageClassName: "local"
```

When configured with `rook.minimumNodeCount >= 21 and installed on a single node, two storageclasses will be available - "scaling" and "local". 
The default storage class will be "scaling", and both storage classes will be backed by openebs localpv.

When the third node is added, a Ceph cluster will be created by the EKCO operator.
When that Ceph cluster becomes healthy (with at least 3 replicas), the "distributed" storageclass will be created using rook-ceph.
However, a migration will not begin until one of four things occurs:

1. The user joins the third(+) node to the cluster, and accepts a prompt to migrate storage
2. The user approves the migration in KOTS
3. The user runs `install.sh` on a primary node, and accepts a prompt to migrate storage
4. The user runs the `migrate-multinode-storage` command in `tasks.sh` from a primary node

The migration process will NOT be triggered automatically.
While the migration process is available to be triggered, a banner will be shown in the KOTS browser UI indicating that the migration is available, and that the cluster is currently in an undesirable state.

The migration process will be as follows:
A request is made to an authenticated EKCO endpoint approving a migration.
If MinIO is present, KOTS will be scaled down, and the existing `sync-object-store` Go command will be used to migrate data from MinIO to Rook.
KOTS, Registry, and Velero will then be updated to use the Rook object store, and KOTS scaled back up.
After MinIO data is migrated and its consumers updated, the MinIO statefulset and namespace will be deleted.
`pvmigrate` will then be used to migrate all data from the "scaling" storageclass to the "distributed" storageclass, and the default storageclass will be changed to "distributed".
This process does involve downtime, caused by stopping pods using "scaling" storage, and is why we require the migration to be manually initiated.

In this way, applications can specifically request storage that will always be local to a node (with the "local" storageclass), or storage that will be distributed across the cluster (with the "distributed" storageclass).
Using the "scaling" storageclass directly (instead of merely using the default storageclass) would be an application linting error.

### Additional Details

In order for the migration to be triggered when joining a node, a few things will need to be added or changed.

There will need to be a way for non-primary nodes to know if a migration is available, and if so, to prompt the user to approve it.
Once the migration has started, there should also be a way to for these nodes to know the progress of the migration and if it has completed.

To this end, join scripts will incorporate two new parameters, one for an IP address+port to check for status, and another for an auth token.
The IP address will be a cluster-internal service, as once the node has been joined we will be able to reach the service from the host.
The auth token will also be available within a configmap within `kurl` namespace in the cluster - not a secret - so that it is also accessible to KOTS.

To use this endpoint effectively, the join script will use it to check the number of nodes in the cluster at the end of the join process.
If there are 3+ nodes, the script will check if a migration is available - and if it is still waiting for Rook to become healthy, it will wait for up to 5 minutes for this to happen.
If the migration is available, then the user will be prompted for approval, with a timeout of < 5 minutes.

Once a migration is in progress, the current status and logs will be available at the endpoint to be polled, and any script that triggers a migration will show them.

## Status

Proposed

## Consequences

Vendors will be able to specify a single spec for single and multi-node installs, with a smooth migration path between the two.

There will be short application downtime migrating between the two storage systems.
This could be mitigated by changing pvmigrate to not stop all pods at once, but it is as yet unknown how this would be accomplished.

Vendor applications will not be able to use the kurl-provided object store with this configuration, as this object store will change endpoints during the migration process and not preserve user credentials.
It is believed this will not impact any vendors.

Clusters may run with 3+ nodes and not use Rook for some time if the user does not approve the migration.

Join scripts will wait for user input to approve a migration, which may be undesirable in some environments.

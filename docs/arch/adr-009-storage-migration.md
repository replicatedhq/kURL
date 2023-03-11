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

A new field, "minimum node count", will be added to the rook config. (minimum value 2, requires openebs localpv to be present)
When it is set, the rook operator will be installed on single node installs, but no ceph cluster will be created.

An example spec is provided below:

```yaml
spec:
  rook:
    version: "1.10.x"
    storageClassName: "distributed"
    minimumNodeCount: 3
  openebs:
    version: "3.4.x"
    isLocalPVEnabled: true
    localPVStorageClassName: "local"
```

When installed on a single node, two storageclasses will be available - "scaling" and "local". 
The default storage class will be "scaling", and both storage classes will be backed by openebs localpv.

When the third node is added, a ceph cluster will be created by the EKCO operator.
When that ceph cluster becomes healthy (with at least 3 replicas), the "distributed" storageclass will be created using rook-ceph.
pvmigrate will then be used to migrate all data from the "scaling" storageclass to the "distributed" storageclass, and the default storageclass will be changed to "distributed".
This process does involve stopping pods using "scaling" storage.

In this way, applications can specifically request storage that will always be local to a node (with the "local" storageclass), or storage that will be distributed across the cluster (with the "distributed" storageclass).
Using the "scaling" storageclass directly (instead of merely using the default storageclass) would be an application linting error.

YET TO BE DECIDED:
1. Should the migration be triggered immediately upon adding a third node, or should it be triggered by the user? It can involve application downtime!
   1. Allow the user to trigger the migration with a 'tasks.sh migrate-storage' command.
   2. Provide a prompt in kotsadm that will trigger the migration.
   3. Trigger the migration automatically when the third node is added.
2. What to do with object storage. (should data be migrated from MinIO to Rook, and MinIO deleted?)
   1. Migrate data from MinIO to Rook, and delete MinIO.
   2. Keep MinIO running, and use it for object storage. Disable (or otherwise do not use) Rook's object storage.
   3. Forbid the use of MinIO in automatic migration configs.

## Status

Proposed

## Consequences


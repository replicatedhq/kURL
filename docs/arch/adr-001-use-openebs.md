# ADR 1: Use OpenEBS Local PV Hostpath for Single Node kURL Installations

The initial kURL installation specification defaulted to [Longhorn](https://longhorn.io/) as the volume provisioner. However, the experience with Longhorn has not lived up to our expecatations. Namely, the instability, slow performance and lack of community support for Longhorn has forced us to switch to another storage provisioner.

## Decision

We will use [OpenEBS Local PV Hostpath](https://openebs.io/docs/user-guides/localpv-hostpath) as the default volume provisioner single node Kubernetes clusters.


## Status

Accepted


## Consequences


- Using OpenEBS Local PV Hostpath affords us a better out of the box experience for Replicated vendors and end-users underpinned by the following benefits:
    - Dynamic local volume provisioning
    - Near disk performance for local volumes
    - Data protection through snapshots and clones
    - Backup and Recovery via Velero

- For Single node Kubernetes installations, the end-user assumes the risk of data loss in the event of a node failure. Local volumes are only available from the node where the persistent volume was created.
- In general, for highly available Kubernetes clusters, Rook is the recommend storage provisioner however, there are valid use cases that fit well for using local PV hostpath on multi node Kubernetes clusters. They are:
    1. When a workload has builtin data replication features
    2. When a workload leverages a Storage appliance for data replication and failover. For example, a storage subsystem that is mounted on a path in the node which is then used as the hostpath local persistent volume on multiple nodes
- The requirements for using OpenEBS local PV hostpath are minimal:
    - Kubernetes 1.18 version and higher
    - No minimum CPU and Memory the [local-provisioner deployment](https://github.com/openebs/charts/blob/d-master/charts/openebs/templates/deployment-local-provisioner.yaml)
- Limitations
    - Volume size is not enforced by OpenEBS. This means that an application could fill up the disk on the node and potentially cause an outage.
- [kurl-api](https://github.com/replicatedhq/kURL-api/pull/12) will need to change so that the `latest` spec is returned with OpenEBS
- Update [kurl.sh](https://github.com/replicatedhq/kurl.sh/pull/868) to show OpenEBS as the default sotrage provisioner add-on
- Update the [vendor portal](https://github.com/replicatedhq/vandoor/pull/2381) so that the defalt kURL spec shows OpenEBS configured as local PV instead of Longhorn


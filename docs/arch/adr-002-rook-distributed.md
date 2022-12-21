# ADR 2: Use Rook as provisioner for Multi Node kURL Installations

The initial kURL installation specification defaulted to [Longhorn](https://longhorn.io/) as the volume provisioner for both Single and Multi-node deployments.
However, the experience with Longhorn has not lived up to our expectations.
Namely, the instability, slow performance, and lack of community support for Longhorn have forced us to switch to another storage provisioner.
For Single node cluster deployments, the default storage provisioner will be delivered, as per linked ADR, by [OpenEBS](https://github.com/replicatedhq/kURL/blob/main/docs/arch/adr-001-use-openebs.md) while for Multi-node clusters this role starts to be fulfilled by [Rook](https://rook.io/docs/rook/v1.10/Getting-Started/intro/).

- These are some of the benefits of using Rook as our default Storage Provisioner:
    - Active and engaging community
    - Excellent scaling capabilities
    - Provides file, block, and object storage (AWS S3 compatible API)
    - Automatic failover in case of node failures
    - Tunable number of data replicas (allows for data replication and resilience to failures)
    - Data distribution across multiple nodes
    - Cluster auto-join of any spare block device or new node
    - Uses a dedicated block device in each node
- These are some of the drawbacks of using Rook
    - Requires for an extra (free) block device to be present in each of the nodes
    - Requires at least three nodes in the cluster
    - Requires more hardware (RAM and CPU) to be available in each node
    - May be slower (performance) than other options in some scenarios (networking)
    - Extra complexity in maintaining (more moving pieces)
- Ekco operator already executes some tasks on the users' behalf
    - The number of `replicas` is automatically tuned according to the number of nodes in the cluster
    - Each new node in the cluster is automatically added to the Rook cluster
- Regarding hardware requirements
    - At least one free block device needs to be available in each of the cluster nodes
    - It is recommended at least 16Gb of available RAM in each node
    - It is recommended each node of the cluster to have at least 4 CPUs available

## Decision

We will recommend [Rook](https://rook.io/docs/rook/v1.10/Getting-Started/intro/) as the default storage provisioner for multi-node embedded clusters.
We won't recommend Rook deployments for single-node embedded clusters.

## Status

Accepted

## Consequences

- Ekco operator's replicas/nodes management code will need to be mantained and possibly changed in the future as new versions of Rook are released.
- The hardware requirements must be stated in the documentation
- Users need to be informed employing documentation and "warnings" in kurl.sh that deploying Rook in a Single node cluster is not recommended
- Our recommendation for Rook in multi-node deployments should be implemented through documentation and "advises" in kurl.sh
- As our Storage provisioner recommendation differs from a single-node to a multi-node setup an automatic migration will need to be implemented and maintained by the team (possibly as part of Ekco operator)

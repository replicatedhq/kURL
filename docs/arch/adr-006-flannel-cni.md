# ADR 6: Flannel CNI

## Context

As offering multiple options for each type of add-ons has proven challenging from both a maintenance and support perspective, we would like to converge on a single CNI of choice.

Today we offer both Weave and Antrea CNI kURL add-ons.
Weave is no longer being [actively developed](https://github.com/weaveworks/weave/issues/3948) and is not being considered by this proposal.

Flannel's simplicity and ubiquity make it the best choice for our recommended CNI for kURL installations.
It is relatively easy to install and configure.
From an administrative perspective, it offers a simple networking model that's suitable for most use cases.
It is offered by default by many common Kubernetes cluster deployment tools and in many Kubernetes distributions.
Flannel supports most features of both Weave and Antrea, including IPv6, Encryption and Network Policies through Calico.

Other popular CNI plugins, including Calico and Antrea, offer higher network performance and more flexibility than Flannel, but are unnecessarily complex for our use case.
Calico has an [in-place migration](https://projectcalico.docs.tigera.io/getting-started/kubernetes/flannel/migration-from-flannel) from Flannel available if we ever decide we want to offer a more full featured CNI.

## Decision

Offer Flannel as our recommended CNI add-on.

## Solution

We will add a Flannel CNI add-on to kURL.
We will update the default kURL installer specification to use Flannel, removing Weave as the default CNI.
Flannel will use the VXLAN backend by default with optional support for IPv6.
Additionally, we will have the option to add support for Encryption and Network Policies in the future, if required by our customers.

We will deprecate support for both Weave and Antrea.
We will support a migration path for our end customers from Weave to Flannel.
As no production installations currently use Antrea, we will not offer a migration path off of it.

## Status

Proposed

## Consequences

We will no longer support Encryption or Network Policies unless we choose to add support for these in the future.

We will deprecate and eventually remove the Weave add-on after a determined migration period.

Installations using Weave today will have to migrate to Flannel with potential downtime.

We will deprecate and remove the Antrea add-on.

Installations using Antrea will no longer be supported unless a migration path is added in the future.

Our team will have to learn to support Flannel.

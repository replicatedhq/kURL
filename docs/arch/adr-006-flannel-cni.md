# ADR 5: Flannel CNI

## Context

As offering multiple options for each type of add-ons has proven challenging from both a maintenance and support perspective, we would like to converge on a single CNI of choice.

Today we offer both Weave and Antrea CNI kURL add-ons.
Weave is no longer being [actively developed](https://github.com/weaveworks/weave/issues/3948) and is not being considered by this proposal.

Flannel's simplicity and ubiquity make it a good choice as a our recommended CNI for kURL.
It is relatively easy to install and configure.
From an administrative perspective, it offers a simple networking model that's suitable for most use cases.
It is offered by default by many common Kubernetes cluster deployment tools and in many Kubernetes distributions.
Flannel supports most features of both Weave and Antrea, including IPv6, Encryption and Network Policies through Calico.

Other popular CNI plugins, including Calico and Antrea, offer higher network performance and more flexibility than Flannel, but are unnecessarily complex for our use case.

## Decision

Offer Flannel as our recommended CNI add-on.

## Solution

We will add a Flannel CNI add-on to kURL.
Flannel will use the VXLAN backend by default with optional support for IPv6.
Additionally, we will have the option to add support for Encryption and Network Policies in the future, if required by our customers.

We will support a migration path for our end customers from Weave to Flannel and will deprecate support for Weave.

As no production installations currently use Antrea, we will not offer a migration path off of it.

## Status

Proposed

## Consequences

We will no longer support Encryption or Network Policies unless we choose to add support for these in the future.

Customers using Weave today will have to migrate to Flannel with potential downtime.

Any installations using Antrea will no longer be supported unless a migration path is added in the future.

Our team will have to learn to support Flannel.

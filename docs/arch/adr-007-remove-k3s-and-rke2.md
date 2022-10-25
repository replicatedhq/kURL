# ADR 7: Remove Support for K3s and RKE2 Add-Ons

## Context

These BETA add-ons were originally added by Replicated as part of an experimentation effort around determining a recommended single-node specification for kURL based installs.
Our recommended default spec for single-node has since been determined to be kubeadm plus OpenEBS with LocalPV for storage.

## Decision

Replicated does not intend to support K3s or RKE2 via kURL at this time, and as such, these BETA add-ons are being deprecated rather than pushed to GA.

## Status

Accepted

## Consequences

* We recommend the Replicated customers wanting to install on K3s or RKE2 pursue an existing cluster install method for their Kubernetes application.
* Remove K3s and RKE2 documentation from kurl.sh

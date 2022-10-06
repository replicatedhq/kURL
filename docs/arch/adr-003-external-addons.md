# ADR 3: kURL External Add-On Capability

Today, a new add-on version cannot be released independently of the entire kURL project.
As a result, when the github.com/replicatedhq/kots project is released, a kURL release must follow.
Any changed staged for a kURL release must be ready or the KOTS release will be blocked.
Additionally, a maintainer of the kURL project must be available to make the release.

## Decision

We will add support for releasing add-ons independent of the kURL project.
Some add-ons will continue to be released with kURL.
The KOTS add-on will be the first to leverage this new feature.

An external add-on will publish a versions.json file to a publicly accessible URL with metadata describing versions it has published.
This data will contain the version, url of the add-on package, and the kURL version compatibility range.

versions.json

```json
[
  {
    "version": "1.85.0",
    "url": "https://kots-kurl-addons-production-1658439274.s3.amazonaws.com/kotsadm-1.85.0-a482541.tar.gz",
    "kurlVersionCompatibilityRange": ">= v2022.10.05-0"
  }
]
```

We will make available a set of tools (GitHub actions to start) to aid external add-ons in building and testing add-on packages.

kURL automation will periodically poll each external add-on's published versions.json file and copy the new add-on package versions to its object storage bucket.
The add-on package will be stored external to any specific kURL version, as kURL versions are immutable.
When retrieving add-on versions from the kURL API, the API will append all internal versions with external ones that satisfy the `kurlVersionCompatibilityRange`.

When a kURL spec is resolved as part of the script rendering process, external add-on package versions will be rendered including the `s3Override` property with reference to the package.
kURL will use this property to identify the source and download the add-on package when installing the add-on in the end user's environment.

```yaml
spec:
  kotsadm:
    version: 1.85.0
    s3Override: https://s3.kurl.sh/external/kotsadm-1.85.0-a482541.tar.gz
```

## Status

Proposed

## Consequences

Once an version is published to an external versions.json file, kURL will copy that add-on package version to its object storage bucket.
That version is immutable and will never be overwritten.

Add-ons share common functions from the kURL source code as well as export environment variables that are shared by the kURL core as well as other add-ons.
The kURL project must commit to supporting these functions and variables to maintain backwards compatibility for all existing external add-on versions.

The KOTS add-on will now be maintained and released from the github.com/replicatedhq/kots project, independent of the kURL project.
It is the responsibility of the team that maintains KOTS to maintain and release the kURL add-on.

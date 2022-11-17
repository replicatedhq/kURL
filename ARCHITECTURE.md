# kURL Architecture

## Installer Manifest

The kURL manifest is made up of top level add-ons, each with it's own properties for configuration.
kURL.sh hosts an API where users can POST kURL manifests and a deterministic hash is stored and returned.
This hashed can then be used to retrieve a kURL installation script or air-gap bundle.

```yaml
apiVersion: cluster.kurl.sh/v1beta1
kind: Installer
metadata:
  name: 5e61e80
spec:
  kubernetes:
    version: 1.23.5
  containerd:
    version: 1.4.13
  weave:
    version: 2.6.5
  longhorn:
    version: 1.2.2
  ekco:
    version: 0.19.0
  minio:
    version: 2020-01-25T02-50-51Z
  contour:
    version: 1.20.1
  registry:
    version: 2.7.1
  kotsadm:
    version: 1.69.1
```

## kURL URL

A URL can be contructed including the hash to retrieve a kURL script (curl https://k8s.kurl.sh/5e61e80) or air-gap bundle (curl -LO https://k8s.kurl.sh/bundle/5e61e80.tar.gz).
Additionally, a version of kURL can be pinned in that URL (https://k8s.kurl.sh/version/v2022.04.19-0/5e61e80).

## kURL.sh API

The kURL.sh API can be used to create installers and retrieve install scripts and air-gap bundles.

### Services

The kURL API is made up of 5 services.

#### Web

https://github.com/replicatedhq/kurl-api

The browser UI for creating and viewing kURL installers.

#### Typescript API

The API for creating kURL URLs and rendering installers.
The API accepts a kURL Installer spec and returns a URL including a deterministic hash of the spec for installing a cluster based on that spec, for example https://k8s.kurl.sh/5e61e80.
The API interacts stores these hashes in its relational database for retrieval.
Additionally, the API is responsible for resolving the add-on version ("latetst" and ".x") and rendering the spec when a script is requested, for example https://k8s.kurl.sh/5e61e80/install.sh or shorthand https://k8s.kurl.sh/5e61e80.
The API reads the current kURL version from the object storage bucket (https://kurl-sh.s3.amazonaws.com/dist/VERSION) and uses that version to lookup add-on version information (e.g. https://kurl-sh.s3.amazonaws.com/dist/v2022.04.19-0/supported-versions-gen.json) for spec resolution.

#### Go API Proxy

This API proxies most requests directly to the Typescript API.
Additionally, this API is responsible for assembling and streaming air-gap bundles back to the end-user.
Air-gap packages are assembled from individual add-on package archives (e.g. https://kurl-sh.s3.amazonaws.com/dist/v2022.04.19-0/rook-1.0.4.tar.gz) and streamed as a single archive back to the end user when requested (e.g. https://k8s.kurl.sh/bundle/5e61e80.tar.gz).

#### Relational Database

Stores installer hashes.

#### Object Store

Stores built kURL assets including add-on package archives.

### Architecture Diagram

![kURL.sh Architecture](https://user-images.githubusercontent.com/371319/166266866-267833a7-b21f-4665-b657-a55d6271b48b.png)

### Object Storage

| Object | Description |
| ------ | ----------- |
| s3://[bucket]/[(dist\|staging)]/VERSION                                    | The current kURL version, used by the API to determine what version subdirectory to serve packages from |
| s3://[bucket]/[(dist\|staging)]/[kURL version]/supported-versions-gen.json | Add-on and version information for a given release of kURL, for resolving "latest" and "dot x" versions as well as validating installers |
| s3://[bucket]/[(dist\|staging)]/[kURL version]/[entrypoint].tmpl           | Script templates rendered by the API, install.sh, join.sh, upgrade.sh and tasks.sh |
| s3://[bucket]/[(dist\|staging)]/[kURL version]/[addon-version].tar.gz      | Add-on package archives |

## kURL Installer

### Entrypoints

| Script | Description |
| ------ | ----------- |
| install.sh | Initialize and upgrade a kURL cluster. |
| join.sh    | Join additional nodes to the cluster. |
| upgrade.sh | Utility script for upgrading additional nodes. |
| tasks.sh   | For various tasks including re-generating the join script and loading images from an air-gap bundle. |

### kURL Directory Structure

Exists on the server at `/var/lib/kurl`.

| Directory | Description |
| ----------| ----------- |
| addons/    | Stores add-ons, including images and assets. |
| bin/       | Stores utility binaries. |
| krew/      | Has some plugins we use including support-bundle and preflight. |
| kustomize/ | Scripts output  |
| packages/  | Host packages |
| shared/    | Everything else |

### Flow Chart

#### Installation Lifecycle

![kURL.sh Installation Lifecycle](https://user-images.githubusercontent.com/371319/166572837-a2491c1e-b543-4d42-ac72-6362f3f2b3f6.png)

#### Join Lifecycle

![kURL.sh Join Lifecycle](https://user-images.githubusercontent.com/371319/166573513-4070e330-cc56-4881-a7be-e563dd9f9595.png)

## Add-ons

Add-ons are components that make up a kURL cluster.

### Categories

1. Kubernetes distribution - Kubeadm
1. CRI - Docker or Containerd
1. CNI - Flannel, Weave or Antrea
1. CSI - Longhorn, Rook, OpenEBS
1. Ingress - Contour
1. Misc. - Prometheus, KOTS, Velero...

### Directory Structure

| Directory | Description |
| --------- | ----------- |
| addons/[addon]/[version]/Manifest            | Manifest of assets, host packages and container images |
| addons/[addon]/[version]/install.sh          | Entrypoint to the add-on installation script |
| addons/[addon]/[version]/host-preflight.yaml | Troubleshoot.sh preflight spec |
| addons/[addon]/[version]/assets/             | Runtime assets built during CI |
| addons/[addon]/[version]/images/             | Runtime images built during CI |
| addons/[addon]/[version]/[distro-version]/   | Runtime host packages for each supported Linux OS built during CI |

### Lifecycle

Add-ons can implement a set of lifecycle hooks that are invoked when creating, joining or upgrading the cluster.
See the [flow charts](#flow-chart) for more details.

For more details about each add-on lifecycle hook, see the add-on [README.md](/addons/README.md#lifecycle-hooks)

### External Add-ons

[adr-003-external-addons.md](/docs/arch/adr-003-external-addons.md)

kURL maintains a list of externally built and hosted add-ons (current only "kotsadm").

kURL automation, more specifically the `import-external-addons` GitHub action, polls this list for newly available versions.

New versions are published to the external add-on registry and packages are copied from the source and stored in the kURL S3 bucket.

The kURL API merges the external add-on registry with its internal list of add-on versions, making them available to the end-user.

## Deployment and Releases

Upon releasing kURL, scripts and add-on package archives are built and uploaded to to the kURL object storage bucket along with metadata including the Git sha from which they were generated.
Once complete, the VERSION file is updated to point to the current version of kURL.
The API makes use of this VERSION file to resolve the scripts and add-on packages.

### Production Workflow

Production release are triggerd by running the command `make tag-and-release` or pushing a tag in the format "v*.*.*".
Production releases are uploaded to the object storage bucket at prefix `dist`, for example https://kurl-sh.s3.amazonaws.com/dist/v2022.04.19-0/.
Before building add-on packages, the workflow will first check if there were any changes made to the add-on since the previous production release based on metadata included with the add-on package.
If no changes were made, the package will be copied from the previous production release to optimize for build times.
Next, the workflow will check if there were any changes made since the previous staging release and copy from staging if no changes were made.
The is to account for a scenario where a commit were being tagged other than what is at the HEAD of main.
If changes were made to both production and staging, the package will be built from source and uploaded.
Finally, VERSION file is updated at https://kurl-sh.s3.amazonaws.com/dist/VERSION to point to the new production version.
Historical production releases are never removed from the object storage bucket.

### Staging Workflow

Staging releases are triggered on merge to main.
Staging release versions use the most current release version tag and append prerelease `-dirty`, for example v2022.04.19-0-dirty.
Due to this versioning scheme, staging releases will overwrite the previous staging release if no production release occured prior.
This is intentional to optimize for storage costs.
Staging releases are uploaded to the object storage bucket at prefix `staging`, for example https://kurl-sh.s3.amazonaws.com/staging/v2022.04.19-0-dirty/.
Before building add-on packages, the workflow will first check if there were any changes made to the add-on since the previous staging release based on metadata included with the add-on package.
If no changes were made, the package will be copied from the previous staging release to optimize for build times.
If changes were made, the package will be built from source and uploaded.
Finally, VERSION file is updated at https://kurl-sh.s3.amazonaws.com/staging/VERSION to point to the new staging version.
Historical staging releases are never removed from the object storage bucket.

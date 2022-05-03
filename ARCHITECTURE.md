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

A URL can be contructed including the hash to retrieve a kURL script (curl https://kurl.sh/5e61e80) or air-gap bundle (curl -LO https://kurl.sh/bundle/5e61e80.tar.gz).
Additionally, a version of kURL can be pinned in that URL (https://kurl.sh/version/v2022.04.19/5e61e80).

## kURL.sh API

The kURL.sh API can be used to create installers and retrieve install scripts and air-gap bundles.

### Services

The kURL API is made up of 5 services.

#### Web

The browser UI for creating and viewing kURL installers.

#### Go API Proxy

This API proxies most requests directly to the Typescript API.
Additionally, this API is interacts with the object store and is responsible for assembling and streaming air-gap bundles back to the end-user.

#### Typescript API

The API for creating and consuming installers. Interacts with the relational database.

#### Relational Database

Stores installer hashes.

#### Object Store

Stores built kURL assets including add-on bundles.

### Architecture Diagram

![kURL sh Architecture](https://user-images.githubusercontent.com/371319/166266866-267833a7-b21f-4665-b657-a55d6271b48b.png)

### Object Storage

| Object | Description |
| ------ | ----------- |
| s3://[bucket]/[kURL version]/[entrypoint].tmpl           | Script templates rendered by the API. install.sh, join.sh, upgrade.sh and tasks.sh |
| s3://[bucket]/[kURL version]/[addon-version].tar.gz      | Add-on bundles |
| s3://[bucket]/[kURL version]/supported-versions-gen.json | Add-on and version information for a given release of kURL. For resolving "latest" and "dot x" versions as well as validating installers. |

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
| addons/    | Stores addons, including images and assets. |
| bin/       | Stores utility binaries. |
| krew/      | Has some plugins we use including support-bundle and preflight. |
| kurlkinds/ | Contains cluster.kurl.sh CRD |
| kustomize/ | Scripts output  |
| packages/  | Host packages |
| shared/    | Everything else |

### Flow Chart

#### Installation Lifecycle

![kURL.sh Installation Lifecycle](https://user-images.githubusercontent.com/371319/166572837-a2491c1e-b543-4d42-ac72-6362f3f2b3f6.png)

#### Join Lifecycle

![kURL.sh Join Lifecycle](https://user-images.githubusercontent.com/371319/166572499-17604a58-f694-4cb3-bfa7-5ec605648108.png)

## Add-ons

Add-ons are components that make up a kURL cluster.

### Categories

1. Kubernetes distribution - Kubeadm, RKE2, K3s
1. CRI - Docker or Containerd
1. CNI - Weave or Antrea
1. CSI - Longhorn, Rook, OpenEBS
1. Ingress - Contour
1. Misc. - Prometheus, KOTS, Velero...

### Directory Structure

| Directory | Description |
| --------- | ----------- |
| addons/[addon]/[version]/Manifest            | Manifest of assets, host packages and container images |
| addons/[addon]/[version]/install.sh          | Entrypoint to the add-on installation script |
| addons/[addon]/[version]/host-preflight.yaml | Troubleshoot.sh preflight spec |
| addons/[addon]/[version]/assets/             | Runtime assets |
| addons/[addon]/[version]/images/             | Runtime images |
| addons/[addon]/[version]/[distro-version]/   | Runtime host packages for each supported Linux OS  |

### Lifecycle

#### addon_fetch

Fetch the add-on package from the object store or from the air-gap bundle and extract into `/var/lib/kurl/addons`.
This step is typically skipped if the add-on version has not changed since the previous run.

#### addon_load

Load (bash source) the install.sh script.

#### addon_preflights

Run the Troubleshoot.sh preflight spec from host-preflight.yaml.

#### addon_pre_init

Operations that are performed in the pre-init script include installing host packages or Kustomizing the Kubernetes distribution.

#### addon_install

Kubectl apply this add-on to the cluster.
This step is typically skipped if the add-on version and configuration has not changed since the previous run.

#### addon_already_applied

This step run instead of addon_install if the add-on version and configuration has already been applied.
#### addon_join

Operations that are performed in the join script include installing host packages or Kustomizing the Kubernetes distribution.

#### addon_outro

Print end-user messages to the screen.

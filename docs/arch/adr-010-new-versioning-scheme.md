# ADR 10: New kURL Versioning Scheme

## Context

Based on our prior experience, offering customers the ability to select various add-on versions provides them with significant flexibility, but it also creates numerous challenges. Presently, we're struggling to ensure that each customer's chosen add-ons are compatible with one another and that migration paths are available for all potential combinations. Moreover our user feedback indicates that stability and predictability are their top priorities, rather than the specific technologies they are running behind the scenes.

## Decision

Based on users feedback and the challenges we are facing to maintain kURL upgrades predictable, we have decided to adopt a more opinionated approach to delivering our Kubernetes distribution. This will involve implementing a well-designed versioning scheme, which is outlined in detail in this Architecture Decision Record.

## Solution

The solution involves three different entities named _Channels_, _Installers_ and _Bundles_, each one of them are described below.

### Choosing the Channel

Our revised versioning scheme entails organising our offering into Channels that align with specific Kubernetes minor versions. As a result, users will be required to select the Channel to which they want their installer assigned.

While we recognize the importance of providing our users with access to a wide range of Kubernetes minor versions, we have chosen to focus our efforts on the most recent releases. To this end, we will be offering one Channel for each of the currently supported [Kubernetes releases](https://kubernetes.io/releases/). These releases are maintained by the Kubernetes project and include the most recent three minor versions.

By focusing on the most recent releases, we can ensure that our users have access to the latest features and functionalities of Kubernetes, while also minimizing the risk of compatibility issues and other technical challenges. We believe that this approach strikes the right balance between flexibility and stability, and will provide our users with a high-quality and dependable product.

At the time of writing, the Channels that we will be offering to our users include:

| Channel  | Kubernetes version installed by this Channel    |
|----------|-------------------------------------------------|
| v1.24    | Most up-to-date Kubernetes version for v1.24.x. |
| v1.25    | Most up-to-date Kubernetes version for v1.25.x. |
| v1.26    | Most up-to-date Kubernetes version for v1.26.x. |
| v1.27    | Most up-to-date Kubernetes version for v1.27.x. |

By drafting an installation file similar to the model given below, users can link their setup with a particular kURL Channel (_therefore they will be adhering to Kubernetes versions 1.27_)
```yaml
apiVersion: "cluster.kurl.sh/v1beta2"
kind: "Installer"
metadata:
  name: "cluster"
spec:
  channel:  "1.27"
```
_We have decided to transition to the newer **v1beta2** variant. Existing users who prefer to continue working with the outdated format may still do so at their own discretion_

#### Pinning the kURL version

Another feature we aim to offer is the ability for users to fix (pin) their installation to a particular kURL installer version. The organisation of kURL installer releases follows the pattern `YYYY.MM.DD-x`. A complete list of kURL versions can be seen [here](https://github.com/replicatedhq/kURL/releases).

For those seeking to pin their setup to a designated kURL installer version, the `installerVersion` field must be appropriately configured as shown in the example below.

```yaml
apiVersion: "cluster.kurl.sh/v1beta2"
kind: "Installer"
metadata:
  name: "cluster"
spec:
  channel:  "1.27"
  installerVersion: "v2023.04.24-0"
```

While it's certainly possible to omit the `installerVersion` configuration, doing so means relying upon the current most up-to-dated kURL installer version.

### Add-on versions

In order to maintain greater control over the installation process, we have decided to modify our approach to add-on selection. Going forward, we will no longer allow users to freely select any add-on on any version of their choosing. Instead, we will provide users with specific bundles of add-ons (from here on this ADR will call them _Bundles_), each of which will be available in different versions within a designated Channel.

This is an example of a Bundle on its v1.0.0 version:

| Add-on     | Version              |
|------------|----------------------|
| Containerd | 1.6.20               |
| Flannel    | 0.21.5               |
| OpenEBS    | 3.5.0.               |
| Minio      | 2023-03-13T19-46-17Z |


To facilitate the selection of a Bundle within a Channel, we will implement a new feature that enables users to pin a specific version of a Bundle. This means that users can select and install the precise version of a Bundle that best aligns with their needs, providing them with reproducibility.

To illustrate the concept of Bundle version within a Channel, we have provided an example of one that could be available within the Channel v1.24. Let's call this _Bundle v1.0.0_:

| Add-on     | Version              |
|------------|----------------------|
| Containerd | 1.6.16               |
| Flannel    | 0.21.4               |
| OpenEBS    | 3.3.0.               |
| Minio      | 2023-03-13T19-46-17Z |

For users who wish to pin their Bundle version within a Channel, we will implemented a straightforward solution. By providing the `bundleVersion` parameter as follows, users can easily specify the exact version of the add-on Bundle that they wish to install:

```yaml
apiVersion: "cluster.kurl.sh/v1beta2"
kind: "Installer"
metadata:
  name: "cluster"
spec:
  channel:  "1.24"
  bundleVersion: "1.0.0"
```

_If no `bundleVersion` parameter is passed, the default behaviour is to install or update to the most up-to-dated version of the Channel's Bundle_

For this example let's say we have just released a new version of our Channel 1.24 Bundle, which is now available at version 1.1.0. This release includes several updates and bug fixes on the add-on offered. This is how the Bundle 1.1.0 may look like:

| Add-on     | Version              |
|------------|----------------------|
| Containerd | 1.6.20               |
| Flannel    | 0.21.4               |
| OpenEBS    | 3.4.0                |
| Minio      | 2023-03-13T19-46-17Z |

_Versions for Containerd and OpenEBS were updated._ 

If the Bundle version was pinned then the Installer will need to be updated in order for this to be installed in the cluster:

```yaml
apiVersion: "cluster.kurl.sh/v1beta2"
kind: "Installer"
metadata:
  name: "cluster"
spec:
  channel:  "1.24"
  bundleVersion: "1.1.0"
```

To ensure that the add-on Bundle is always up-to-date users could use the example installer below, which is specifically tailored to meet this need:

```yaml
apiVersion: "cluster.kurl.sh/v1beta2"
kind: "Installer"
metadata:
  name: "cluster"
spec:
  channel:  "1.24"
```
_i.e. if no `bundleVersion` is present then the most up-to-dated one is installed_

### Additional Details

We will develop an approach that does not require any modifications to the kURL installer otherwise pinning old installer versions will result in a failure. Instead, we will implement a new feature in the kURL-API that allows us to seamlessly translate the new Installer (_Channel_, _Installer Version_ and _Bundle Version_) into the old Installer on-the-fly, and then inject it into the installer script.

For example, let's supposed that this is the most up-to-dated Bundle in the Channel 1.24:

| Add-on     | Version              |
|------------|----------------------|
| Containerd | 1.6.20               |
| Flannel    | 0.21.4               |
| OpenEBS    | 3.4.0                |
| Minio      | 2023-03-13T19-46-17Z |

Upon attempting to translate the following _new Installer_ and taking into account the Bundle above:

```yaml
apiVersion: "cluster.kurl.sh/v1beta2"
kind: "Installer"
metadata:
  name: "cluster"
spec:
  channel:  "1.24"
  installerVersion: "v2023.04.24-0"
```

The API will render the following _old Installer_ inside the script:

```yaml
apiVersion: "cluster.kurl.sh/v1beta1"
kind: "Installer"
metadata: 
  name: "installer"
spec:
  kubernetes: 
    version: "1.24.12"
  flannel: 
    version: "0.21.4"
  containerd: 
    version: "1.6.20"
  minio: 
    version: "2023-03-13T19-46-17Z"
  openebs: 
    version: "3.4.0"
  kurl:
    installerVersion: "v2023.04.24-0"
```

## Status

Proposed

## Questions to be answered in future interactions on this ADR

- How one disables or enables specific add-ons inside the Bundle ?
- How one can provide custom config to specific add-ons inside the Bundle ?
- How are we going to manage OpenEBS vs Rook when both are of the Bundle ?
	- We might need to finish the "auto-migration" work before.

## Consequences

- This new type needs to be stored by the kURL-API and translated into the original Installer (_v1beta1_) on the fly.
- We gonna need to keep track of what add-ons belong to what Bundle version in what Channel.
- There might be some heavy lifting in the vendor side to support new promoted installers using this method.

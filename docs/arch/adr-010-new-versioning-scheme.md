# ADR 10: New kURL Versioning Scheme

## Context

Based on our prior experience, offering customers the ability to select various add-on versions provides them with significant flexibility, but it also creates numerous challenges. Presently, we're struggling to ensure that each customer's chosen add-ons are compatible with one another and that migration paths are available for all potential combinations. Moreover our user feedback indicates that stability and predictability are their top priorities, rather than the specific technologies running behind the scenes.

## Decision

Based on users feedback and the challenges we are facing to maintain kURL upgrades predictable, we have decided to adopt a more opinionated approach to delivering our Kubernetes distribution. This will involve implementing a well-designed versioning scheme, which is outlined in detail in this Architecture Decision Record.

## Solution

The solution involves two different entities named _Channels_ and _Installer Versions_, each one of them are described below.

### Choosing the Channel

Our revised versioning scheme entails organising our offering into _Channels_. As a result, users will be required to select the _Channel_ to which they want their cluster installation assigned. Each _Channel_ refers to one and only one Kubernetes minor version.

While we recognise the importance of providing our users with access to a wide range of Kubernetes minor versions, we have chosen to focus our efforts on the most recent releases. To this end, we will be offering one _Channel_ for each of the currently supported [Kubernetes releases](https://kubernetes.io/releases/). These releases are maintained by the Kubernetes project and include the most recent three minor versions.

By focusing on the most recent releases, we can ensure that our users have access to the latest features and functionalities of Kubernetes, while also minimizing the risk of compatibility issues and other technical challenges. We believe that this approach strikes the right balance between flexibility and stability, and will provide our users with a high-quality and dependable product.

At the time of writing, the _Channels_ we will be offering to our users are:

| Channel                   | Kubernetes version installed                    |
|---------------------------|-------------------------------------------------|
| v1.24                     | Most up-to-date Kubernetes version for v1.24.x. |
| v1.25                     | Most up-to-date Kubernetes version for v1.25.x. |
| v1.26                     | Most up-to-date Kubernetes version for v1.26.x. |
| v1.27                     | Most up-to-date Kubernetes version for v1.27.x. |

By drafting an installation file similar to the model given below, users can link their cluster installation with a particular _Channel_ (_by doing so they will be adhering to Kubernetes versions 1.27_)

```yaml
apiVersion: "cluster.kurl.sh/v2beta1"
kind: "Installer"
metadata:
  name: "cluster"
spec:
  channel:  "1.27"
```

_We have decided to transition to the newer **v2beta1** variant for this CRD. Existing users who prefer to continue working with the outdated format may still do so at their own discretion_

#### Choosing the Installer Version

Another feature we aim to offer is the ability for users to fix (pin) their installation to a particular kURL _Installer Version_. The organisation of kURL installer releases follows the pattern `YYYY.MM.DD-x`. A complete list of kURL versions can be seen [here](https://github.com/replicatedhq/kURL/releases).

For those seeking to pin their setup to a designated kURL _Installer Version_, the `installerVersion` field must be appropriately configured as shown in the example below.

```yaml
apiVersion: "cluster.kurl.sh/v2beta1"
kind: "Installer"
metadata:
  name: "cluster"
spec:
  channel:  "1.27"
  installerVersion: "v2023.04.24-0"
```

#### Add-ons and their respective Installer Versions

In order to maintain greater control over the installation process, we have also decided to modify our approach to add-on selection. Going forward, we will no longer allow users to freely select any add-on on any version of their choosing. Instead, we will provide users with specific groups of add-ons.

Add-on groups are directly related to _Installer Versions_ e _Channels_, meaning that each _Installer Version_ in a given _Channel_ will include its own specific group of add-ons. This is a hypothetical example of an add-ons group for `installerVersion` version  `v2023.04.24-0` , _Channel_ `v1.24`:

| Add-on     | Version              |
|------------|----------------------|
| Containerd | 1.6.19               |
| Flannel    | 0.21.3               |
| OpenEBS    | 3.4.0                |
| Minio      | 2023-03-13T19-46-17Z |

As we release new _Installer Versions_, the add-ons included in each one of them may be updated to reflect the latest features and functionalities. This, for example, could be the add-ons grouped under `installerVersion` version `v2023.04.25-0`  on _Channel_ `v1.24` (_versions for Containerd and Flannel were updated._):

| Add-on     | Version              |
|------------|----------------------|
| Containerd | 1.6.20               |
| Flannel    | 0.21.4               |
| OpenEBS    | 3.4.0                |
| Minio      | 2023-03-13T19-46-17Z |

_If no `installerVersion` parameter is specified in the Installer, the default behaviour is to install or update using the most up-to-dated Installer Version available on the chosen Channel._

In summary, users can select which add-ons and their respective versions they want by pinning a specific `installerVersion` and a specific _Channel_ in the Installer YAML.

### Additional Details

We will develop an approach that does not require any modifications to the kURL installer otherwise pinning old installer versions will result in a failure. Instead, we will implement a new feature in the kURL-API that allows us to seamlessly translate the new Installer (_Channel_ and _Installer Version_) into the old Installer object on-the-fly, and then inject the result into the installer script.

For example, let's supposed that this is the most up-to-date add-on group for `installerVersion` version `v2023.04.24-0` in the _Channel_ 1.24:

| Add-on     | Version              |
|------------|----------------------|
| Containerd | 1.6.20               |
| Flannel    | 0.21.4               |
| OpenEBS    | 3.4.0                |
| Minio      | 2023-03-13T19-46-17Z |

Upon attempting to translate the following _new Installer_ and taking into account the add-ons group above:

```yaml
apiVersion: "cluster.kurl.sh/v2beta1"
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

### Upgrades

By limiting our support to only the Kubernetes minor versions that are currently supported by the upstream Kubernetes project, there may be some unintended consequences. For example, users who are running older versions of Kubernetes (prior to `1.24`) would have their installations considered out-of-support. This could lead to frustration and a negative experience for some of our users.

Selecting the right add-on groups will be a critical step in this process. It is important that we carefully choose which add-ons to include in each _Installer Version_ in each _Channel_, and we should leverage the most up-to-date versions of each add-on whenever possible. By doing so, users will be able to upgrade their clusters directly to any _Channel_ they desire, without worrying about compatibility issues with their add-ons.


### Upgrade paths

Users are allowed to upgrade from any _Channel + Installer Version_ to any other _Channel + Installer Version_ without restrictions, downgrades are not supported. We plan to upgrade through as many versions as necessary so an upgrade from the _Installer Version_ `v2021.09.01-0` on _Channel_ `1.24` to the _Installer Version_ `v2023.05.01-0` on _Channel_ `1.27` may end up looking like the following diagram:

```
       1.24                     1.25                    1.26                    1.27
 ┌────────────────┐       ┌────────────────┐      ┌────────────────┐      ┌────────────────┐
 │ v2021.09.01-0  ├───┐   │ v2021.09.01-0  │      │                │      │                │
 │ v2022.10.01-0  │   │   │ v2022.10.01-0  │      │                │      │                │
 │                │   │   │ v2022.11.01-0  │      │                │      │                │
 │                │   │   │ v2022.12.01-0  │      │ v2022.12.01-0  │      │                │
 │                │   └───► v2023.01.01-0  ├──┐   │ v2023.01.01-0  │      │                │
 │                │       │                │  │   │ v2023.02.01-0  │      │                │
 │                │       │                │  │   │ v2023.03.01-0  │      │                │
 │                │       │                │  │   │ v2023.04.01-0  │      │                │
 │                │       │                │  └───► v2023.05.01-0  ├──────► v2023.05.01-0  │
 └────────────────┘       └────────────────┘      └────────────────┘      └────────────────┘
```

Whenever an `installerVersion` is not set the latest version on the selected _Channel_ is used. As mentioned above any upgrade is possible when the user pins the `Installer Version`. For example an upgrade from _Installer Version_ `v2021.09.01-0` on _Channel_ `1.24` to _Installer Version_ `v2023.01.01-0` on _Channel_ `1.26` would look like the following graphs.

```
       1.24                     1.25                    1.26                    1.27
 ┌────────────────┐       ┌────────────────┐      ┌────────────────┐      ┌────────────────┐
 │ v2021.09.01-0  ├───┐   │ v2021.09.01-0  │      │                │      │                │
 │ v2022.10.01-0  │   │   │ v2022.10.01-0  │      │                │      │                │
 │                │   │   │ v2022.11.01-0  │      │                │      │                │
 │                │   │   │ v2022.12.01-0  │      │ v2022.12.01-0  │      │                │
 │                │   └───► v2023.01.01-0  ├──────► v2023.01.01-0  │      │                │
 │                │       │                │      │ v2023.02.01-0  │      │                │
 │                │       │                │      │ v2023.03.01-0  │      │                │
 │                │       │                │      │ v2023.04.01-0  │      │                │
 │                │       │                │      │ v2023.05.01-0  │      │ v2023.05.01-0  │
 └────────────────┘       └────────────────┘      └────────────────┘      └────────────────┘
```

Upgrade attemps like the following two examples below are not allowed as they are considered a downgrade. Users can't upgrade to an older _Channel_ **or** to an older _Installer Version_.

```
       1.24                     1.25                    1.26                    1.27
 ┌────────────────┐       ┌────────────────┐      ┌────────────────┐      ┌────────────────┐
 │ v2021.09.01-0  ├───┐   │ v2021.09.01-0  │      │                │      │                │
 │ v2022.10.01-0  │   │   │ v2022.10.01-0  │      │                │      │                │
 │                │   │   │ v2022.11.01-0  │      │                │      │                │
 │                │   │   │ v2022.12.01-0  │   ┌──► v2022.12.01-0  │      │                │
 │                │   └───► v2023.01.01-0  ├───┘  │ v2023.01.01-0  │      │                │
 │                │       │                │      │ v2023.02.01-0  │      │                │
 │                │       │                │      │ v2023.03.01-0  │      │                │
 │                │       │                │      │ v2023.04.01-0  │      │                │
 │                │       │                │      │ v2023.05.01-0  │      │ v2023.05.01-0  │
 └────────────────┘       └────────────────┘      └────────────────┘      └────────────────┘
```
_Users are not allowed to upgrade to a newer Channel but using an older Installer Version._

```
       1.24                     1.25                    1.26                    1.27
 ┌────────────────┐       ┌────────────────┐      ┌────────────────┐      ┌────────────────┐
 │ v2021.09.01-0  ├───┐   │ v2021.09.01-0  │      │                │      │                │
 │ v2022.10.01-0  │   └───► v2022.10.01-0 ┐│      │                │      │                │
 │ v2022.11.01-0  │       │ v2022.11.01-0 ▼│      │                │      │                │
 │ v2022.12.01-0  │   ┌───│ v2022.12.01-0  │      │ v2022.12.01-0  │      │                │
 │ v2023.01.01-0 ◄────┘   │ v2023.01.01-0  │      │ v2023.01.01-0  │      │                │
 │                │       │                │      │ v2023.02.01-0  │      │                │
 │                │       │                │      │ v2023.03.01-0  │      │                │
 │                │       │                │      │ v2023.04.01-0  │      │                │
 │                │       │                │      │ v2023.05.01-0  │      │ v2023.05.01-0  │
 └────────────────┘       └────────────────┘      └────────────────┘      └────────────────┘
```
_Users can't upgrade to a newer Installer Version using an older Channel_

## Questions and Answers

**If I do not pin my Installer Version and my Channel falls out of support what is the user experience? Do we use a previous installer version or exit the script with an error?**
Decision: use the most up to date _Installer Version_ that supports the EOL _Channel_.

**How do users know what exactly Kubernetes patch is being installed in an specific Channel?**
Decision: We already have an API that tells you “you will get this set of addons from this spec at this installer version” and we will specify everything through the release notes.

## Status

Accepted

## Questions to be answered in future interactions on this ADR

- How one disables or enables specific add-ons ?
- How one can provide custom config to specific add-ons ?
- How are we going to manage OpenEBS vs Rook when both are provided on the same `installerVersion` ?
        - We might need to finish the "auto-migration" work before.

## Consequences

- This new type needs to be stored by the kURL-API and translated into the original Installer (_v1beta1_) on the fly.
- We gonna need to keep track of what add-ons belong to what _Installer Version_.
- There might be some heavy lifting in the Vendor Portal side to support new promoted installers using this method.
- Not all _Installer Versions_ are going to be compatible with all _Channels_, we gonna have to keep track of what _Installer Version_ can be used together with what _Channel_ and block upgrades based on that.

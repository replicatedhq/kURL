# ADR 011: kURL Add-on Operator

## Context

kURL today is a set of bash scripts that configure and install a Kubernetes cluster in addition to a set of add-on components. The components are installed in sequence by applying highly customized Kubernetes YAML resources. The current architecture makes kURL hard to develop, maintain, and support.

As an amalgam of bash scripts, the code base suffers from low cohesion and high complexity which results in the code being difficult to read and reason, and difficult to test. The installation is applied sequentially and each component is highly dependent on each other with no scopes to limit access and enforce separation. The project is architecturally a monolith without any functional separation of components and concerns.

The installation of all components is done procedurally in the script. When there is a failure, it is difficult to understand what components have failed and how that affects the installation process as a whole.

The components are installed in a proprietary fashion by applying highly customized Kubernetes YAML resources. They are hard to customize as the spec is proprietary and hard to extend because each customization must be passed through configuration to the end-user. Changes to this spec must be documented and are less discoverable. This method is not supported by the upstream which makes it difficult to pin addon installation issues on the upstream project and difficult to request support from the upstream.


## Decision

We will develop a Kubernetes [Operator](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/) in _Go_ that will install, configure and manage add-on applications in the cluster. The operator will extend the Kubernetes API through Custom Resource Definitions (CRD) and will allow users to declaritively manage add-ons with a Custom Resource (CR). 

## Solution

The operator will be implemented with the following objectives in mind:

- It will be scaffolded using [kubebuilder](https://book.kubebuilder.io/introduction.html).
- It will be developed using [SOLID](https://en.wikipedia.org/wiki/SOLID) principles and operator best practices.
- It will distribution agnostic. I.e. it will not be tightly coupled to the kURL Kubernetes distribution.
- It will manage application add-ons _only_ and _exclude_ managing CRI and CNI resources.
- It will install and confiure the KOTS admin console.
- It can be installed on an existing [kURL](https://kurl.sh/) cluster with only Kubernetes, containerd and flannel.
- The installation mechanism for add-ons will be through the use of Helm Charts.
- By default the add-on configuration will be opinionated by us but we will enable the end-user to override the configuration for maximum flexibility. Vendors and users will be able to override the configuration using a standard [Helm values](https://helm.sh/docs/chart_template_guide/values_files/) file.
- It will rely as much as possible on Helm for managing the lifecyle of the add-ons.

### The `Installer` API

The `Installer` API defines a resource for installing specific add-ons.

```yaml
apiVersion: cluster.kurl.sh/v2beta1
kind: Installer
metadata:
  name: installer-sample
spec:
  channel: "1.27"
  minio:
    enabled: true
    configOverride:
        persistence:
            enabled: true
        replicas: 1
        mode: standalone

```

### The Controllers

The operator will have at minimum one controller which ensures the `Installer` CR is reconciled with the cluster periodically. The `Installer` controller (main controller) will delegate responsiblity for managing add-ons to other controllers. The reconcilation for the main controller will consist of determining the add-ons to be managed from the `Installer` CR and creating a controller for each add-on (addon-on controller).

The add-on controller will be responsible for
- verifying the requirements for the add-on are met
- managing the add-on itself
- ensure add-on is in desired state
- update the add-on CR status

### Managing the Add-ons

How the add-ons will be managed is still an open question. We have a couple of options:

_Use the Helm Controller provided by Flux_

The [Flux Helm Controller](https://fluxcd.io/flux/components/helm/helmreleases/) affords us the following benefits:
- Stable [HelmRelease API](https://fluxcd.io/flux/components/helm/api/)
- Helm release [dependencies](https://fluxcd.io/flux/components/helm/helmreleases/#helmrelease-dependencies)
- Support for Helm install, upgrade, test, rollback and uninstall
- Performs Helm uninstall on `HelmRelease` CR removal
- Chart values override\
- Pull charts from Helm repository directly

_Develop our own Homebrew Helm Controller_

This approach affords us with a controller that meets our specific needs and avoids any third party software dependency. 




## Status

Proposed

## Open Questions

- How to allow full configuration of add-ons for advanced vendors/users?
- Do we use an existing feature rich Helm controller like the one provided by [Flux](https://fluxcd.io/flux/components/helm/) or build our own?
- How to structure the add-on to adhere to SOLID principles?

## Consequences

- A kURL CLI will be needed to install the operator dependencies (if any)
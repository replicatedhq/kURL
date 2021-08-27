# Helm Addons

To be an addon in a Kurl cluster, they must be contributed into the repo and maintained across new breaking changes and new versions.
This proposal will give users the flexibility to specify their own addons through a helm chart support in the Kurl installer spec.


## Goals
- Allow any Helm chart to be specified as part of a Kurl spec.

## Non Goals

- Verify authenticity, trustworthyness and "goodness" of helm addons.
- Validate Helm values.

## Background

Users of Kurl have a limited set of available cluster addons and often want to include ones that are unsupported.
There is friction in the [kurl development process](https://github.com/replicatedhq/kURL/blob/master/test/dev.md), [contributing new addons](https://kurl.sh/docs/add-on-author/) and addon maintanence. 

Helm is a popular tool for managing deployment configuration that allows application/addon developers or the community to maintain a consistent interface for deployment through a chart.
By allowing Kurl users to specifify a chart and its values, we can allow customization of kutl with new addons while delegating addons support and maintance to its community.

## High-Level Design

Kurl will bundle the Helm and [Helmfile](https://github.com/roboll/helmfile) binary into the common tools bundle already delivering krew and kubectl plugins. The install.sh script will perform the following in the online case:
1. Unarchive `helm` + `helmfile` and move them into the `$PATH` and `/usr/bin`
1. Create a temporary helmfile on disk
1. Run `helmfile sync` to sync the contents 
1. Delete the temporary helmfile (but store a lockfile as a record of the install)

For airgapped the chart and artifacts need to be packaged into a bundle. The builder should perform the following:
1. Call `helmfile template` or `helmfile build` to render the charts with the provided values
1. Generate an adhoc `manifest` file by parsing `image` specs from the rendered yaml
1. Save the rendered yaml as parsed helmfile or rendered yaml (as opposed to parsing the helmfile for charts and `helm pull`ing them)
1. Generate a unique bundle with hash including the yaml + images

In the airgapped case, install.sh will perform the following:
1. Unpack the helm bundle on initialization
1. Load docker containers as part of the helm initialization
1. Apply the rendered yaml in bulk (assumption this is technically easier than saving the chart and there would be no utility in modify a helmfile in airgap use)

## Detailed Design

The yaml design is informed by the [Flux Helm Operator CRD](https://github.com/fluxcd/helm-operator/blob/master/docs/references/helmrelease-custom-resource.md). 
Another spec is [Rancher's Helm CRD](/var/lib/rancher/rke2/server/manifests/) that works with k3s and RKE2.

The proposal is to implement option1 in the updated Kurl Installer Spec:
```yaml
apiVersion: "cluster.kurl.sh/v1beta1"
kind: "Installer"
metadata: 
  name: "latest"
spec: 
  kubernetes: 
    version: "latest"
  weave: 
    version: "latest"
  containerd: 
    version: "latest"
  helm:                 
    helmVersion: "latest"       # Optional Future Capability
    helmfileVersion: "latest"   # Optional Future Capability
    helmfileSpec: |
      repositories:
      - name: hashicorp
        url: https://helm.releases.hashicorp.com
      releases:
      - name: vault                            
        namespace: vault                       
        createNamespace: true                  
        labels:                                
          foo: bar
        chart:  hashicorp/vault     
        version: ~1.24.1
        values:
          - address: https://vault.example.com                      
    # Values files used for rendering the chart
    additionalImages:   # Optional: Needed for operators
       - additleominov/redis_sentinel_exporter:1.3.0
       - oliver006/redis_exporter:v1.3.5-alpine
       - redis:5.0-alpine
  #  Alternatives Considered
  helmReleases:
    # Basic Idea, Option 1
    - release: nginx-ingress
      namespace: kube-system    # Optional
      chart: 
        name: bitnami/nginx
        repo: https://charts.bitnami.com/bitnami 
        version: 8.5.1          # Optional - uses latest if not provided
      values: |                 # Optional
        ingress:
          enabled: true
          hostname: dan-dot-com
        metrics: 
          enabled: true
    # An operator with a indirect-dependency image
    - release: redis-operator
      chart:
        name: charts/redisoperator
        repo: https://github.com/spotahome/redis-operator
      values: |
        example: hello
      additionalImages:
       - additleominov/redis_sentinel_exporter:1.3.0
       - oliver006/redis_exporter:v1.3.5-alpine
       - redis:5.0-alpine
    # Option 2 (Using Mapstructure?)
    - release: postgres-web
      chart: 
        name: bitnami/postgresql
        repo: https://charts.bitnami.com/bitnami 
      values:
        postgresqlUsername: dan
        postgresqlPassword: opensesame
    # Option 3 (Values Url)
    - release: postgres-auth
      chart: 
        name: bitnami/postgresql
        repo: https://charts.bitnami.com/bitnami 
      valuesUrl: https://gist.githubusercontent.com/DanStough/b4376b7a6aa5b73c6a647bff504212df/raw/829680f4a474720dc36b7a963d2d691305b8cdfb/postgres-auth.yaml
  ...
```

### Assumptions
1. Authenticated Registries are NOT supported by Kurl
1. Kurl Upgrade functionality of Kurl is transparent to Helm installs.
1. Certain functionality in Helmfile don't make sense in Kurl, and we'll need to figure out how to manage expectation to consumers as we go (e.g. path to helm binary should be a constant) 

### Design Decisions
1. Re-install a chart: chart installs are not idempotent, so this will be treated as an upgrade with a new revision.
1. State between executions - the only place we want to keep to keep state outside of the cluster is in the installer as the desired config.
1. Waiting - the (initial) default behavior of kurl will be to wait for resources to create. This will ensure that the cluster is in a known state before the user continues with the next set of installation (kotadm)
1. RKE2 support: has built in helm chart support by putting the Rancher Helm CR in the directory `/var/lib/rancher/rke2/server/manifests/`, but we will initially manage helm support through the helmfile CLI to have one code path for all distros.
 
### Limitations
1. Users can not manage helm installs through the helmfile directly - changes should go through the installer. 

### Tasks

#### Required
1. Update CRD for Helm + Helmfile
1. Add Helm + Helmfile binary bundle to common.tar.gz
1. Add helm.sh to install.sh
1. Add Helm tests to TestGrid Dailys
    1. Nginx?
    1. Postgres?
1. Make sure Helm is deleted with tasks.reset

#### Followup
1. Add airgap support to airgap builder for helm
  1. Join loads images on to new nodes.
1. Update Kurl.sh with new component(s) to display helm and helmfile fields and possibly lint yaml (Out of scope for this story)

## Testing

Development testing will consist of installing and re-installing several helm charts . 
Also airgap testing will be conducted on a couple of OSes (Ubuntu and Centos).

Ongoing maintance of the helm addons feature will be tested with daily TestGrid runs of several helm addons (TBD).

## Alternatives Considered

1. Creating a custom HelmRelease syntax for Kurl (see Detailed Design Section).
  1. Helmfile is a common syntax and includes a lot of advanced functionality (like generating a lockfile)
  1. A kurl-specific design would be simpler and easier to create a facade over helmfile to manage compatibility expectations.
1. Create a custom binary to manage Helm releases in kurl.
    1. Any custom binary seems like it would be a thin wrapper on the helm API. Using the helm binary directly seems like the path of least resistance for initial development.
    1. Discussion have begun to replace Kurl scripts with a CLI. Any work here would likely need to be refactored soon after.  
1. Use another industry standard to manage bundling helm charts.
    1. [Porter](https://porter.sh/mixins/helm/) has a helm mixin that could help build bundles, but supporting bundles for arbitrary charts/values seems unrealistic in terms of overhead.


## Security Considerations

1. Any anonymous user could create a TestGrid run with a malicious helm chart, but authentication is now required to add TestGrid runs since PR #1096
1. Users could create malicious Helm configurations and share the Kurl URL with others. The primary onus would be on the consumer to validate the script configuration in advance. The only solution would be to provide a allow-list of acceptable helm charts/repos, which seems counter to the goal of flexibility.


(Thanks to vmware-tanzu/velero for this design template)
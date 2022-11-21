# Add-ons

## Structure

Each available add-on has a directory with subdirectories (<addon>/<version>) for each available version of the add-on.
Each add-on is require to define at a minimum two files, `install.sh` and `Manifest`.

The Manifest file specifies a list of assets required by the add-on.
These will be downloaded during CI and saved to the add-on [directory](/ARCHITECTURE.md#directory-structure).

The install.sh script can implement a set of [Lifecycle Hooks](#lifecycle-hooks).

Any [other files](/ARCHITECTURE.md#directory-structure) in the <addon>/<version> subdirectory will be included in the package built for the add-on.
The package will be built and uploaded to s3://[bucket]/[(dist\|staging)]/[kURL version]/<addon>-<version>.tar.gz during CI.

## Runtime

During installation, upgrades and joining additional nodes, the installer will invoke a set of add-on lifecycle hooks.
See the [flow charts](/ARCHITECTURE.md#flow-chart) in ARCHITECTURE.md for more details.

### Lifecycle Hooks

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
This hook is unique in that implementation of this hook requires a function with the add-on name itself, for example [function weave()](https://github.com/replicatedhq/kURL/blob/5ce2372da583844137efee28f55498393ea32e8d/addons/weave/template/base/install.sh#L6).

#### addon_already_applied

This step run instead of addon_install if the add-on version and configuration has already been applied.

#### addon_join

Operations that are performed in the join script include installing host packages or Kustomizing the Kubernetes distribution.

#### addon_post_init

Operations that are performed in the post-init script include but not limited to configuring other add-on resources.

#### addon_outro

Print end-user messages to the screen.

## Developing Add-ons

### Requirements

To be considered for production, an add-on must adhere to the following requirements:

1. A [template directory](https://github.com/replicatedhq/kURL/tree/5ce2372da583844137efee28f55498393ea32e8d/addons/flannel/template/) with a [generate.sh](https://github.com/replicatedhq/kURL/blob/5ce2372da583844137efee28f55498393ea32e8d/addons/flannel/template/generate.sh) script and corresponding [workflow file](https://github.com/replicatedhq/kURL/blob/5ce2372da583844137efee28f55498393ea32e8d/.github/workflows/update-flannel.yaml) for automated generation of new add-on versions.
1. A [Testgrid spec](https://github.com/replicatedhq/kURL/tree/5ce2372da583844137efee28f55498393ea32e8d/addons/flannel/template/testgrid/) with adequate coverage for merging without human approval.
1. A [host-preflight.yaml](https://github.com/replicatedhq/kURL/blob/5ce2372da583844137efee28f55498393ea32e8d/addons/weave/template/base/host-preflight.yaml) file including system requirements and preflights for successful customer installations.
1. A [Troubleshoot spec](https://github.com/replicatedhq/kURL/blob/5ce2372da583844137efee28f55498393ea32e8d/addons/flannel/template/base/yaml/troubleshoot.yaml) file with collectors and analyzers for ease of troubleshooting customer issues.

### Manifest

The manifest is comprised of a set of directives for downloading and storing assets in add-on package archives.

| Directive | Description |
| --------- | ----------- |
| image [id] [image]                                 | A container image saved as a tar archive |
| yum [package]                                      | A package from a Yum repository |
| yum8 [package]                                     | A package from a Yum 8 repository |
| yumol [package]                                    | A package from a Yum Oracle Linux repository |
| apt [package]                                      | A package from an Apt repository |
| asset [src]                                        | A url or local path to a file |
| dockerout [dst] [Dockerfile] [--build-arg=VERSION] | A Dockerfile to build and save as a tar archive |

### install.sh

#### Kubernetes Resources

Kubernetes resources should be applied in the [addon_install](#addon_install) hook.

The `DIR` env var will be defined to the install root.
Any yaml that is ready to be applied unmodified should be copied from the add-on directory to the kustomize directory.

```bash
cp "$DIR/addons/weave/2.5.2/kustomization.yaml" "$DIR/kustomize/weave/kustomization.yaml"
```

The [insert_resources](https://github.com/replicatedhq/kURL/blob/5ce2372da583844137efee28f55498393ea32e8d/scripts/common/yaml.sh#L33), [insert_patches_strategic_merge](https://github.com/replicatedhq/kURL/blob/5ce2372da583844137efee28f55498393ea32e8d/scripts/common/yaml.sh#L22) and [insert_patches_json_6902](https://github.com/replicatedhq/kURL/blob/5ce2372da583844137efee28f55498393ea32e8d/scripts/common/yaml.sh#L44) functions can be used to add resources to the kustomization.yaml.

```bash
insert_resources "$DIR/kustomize/weave/kustomization.yaml" secret.yaml
```

The [render_yaml_file_2](https://github.com/replicatedhq/kURL/blob/5ce2372da583844137efee28f55498393ea32e8d/scripts/common/yaml.sh#L10) function can be used to substitute env vars in a yaml file at runtime.

```bash
render_yaml_file "$DIR/addons/weave/2.5.2/tmpl-secret.yaml" > "$DIR/kustomize/weave/secret.yaml"
```

After the kustomize directory has been prepared with resources and patches and the kustomization.yaml file has been updated, the add-on should call `kubectl apply -k` to deploy its resources to the cluster.

#### Host Packages

Host packages can be installed using the [install_host_archives](https://github.com/replicatedhq/kURL/blob/5ce2372da583844137efee28f55498393ea32e8d/scripts/common/host-packages.sh#L2) function.
They should be installed in either the [addon_pre_init](#addon_pre_init) hook or the [addon_install](#addon_install) hook.
Additionally, host packages can be installed in the [addon_join](#addon_join) hook if necessary on the secondary nodes.

```bash
install_host_archives "$DIR/addons/rook/$ROOK_VERSION" lvm2
```

### Publishing

After adding a new version of an add-on, the [versions.js](/web/src/installers/versions.js) file must be updated to make the version available to kURL. 

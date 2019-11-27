
Add-ons
======

## Structure

Each available add-on has a directory with subdirectories for each available version of the add-on.
Each subdirectory must have two files: `install.sh` and `Manifest`.

The Manifest file specifies a list of images required for the add-on.
These will be pulled during CI and saved to the directory <addon>/<version>/images/.

The install.sh script must provide a function <name> matching the add-on that should install the add-on by generating yaml in `kustomize/addon` and applying it.

Any other files in the <addon>/<version> subdirectory will be included in the package built for the add-on.
The package will be built and uploaded to s3://kurl-sh/dist/<addon>-<version>.tar.gz during CI.

## Runtime

The [addon](https://github.com/replicatedhq/kurl/blob/master/scripts/common/addon.sh) function in Kurl will first load all images from the add-on's `images/` directory and create the directory `<KURL_ROOT>/kustomize/<addon>`.
It will then dynamically source the `install.sh` script and execute the function named <addon>.

## Example for Weave 2.5.2

The Kurl install script would call the `addon` function to install Weave 2.5.2:

```
addon weave 2.5.2
```

That would fetch the package https://kurl-sh.s3.amazonaws.com/dist/weave-2.5.2.tar.gz and extract it to the Kurl install directory.
The Kurl `addon` function would then load the images in `<KURL_ROOT>/addons/weave/2.5.2/images` into docker, create the directory `<KURL_ROOT>/kustomize/weave`, source `<KURL_ROOT>/addons/weave/2.5.2/install.sh` and call `weave`.
The `weave` function should generate yaml and patches and place them in the directory `<KURL_ROOT>/kustomize/weave` and apply them with `kubectl apply -k`.

## Developing Add-ons

The `DIR` env var will be defined to the install root.
Any yaml that is ready to be applied unmodified should be copied from the addon directory to the kustomize directory.
```
cp "$DIR/addons/weave/2.5.2/kustomization.yaml" "$DIR/kustomize/weave/kustomization.yaml"
```

The [insert_resources](https://github.com/replicatedhq/kurl/blob/5e6c9549ad6410df1f385444b83eabaf42a7e244/scripts/common/yaml.sh#L29) function can be used to add an item to the resources object of a kustomization.yaml:
```
insert_resources "$DIR/kustomize/weave/kustomization.yaml" secret.yaml
```

The [insert_patches_strategic_merge](https://github.com/replicatedhq/kurl/blob/5e6c9549ad6410df1f385444b83eabaf42a7e244/scripts/common/yaml.sh#L18) function can be used to add an item to the `patchesStrategicMerge` object of a kustomization.yaml:
```
insert_patches_strategic_merge "$DIR/kustomize/weave/kustomization.yaml" ip-alloc-range.yaml
```

The [render_yaml_file](https://github.com/replicatedhq/kurl/blob/5e6c9549ad6410df1f385444b83eabaf42a7e244/scripts/common/yaml.sh#L18) function can be used to substitute env vars in a yaml file at runtime:
```
render_yaml_file "$DIR/addons/weave/2.5.2/tmpl-secret.yaml" > "$DIR/kustomize/weave/secret.yaml"
```

After the kustomize directory has been prepared with resources and patches and the kustomization.yaml file has been updated, the add-on should call `kubectl apply -k`.

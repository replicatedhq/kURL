
Addons
======

## Structure

Each available addon has a directory with subdirectories for each available version of the addon.
Each subdirectory must have two files: `install.sh` and `Manifest`.

The Manifest file specifies a list of images required for the addon.
These will be pulled during CI and saved to the directory <addon>/<version>/images/.

The install.sh script must provide a function <name> matching the addon that should install the addon by generating yaml in `kustomize/addon` and applying it.

Any other files in the <addon>/<version> subdirectory will be included in the package built for the addon.
The package will be built and uploaded to s3://kurl-sh/dist/<addon>-<version>.tar.gz during CI.

## Runtime

The [addon](https://github.com/replicatedhq/kurl/blob/master/scripts/common/addon.sh) function in Kurl will first load all images from the addon's `images/` directory and create the directory `<KURL_ROOT>/kustomize/<addon>`.
It will then dynamically source the `install.sh` script and execute the function named <addon>.

## Example for Weave 2.5.2

The Kurl install script would call the `addon` function to install Weave 2.5.2:

```
addon weave 2.5.2
```

That would fetch the package https://kurl-sh.s3.amazonaws.com/dist/weave-2.5.2.tar.gz and extract it to the Kurl install directory.
The Kurl `addon` function would then load the images in `<KURL_ROOT>/addons/weave/2.5.2/images` into docker, create the directory `<KURL_ROOT>/kustomize/weave`, source `<KURL_ROOT>/addons/weave/2.5.2/install.sh` and call `weave`.
The `weave` function should generate yaml and patches and place them in the directory `<KURL_ROOT>/kustomize/weave` and apply them with `kubectl apply -k`.

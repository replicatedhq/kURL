This is a template that can be used to create a new release of Contour.

1. Creation and modification of `contour.yaml`

Upstream yaml is taken from https://projectcontour.io/quickstart/contour.yaml, which then redirects to the relevant release yaml such as https://raw.githubusercontent.com/projectcontour/contour/release-1.11/examples/render/contour.yaml.

This yaml is given the following prefix:
```yaml
# From __upstreamurl__
# - Moved ConfigMap into separate template
# - Moved namespace into separate template
# - Removed envoy container host ports
```
and saved as contour.yaml.

The `kind: ConfigMap` document is removed and saved as tmpl-configmap.yaml.
The `kind: Namespace` document is removed entirely, as it is superseded by the existing tmpl-namespace.yaml.
The lines `hostPort: 80` and `hostPort: 443` are removed.

2. Editing of `tmpl-configmap.yaml`

The line
```yaml
    # minimum-protocol-version: "1.1"
```
is replaced by
```yaml
      minimum-protocol-version: "$CONTOUR_TLS_MINIMUM_PROTOCOL_VERSION"
```

This can be done with 
`sed -i 's/# minimum-protocol-version: "1.1"/  minimum-protocol-version: "\$CONTOUR_TLS_MINIMUM_PROTOCOL_VERSION"' base/tmpl-configmap.yaml`.

3. Insertion of values

`contour.yaml` is edited to have the correct upstream URL with 
`sed -i "s!__upstreamurl__!https://raw.githubusercontent.com/projectcontour/contour/release-1.11/examples/render/contour.yaml!g" base/contour.yaml"`.

`install.sh` is edited to have the correct directory with
`sed -i "s/__releasever__/1.11.0/g" base/install.sh"`.

`Manifest` is edited to have the correct images with
`sed -i "s/__releasever__/1.11.0/g" base/Manifest"` and
`sed -i "s/__envoyver__/1.16.2/g" base/Manifest"`.

`patches/job-image.yaml` is edited to have the correct image with
`sed -i "s/__releasever__/1.11.0/g" "base/patches/job-image.yaml"`

4. Insertion into index

`/web/src/installers/index.ts` is edited to insert the new Contour version within the `Installer` class.

5. Insertion into tests

???

6. Creation of PR

The `test-addon-pr` github action will initiate a testgrid run against the templated spec(s) in `./template/testgrid` when this addon version is updated or created. 
This spec should use `__testver___` and `__testdist__` as substitution parameters for the this addon.
Currently cross-addon PR testing is not supported.
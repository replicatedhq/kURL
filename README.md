<div align="center">
  <img alt="Kurl-logo" src="https://kurl.sh/kurl_logo@2x.png" />
</div>
<br/>

# kURL

kURL is a Kubernetes installer for airgapped and online clusters.

kURL relies on `kubeadm` to bring up the Kubernetes control plane, but there are a variety of tasks a system administrator must perform both before and after running kubeadm init in order to have a production-ready Kubernetes cluster, such as installing Docker, configuring Pod networking, or installing kubeadm itself.
The purpose of this installer is to automate those tasks so that any user can deploy a Kubernetes cluster with a single script.

## Getting Started

For more information please see [kurl.sh/docs/](https://kurl.sh/docs/)

## Community

For questions about using kURL, there's a [Replicated Community](https://help.replicated.com/community) forum, and a [#kurl channel in Kubernetes Slack](https://kubernetes.slack.com/channels/kurl).

## Notifications

kURL offers several optional [add-ons](https://kurl.sh/add-ons) for Kubernetes cluster creation.
These open-source technology add-ons are distributed under various open-source licenses.

One optional add-on available for object storage is [MinIO](https://github.com/minio/minio).
Use of MinIO is governed by the GNU AGPLv3 license that can be found in their [License](https://github.com/minio/minio/blob/master/LICENSE) file.

One optional add-on available for Metrics & Monitoring is Prometheus via the [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator), which includes Grafana.
Use of Grafana is currently governed by the GNU AGPL v3 license that can be found in their [License](https://github.com/grafana/grafana/blob/main/LICENSE) file.

## Contributing

Contributions are greatly appreciated. See [CONTRIBUTING.md](CONTRIBUTING.md) or more details. 
Before starting any work, please either comment on an existing issue, or file a new one.

## Releases

For details on each release, see the [changelog](https://github.com/replicatedhq/kURL/releases).
For Replicated vendors, detailed release notes are available at [Kubernetes Installer Release Notes](https://docs.replicated.com/release-notes/rn-kubernetes-installer) on the Replicated documentation site.

Release assets and changelog are available on the [GitHub Releases](https://github.com/replicatedhq/kURL/releases) page.

Releases are created by a GitHub Workflow when a tag is pushed.
The tag should follow the date format `vYYYY.MM.DD-#`.

A new release, from HEAD, can be tagged by running the following command:

```shell
make tag-and-release
```

To tag and release a specific commit:

```shell
make COMMIT_ID=<GITHUB_SHA> tag-and-release
```

The `tag-and-release` Make task enforces the git tree to be clean and a tag to be created against
the `main` branch. To override this behavior call the underlying script directly:

```shell
./bin/tag-and-release.sh --commit-id=<GITHUB_SHA> --no-main --outdated
```

## Software Bill of Materials

Signed SBOMs for kURL Go and Javascript dependencies are combined into a tar file and are included with each release.

- **kurl-sbom.tgz** contains SBOMs for Go  and Javascript dependencies
- **kurl-sbom.tgz.sig** is the digital signature for kurl-sbom.tgz
- **key.pub** is the public key from the key pair used to sign kurl-sbom.tgz

The following example illustrates using [cosign](https://github.com/sigstore/cosign) to verify that **kurl-sbom.tgz** has
not been tampered with.

```shell
$ cosign verify-blob --key key.pub --signature kurl-sbom.tgz.sig kurl-sbom.tgz
Verified OK
```

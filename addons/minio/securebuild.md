# MinIO SecureBuild migration

This is a **test-only branch**, `mikhail/minio-securebuild-test`. It replaces the
MinIO server references in the templates and regenerates only
`addons/minio/2025-10-15T17-29-55Z/`. Do not merge this branch as a production
migration: its purpose is to build an isolated candidate tarball for Testgrid.
The published add-on packages and version registry are unchanged.

The candidate reuses SecureBuild's existing `kotsadm/minio` image with its upstream
release tag. The existing packager saves a tagged Docker archive for offline
loading. The tag was verified on September 18, 2026 against the tested amd64 digest
below; the cluster tests additionally require APK release `r8` and record runtime
image IDs. Recheck the digest before subsequent runs because the published tag
can move when SecureBuild rebuilds dependencies.

## Run cluster tests without workflow changes

Push this branch, then dispatch the existing workflow:

```sh
gh workflow run test-addon.yaml --repo replicatedhq/kurl \
  --ref mikhail/minio-securebuild-test \
  -f addon=minio \
  -f version=2025-10-15T17-29-55Z \
  -f prefix="minio-securebuild-r8-$(date -u +%Y%m%dT%H%M%SZ)" \
  -f update-supported-versions=false
```

The workflow builds the candidate, uploads it under `s3://kurl-sh/pr/`, and queues
both MinIO spec files with the existing default OS pool. It substitutes the
candidate URL into `s3Override`; initial installations in the new scenarios use
the released package, and upgrades use the candidate at the same upstream
version. No shared supported-version metadata needs to be updated.

`template/testgrid/securebuild.yaml` adds PVC, hostpath, and three-node HA image
replacement tests with other add-on versions held fixed. They validate the
baseline image, preserve an object across upgrade, require the SecureBuild
package in running servers, exercise new writes, recreate a pod, and recheck
both objects. The HA case waits for all six MinIO replicas before and after the
upgrade. Existing legacy filesystem and Rook migration cases still run from
`k8s-docker.yaml`.

Template regeneration for this test branch substitutes `__MINIO_VERSION__` and
`__MINIO_DIR_NAME__` in every file under `template/base/` and copies file modes to
the matching version directory. It deliberately avoids the current generator's
version-registry insertion when regenerating an already registered version.

## Existing resources

- [MinIO package family](https://admin.sbld.io/package-families/909c0e8cd06bf53778627e20865d9ac5).
  Created September 16, 2026 around the existing packages. Monitoring is disabled
  pending timestamp-version support; this is not a Git-linked family.
- [Latest package](https://admin.sbld.io/packages/7a517cb6aa5a0fe42b34d00195e61e91408a539d73193b4ec9fcdd21caa56837):
  `minio-0.20251015`, version `0.20251015.172955`, with the OCI entrypoint subpackage.
  Release `r8` fixes the Go checksum failure following dependency remediation by
  building with `-mod=mod`. The security dependency updates remain enabled.
  [Build and package tests passed on amd64 and arm64](https://admin.sbld.io/executions/f70a60bb74ff13730835fdfaf4d41f23c360abd8c9325312).
- [Existing image](https://admin.sbld.io/images/i60t38UVFMQO145HIojgy6aH0NqvXwycn):
  publishes to `kotsadm/minio` and the Replicated library registries. Its APKO
  includes MinIO, its entrypoint, `mcli`, and runtime utilities. No new client
  package or kURL-specific server package is needed.

## Qualification

For a local single-server check, use a Docker environment:

```sh
addons/minio/test-securebuild-image.sh \
  kotsadm/minio@sha256:4fcdc39f829f70905b32b0c7916253caff84b67fb900dff4b923acdb3053da57 \
  RELEASE.2025-10-15T17-29-55Z
```

This rebuilt amd64 digest passed locally on September 16, 2026 after the `r8`
package repair. The [dependent image build](https://admin.sbld.io/builds/b64f68580232cbc85833f5b02f0e03ba27d99a2ab843b640)
ran automatically and published the existing upstream tag. The test checks the release, the default
entrypoint with `--quiet server /data`, kURL's legacy credential environment
variables, both health endpoints, S3 upload/download, format-file access,
graceful shutdown, and persistence after restart. It uses a disposable Docker
volume and container, exposes no host ports, and cleans both up on exit.

Before switching the add-on, run
Testgrid coverage for PVC, hostpath, HA, and upgrade/migration paths. The local
test covers a single server and does not replace those cluster tests.

## Remaining automation work

SecureBuild v0.0.509's family detector currently filters tags and then parses the stripped
tag as semantic version. It cannot convert MinIO's timestamp tags through the
family's regex capture groups. The package recipe's `var-transforms` only performs
the reverse conversion during builds. The configured package tag filter also
does not match upstream timestamp tags.

Before enabling monitoring, support and test this mapping end to end:

```text
upstream tag:    RELEASE.2025-10-15T17-29-55Z
package version: 0.20251015.172955
package name:    minio-0.20251015
image tag:       RELEASE.2025-10-15T17-29-55Z
```

Detection must retain the exact upstream tag and commit, preserve zero-padded
date/time fields, enforce a latest-only starting point, and avoid backfilling
older releases. Image tag generation must preserve the upstream timestamp tag.
The build's commit metadata must also follow the selected source commit.

For a future production migration, update the add-on generator and all
server image references together. The current references include the Manifest,
deployment, HA StatefulSet, both filesystem-migration deployments, and the
`kubectl set image` calls in `install.sh`. Replace the separate Docker build with
an image-readiness/promotion step which consumes a verified SecureBuild digest.
Existing released tags and historical add-on directories should remain intact.

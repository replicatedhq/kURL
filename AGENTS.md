# Agent Guide for kURL

This guide is for AI agents working in the kURL repository. It explains how the project is organized, how changes are made (especially add-on updates), how to test, and how the repository relates to the kURL-testgrid testing platform.

## 1. Project overview

**kURL** is a Kubernetes installer for air-gapped and online clusters, maintained by Replicated. It automates the tasks a cluster administrator must perform before and after running `kubeadm init` to create a production-ready Kubernetes cluster.

A user posts a YAML `Installer` manifest to the kURL.sh API and receives a deterministic hash. That hash can be used to fetch an install script (`https://kurl.sh/<hash>`) or an air-gap bundle (`https://kurl.sh/bundle/<hash>.tar.gz`). The installer then downloads pre-built add-on tarballs and host packages from the `kurl-sh` S3 bucket and executes the install/upgrade on the target node.

The kURL project has two main repositories:

- **kURL** (`/Users/xav/go/src/github.com/replicatedhq/kURL`) — builds the installer scripts, add-on packages, host packages, Go utilities, and the public API registry.
- **kURL-testgrid** (`/Users/xav/go/src/github.com/replicatedhq/kURL-testgrid`) — the test automation platform that provisions real Linux VMs, runs kURL installers, executes Sonobuoy conformance tests, and publishes results at `https://testgrid.kurl.sh`.

## 2. Repository structure

Key directories in this repo:

| Directory | Purpose |
|---|---|
| `addons/<name>/<version>/` | Add-on definitions, one directory per version. Each version contains at minimum `Manifest`, `install.sh`, and usually `host-preflight.yaml`. |
| `bin/` | Build, packaging, and release helper scripts. |
| `bundles/` | Docker build contexts for host packages (Kubernetes RPM/DEB repos per OS). |
| `cmd/` | Go entrypoints; `cmd/kurl` is the main CLI binary. |
| `hack/` | Local development helpers, test data, and test Dockerfiles. |
| `kurl_util/` | Go utilities built into binaries and the `replicated/kurl-util` Docker image. |
| `packages/` | Host-package definitions (e.g., `kubernetes`, `host/openssl`, `host/fio`). |
| `pkg/` | Go library code for the `kurl` CLI. |
| `scripts/` | The bash installer source (`install.sh`, `join.sh`, `upgrade.sh`, `tasks.sh`, `common/`). |
| `testgrid/specs/` | Testgrid YAML specs for OS images and test scenarios. |
| `tools/` | Additional tooling. |
| `web/src/installers/` | Frontend version registry; `versions.js` lists available add-on versions. |
| `.github/workflows/` | CI/CD workflows. |

Important documents:

- `README.md` — project overview and community links.
- `ARCHITECTURE.md` — manifest format, API services, object storage, add-on lifecycle, release workflows.
- `CONTRIBUTING.md` — development workflow, remote testing, environment setup.
- `addons/README.md` — add-on structure, Manifest directives, lifecycle hooks.
- `testgrid/specs/README.md` — how Testgrid specs work.
- `docs/arch/adr-003-external-addons.md` — external add-on model (`kotsadm`).
- `CODEOWNERS` — global owner `@replicatedhq/embedded-kubernetes`.

## 3. How to approach changes

### General workflow

1. **Identify the scope.** Is this a core installer change, an add-on change, a Testgrid-only change, or a version bump? Core scripts live in `scripts/`. Add-ons live in `addons/<name>/<version>/`. Testgrid specs live in `testgrid/specs/` and in add-on `template/testgrid/` directories.
2. **Make the minimal change.** Edit only the source files. Generated files (e.g., `build/`, `dist/`, `addons-gen.json`, `supported-versions-gen.json`) are produced by `make` targets and should not be hand-edited.
3. **Keep `scripts/Manifest` in sync with `hack/testdata/manifest/clean`.** `make test` compares these two files and fails if they differ. If you modify `scripts/Manifest`, update the test data copy as well.
4. **Run local tests.** See the Testing section below.
5. **Let CI run Testgrid for add-on changes.** The `test-addon-pr.yaml` workflow detects modified add-ons and queues Testgrid runs automatically.

### When working on a remote Linux VM

The install scripts are not macOS-compatible. For real-world testing, use `make watchrsync` after exporting:

```bash
export GOOS=linux
export GOARCH=amd64
export DOCKER_DEFAULT_PLATFORM=linux/amd64
export REMOTES="USER@TARGET_SERVER_IP"
make watchrsync
```

`bin/watchrsync.js` continuously syncs local builds to `~/kurl` on the remote server.

### macOS local-build prerequisites

Install `gnu-sed` and `md5sha1sum` (e.g., via Homebrew) to run local build scripts. Apple Silicon hosts should also set `GOOS=linux`, `GOARCH=amd64`, and `DOCKER_DEFAULT_PLATFORM=linux/amd64` before building.

## 4. How to update add-ons

Add-ons are the primary extension point of kURL. Each add-on is a versioned directory with a declarative `Manifest`, an `install.sh` shell script, and optional templates.

### Add-on structure

```text
addons/<name>/<version>/
  Manifest                # assets, images, host packages to download
  install.sh              # defines a function named exactly like the add-on
  host-preflight.yaml     # optional Troubleshoot.sh preflight spec
  assets/                 # generated at build time
  images/                 # generated at build time
  ...
```

The `install.sh` must define a function with the exact add-on name (e.g., `function containerd()`). Lifecycle hooks are defined in `addons/README.md`:

- `addon_fetch`
- `addon_load`
- `addon_preflights`
- `addon_pre_init`
- `addon_install` (required)
- `addon_already_applied`
- `addon_join`
- `addon_post_init`
- `addon_outro`

### Manifest directives

Common directives (see `addons/README.md` for the full list):

```text
image pause k8s.gcr.io/pause:3.6
yum libzstd
yum8 container-selinux
yumol <pkg>
apt containerd
apt24 containerd
yum2023 containerd
asset runc https://github.com/opencontainers/runc/releases/download/v1.3.5/runc.amd64
dockerout rhel-9 addons/containerd/template/Dockerfile.rhel9 1.7.29
```

### Adding a new add-on version

1. Create or generate the version directory under `addons/<name>/<version>/`.
2. Ensure it contains `Manifest`, `install.sh`, and `host-preflight.yaml`.
3. Add or update Testgrid specs under `addons/<name>/template/testgrid/*.yaml` if needed.
4. Register the new version in `web/src/installers/versions.js`.
5. Run `make generate-addons` to update `addons-gen.json` and `supported-versions-gen.json`.
6. Build the package locally: `make dist/<name>-<version>.tar.gz`.
7. Test with Testgrid or via `make watchrsync` on a remote Linux VM.

### Templated add-ons

Some add-ons are auto-generated from a `template/` directory:

- `addons/containerd/template/` — `script.sh`, Dockerfiles, and testgrid specs.
- `addons/flannel/template/` — `generate.sh`, `base/`, and testgrid specs.

For templated add-ons, changes should be made in the template, then the version is regenerated. Do not hand-edit generated version directories.

### External add-ons

`kotsadm` is an external add-on (see `docs/arch/adr-003-external-addons.md`). It is built and released from `replicatedhq/kots`, publishes a `versions.json`, and the `import-external-addons` action copies packages into the kURL S3 bucket. The kURL API merges these with internal versions.

## 5. Testing

### Local tests

```bash
# Lint, vet, Go tests, and manifest check
make test

# Go tests only
go test ./cmd/... ./pkg/...
make -C kurl_util test

# Shell tests in Docker
make docker-test-shell

# Containerd configure/upgrade regression tests
make docker-test-containerd

# Build a specific add-on package
make dist/containerd-1.7.29.tar.gz

# Build Kubernetes host packages for a specific OS
make build/packages/kubernetes/1.31.14/ubuntu-22.04
make build/packages/kubernetes/1.31.14/images
```

### Testgrid integration

Testgrid is the primary end-to-end testing platform. It is a separate repository (`kURL-testgrid`), but the specs that drive it live in this repo:

- `testgrid/specs/os-*.yaml` — OS image pools.
- `testgrid/specs/deploy.yaml`, `full.yaml`, `latest.yaml`, `storage-migration.yaml`, `customer-migration-specs.yaml`, `k8s-upgrade.yaml` — test scenarios.

Active CI usage is documented in `testgrid/specs/README.md`. Workflows submit runs via the `replicated/tgrun` Docker image:

```bash
tgrun queue --spec <spec> --os-spec <os-spec> --ref <ref> --api-token <token>
```

Add-ons can define their own specs under `addons/<name>/template/testgrid/*.yaml`. During add-on tests, `bin/test-addon.sh` substitutes `__testver__` and `__testdist__` placeholders in the spec templates.

### How Testgrid works (high-level)

1. A user or CI invokes `tgrun queue` with a test spec and OS spec.
2. `tgrun` submits each installer spec to the kURL API to get a runnable URL/hash.
3. `tgrun` enqueues planned VM instances to the TGAPI (Testgrid API).
4. `tgrun run` (the runner daemon) polls TGAPI, creates KubeVirt VMs on bare-metal hosts, and runs the test scripts.
5. VMs report status, logs, Sonobuoy results, and support bundles back to TGAPI.
6. The web UI reads TGAPI and displays results at `https://testgrid.kurl.sh`.

Key Testgrid API endpoints for public data:

- `POST /api/v1/run/{refId}` — get a run with its instances.
- `GET /api/v1/instance/{instanceId}/logs` — main instance logs.
- `GET /api/v1/instance/{nodeId}/node-logs` — per-node logs.
- `GET /api/v1/instance/{instanceId}/sonobuoy` — Sonobuoy results.

## 6. Build and release

### Primary build targets

```bash
make build/install.sh      # single-file installer script
make build/join.sh         # single-file join script
make build/upgrade.sh      # single-file upgrade script
make build/tasks.sh        # single-file tasks script
make dist/<addon>-<version>.tar.gz
make dist/common.tar.gz
make dist/kurl-bin-utils-<version>.tar.gz
make build/bin/kurl        # kurl CLI
make kurl-util-image       # replicated/kurl-util:alpha
```

### Script assembly

`build/install.sh` is assembled from `scripts/install.sh` by inlining every file referenced by `. $DIR/scripts/...` between the `# Magic begin` and `# Magic end` markers. The same pattern applies to `join.sh`, `upgrade.sh`, and `tasks.sh`.

### CI/CD workflows

- `.github/workflows/build-test.yaml` — runs on every PR (Go mod tidy, kurl_util tests, kurl build, shell tests, containerd tests).
- `.github/workflows/deploy-staging.yaml` — runs on every merge to `main`. Builds packages, uploads to `s3://kurl-sh/staging/<version>-<sha>/`, generates `addons-gen.json`/`supported-versions-gen.json`, and queues Testgrid.
- `.github/workflows/deploy-prod.yaml` — triggered by tags `v*.*.*`. Copies staging packages to `s3://kurl-sh/dist/<version>/`, creates a GitHub release, generates SBOMs, and queues Testgrid.
- `.github/workflows/test-addon-pr.yaml` — detects modified add-ons in PRs and invokes `test-addon.yaml` for each.
- `.github/workflows/test-addon.yaml` — builds a single add-on package, uploads to S3, and queues Testgrid using the add-on's template specs.
- `.github/workflows/update-<addon>.yaml` — scheduled workflows that generate PRs for new upstream add-on versions (e.g., `update-containerd.yaml`, `update-flannel.yaml`).

### Release versioning

- Production tags: `vYYYY.MM.DD-#` (e.g., `v2024.07.02-0`).
- Staging versions: `<latest-tag>-<short-sha>` (e.g., `v2024.07.02-0-5af497c`).
- `make tag-and-release` creates a production tag and triggers the release workflow.
- The current release is advertised by `s3://kurl-sh/dist/VERSION` and `s3://kurl-sh/staging/VERSION`.

## 7. Conventions and gotchas

- **Add-on directory names** are lowercase (`containerd`, `flannel`, `rook`).
- **Version directories** use the upstream version string (`1.7.29`, `2.8.1`).
- **All shell functions in an add-on** should be prefixed with the add-on name to avoid collisions (e.g., `containerd_configure`).
- **`versions.js`** is the source of truth for selectable add-on versions. The generated `addons-gen.json` and `supported-versions-gen.json` are produced by `make generate-addons`.
- **`scripts/Manifest`** must stay in sync with `hack/testdata/manifest/clean`; `make test` enforces this.
- **Generated version directories** should not be hand-edited for templated add-ons; edit the template and regenerate.
- **Testgrid OS filtering is opt-out** via `unsupportedOSIDs`; there is no `supportedOSIDs`.
- **Linux/amd64 required** for runtime testing. The scripts are not macOS-compatible; use a remote Linux VM or Docker.
- **On Apple Silicon**, set `GOOS=linux`, `GOARCH=amd64`, and `DOCKER_DEFAULT_PLATFORM=linux/amd64` before building.

## 8. Useful commands

```bash
# Full local test suite
make test

# Build the installer script
make build/install.sh

# Build an add-on package
make dist/<addon>-<version>.tar.gz

# Generate add-on metadata
make generate-addons

# Watch and sync builds to a remote Linux test VM
export GOOS=linux GOARCH=amd64 DOCKER_DEFAULT_PLATFORM=linux/amd64 REMOTES="USER@IP"
make watchrsync

# Run shell tests in Docker
make docker-test-shell
```

## 9. Key files for agents to know

- `Makefile` — primary build orchestration.
- `scripts/install.sh` — entrypoint source with `Magic begin/end` markers.
- `scripts/Manifest` and `hack/testdata/manifest/clean` — must stay in sync.
- `scripts/common/addon.sh` — add-on runtime orchestration.
- `bin/save-manifest-assets.sh` — downloads/builds all assets described by a `Manifest`.
- `web/src/installers/versions.js` — human-edited version registry.
- `addons-gen.json` and `supported-versions-gen.json` — generated API metadata.
- `.github/workflows/deploy-staging.yaml` and `.github/workflows/deploy-prod.yaml` — release pipelines.
- `.github/workflows/test-addon-pr.yaml` — PR add-on testing.
- `bin/test-addon.sh` — submits add-on Testgrid runs.
- `pkg/cli/commands.go` — `kurl` CLI command tree.

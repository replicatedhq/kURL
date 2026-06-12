# Testgrid Specs

This document describes how Testgrid test specs and OS specs are defined, how they determine which OSs to run on, and which files are actively used in CI.

## Overview

Testgrid runs are driven by YAML spec files that come in two categories:

1. **Test specs** (`*.yaml`) — define what to install (kURL installer spec, upgrade spec, scripts, etc.)
2. **OS specs** (`os-*.yaml`) — define the pool of operating systems the tests run against

Both are submitted to Testgrid via `tgrun queue --spec <test-spec> --os-spec <os-spec>`.

---

## How OSs Are Determined

Testgrid uses an **opt-out** model:

- A test spec runs on **all OSs defined in the OS spec file** by default.
- To exclude an OS, the test spec lists its `id` under `unsupportedOSIDs`.

### Example

```yaml
# testgrid/specs/os-latest.yaml
- id: ol-8x
  name: Oracle Linux
  version: "8.x"
  vmimageuri: https://cloud.centos.org/.../CentOS-8-GenericCloud...qcow2
  preinit: |
    curl -L -o centos2ol.sh https://...
    bash centos2ol.sh -r

# testgrid/specs/full.yaml
- name: k8s119_containerd149
  installerSpec:
    kubernetes:
      version: 1.19.x
    containerd:
      version: 1.4.9
  unsupportedOSIDs:
    - ubuntu-2204   # containerd 1.4.x is not available on ubuntu 22.04
    - rocky-91      # containerd < 1.6 is not supported on rhel 9 variants
    - amazon-2023   # Kubernetes versions < 1.24 are not supported on Amazon Linux.
```

In this example, the `k8s119_containerd149` test runs on **every OS in `os-latest.yaml` except** `ubuntu-2204`, `rocky-91`, and `amazon-2023`.

---

## Active OS Spec Files

Not all `os-*.yaml` files are read automatically. CI workflows explicitly pass one OS spec file per `tgrun queue` invocation.

| File | Used by | Purpose |
|------|---------|---------|
| `os-latest.yaml` | `deploy-prod.yaml`, `deploy-staging.yaml`, addon tests | Default OS pool for release and addon tests |
| `os-firstlast.yaml` | `cron-testgrid-staging.yaml`, `cron-testgrid-production-monthly.yaml` | Smaller OS pool for daily/monthly cron tests |
| `os-customer-common.yaml` | `cron-testgrid-staging.yaml` (storage-migration + customer-migration jobs), `cron-testgrid-production-monthly.yaml` (storage-migration + customer-migration jobs) | OSs relevant to customer migration scenarios |

### Unused / Legacy OS Spec Files

| File | Status |
|------|--------|
| `os-full.yaml` | **Not referenced** by any workflow. Contains a larger historical OS list. |
| `os-removed.yaml` | **Not referenced** by any workflow. Preserved as a record of removed OS configurations. |

---

## Test Spec Files

### Main Test Specs

| File | Used by | Description |
|------|---------|-------------|
| `deploy.yaml` | Release workflows (`deploy-prod`, `deploy-staging`) | Tests the release artifact before/after promotion |
| `full.yaml` | Cron workflows (`cron-testgrid-staging`, `cron-testgrid-production-monthly`) | Comprehensive test matrix covering many kURL configurations |
| `latest.yaml` | — | (See repo for current usage) |
| `storage-migration.yaml` | `cron-testgrid-staging.yaml` (testgrid-daily-storage-migration job), `cron-testgrid-production-monthly.yaml` (testgrid-weekly-storage-migration-specs job) | Tests for storage migration scenarios |
| `customer-migration-specs.yaml` | Customer migration workflows | Tests for customer-specific migration paths |
| `k8s-upgrade.yaml` | — | Kubernetes upgrade tests |

### Addon Test Specs

Each addon can define its own Testgrid specs under:

```
addons/<name>/template/testgrid/*.yaml
```

Examples:
- `addons/flannel/template/testgrid/k8s-ctrd.yaml`
- `addons/containerd/template/testgrid/k8s-ctrd.yaml`
- `addons/rook/template/testgrid/k8s-docker.yaml`

These are submitted independently via the `addon-testgrid-tester` GitHub Action (`bin/test-addon.sh`), which iterates over all `.yaml` and `.yml` files in the addon's `template/testgrid/` directory and queues them with `tgrun`.

**Default OS spec for addons:** `os-latest.yaml` (used when `testgrid-os-spec-path` is not explicitly provided in the workflow).

---

## How the `unsupportedOSIDs` Field Works

- If an OS `id` appears in `unsupportedOSIDs`, that test case is **skipped** on that OS.
- If an OS `id` is **not** listed, the test runs on it.
- There is no `supportedOSIDs` field; the default is always "run on everything."

Common reasons for excluding an OS:
- Component version not supported on that OS (e.g., Docker on RHEL 9 variants)
- Kernel too old for a feature (e.g., Rook 1.8+ on CentOS 7.4)
- Package availability (e.g., containerd 1.4.x not available on Ubuntu 22.04)

---

## Spec Substitution for Addons

When addon tests run, `bin/test-addon.sh` performs two substitutions before submitting:

- `__testver__` → the actual addon version
- `__testdist__` → the S3 URL of the built addon package

This allows addon templates to reference the version and package under test dynamically.

---

## Summary

- **Testgrid does not auto-discover spec files.** Each workflow explicitly passes `--spec` and `--os-spec` to `tgrun`.
- **Only `os-latest.yaml`, `os-firstlast.yaml`, and `os-customer-common.yaml` are actively used.** `os-full.yaml` and `os-removed.yaml` are not referenced by any CI workflow.
- **OS filtering is opt-out via `unsupportedOSIDs`.** If an OS is not listed there, the test runs on it.
- **Addons define their own test specs** and are submitted separately via the `addon-testgrid-tester` action.

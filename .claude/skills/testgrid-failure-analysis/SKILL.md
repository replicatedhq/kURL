---
name: testgrid-failure-analysis
description: Use when analyzing a failed Testgrid kURL run to fetch the run results, failure logs, and encrypted support bundles from the Testgrid API and write them into a directory for offline analysis; also use when cancelling queued/stuck Testgrid runs, marking zombie instances failed, or cleaning up orphaned KubeVirt VMs on the Testgrid hosts; trigger with "testgrid failure analysis", "fetch testgrid logs", "get support bundle from Testgrid", "analyze Testgrid run", "cancel testgrid run", "skip testgrid run", "testgrid queue", or "clean up testgrid hosts".
---

# Testgrid failure analysis

This skill helps an agent collect the artifacts of a failed [Testgrid](https://testgrid.kurl.sh/) run so they can be analyzed locally.

## What it does

1. Queries the Testgrid API for a run by `refId`.
2. Identifies every failed instance (`isSuccess == false`, not unsupported, not skipped, not cancelled, and finished).
3. For each failure, fetches:
   - The instance metadata (`instance.json`)
   - The main instance logs (populated when the VM fails to start)
   - Sonobuoy results, if any
   - The per-node logs from the actual test VMs (`{nodeId}.log.txt`)
   - Any encrypted support bundles whose S3 URLs are printed in the node logs
4. Writes everything into a structured output directory ready for an agent to inspect.

## Important details from the codebase

- Public API base path is `/api/v1`. The endpoints used are:
  - `POST /api/v1/run/{refId}` — returns the run with its `instances` array, plus `success_count` and `failure_count`.
  - `GET /api/v1/instance/{instanceId}/logs` — returns `{"logs": "..."}` from the `testinstance.output` column.
  - `GET /api/v1/instance/{nodeId}/node-logs` — returns `{"logs": "..."}` from the `clusternode.output` column.
  - `GET /api/v1/instance/{instanceId}/sonobuoy` — returns `{"results": "..."}`.
- The open-source `/api/v1` endpoints are **not** authenticated by default (the `api-token` auth middleware only protects the runner endpoints under `/v1`). However, an optional `--api-token` is accepted and sent as HTTP Basic Auth with username `token` and the provided password, for deployments that add authentication. `--api-key` is kept as a deprecated alias for backward compatibility.
- Support bundles are collected by the test script (`tgrun/pkg/runner/vmi/embed/runcmd.sh` → `collect_support_bundle`) and uploaded to S3 with the handler at `POST /v1/instance/{instanceId}/bundle`. The S3 URL is printed in the node log output, which is why this skill scans the logs for it.
- The bundle is encrypted with the `age` file format using a scrypt passphrase. The API stores it with key pattern `{instanceId}-{unix}/bundle.tgz.age`. The downloaded file keeps the `.age` extension.
- If you provide the age passphrase, the helper script will try to decrypt each bundle in place with `age -d -p`.

## Node IDs used by the runner

Testgrid creates one initial-primary node plus optional additional nodes. The node IDs are predictable from the instance ID and the `numPrimaryNodes` / `numSecondaryNodes` fields, so the skill tries:

- `{instanceId}-initialprimary`
- `{instanceId}-primary-1` ... `{instanceId}-primary-{numPrimaryNodes-1}`
- `{instanceId}-secondary-0` ... `{instanceId}-secondary-{numSecondaryNodes-1}`

Only nodes that actually produced logs will be saved.

## How to use

Run the helper script shipped with this skill:

```bash
python3 .claude/skills/testgrid-failure-analysis/fetch.py \
  --api-endpoint https://api.testgrid.kurl.sh \
  --ref-id <RUN_REF_ID> \
  --output-dir ./testgrid-analysis/<RUN_REF_ID> \
  [--api-token <TOKEN>] \
  [--age-passphrase <PASSPHRASE>]
```

Environment variables are also supported:

- `TESTGRID_API_TOKEN` → `--api-token` (`TESTGRID_API_KEY` is still read as a fallback)
- `TESTGRID_AGE_PASSPHRASE` → `--age-passphrase`

## Output layout

```
<output-dir>/
  run.json                    # full run response
  <instanceId>/
    instance.json             # instance metadata
    logs.txt                  # main instance output, if any
    sonobuoy.txt              # sonobuoy results, if any
    <instanceId>-initialprimary.log.txt
    bundle-<nodeId>-0.tgz.age # encrypted support bundle
    bundle-<nodeId>-0.tgz     # decrypted support bundle (if passphrase supplied)
```

## What to do next

After fetching, read the `run.json` summary, open the per-instance logs, and inspect any decrypted support bundles. If a bundle could not be downloaded, grep the corresponding node log for `bundle.tgz.age` to find the raw S3 URL.

## Run and instance lifecycle

An instance is **pending** when `dequeuedAt == null` (in the runner queue), **running** when `dequeuedAt != null && finishedAt == null`, and **finished** once `finishedAt` is set. `isSkipped`/`isUnsupported` instances are excluded from a run's `success_count`/`failure_count`. The UI shows pending+running instances as in-flight; a VM that never reports back leaves its instance in "running" forever (a zombie).

Useful enumeration patterns:

- `GET /api/v1/runs?pageSize=100&currentPage=N` — every run includes `pending_runs` (count of `dequeuedAt == null` instances), so pending work can be counted without fetching every run's instances.
- Stuck/running instances: fetch `POST /api/v1/run/{refId}` and filter `finishedAt == null && !isSkipped && !isUnsupported`.
- Run names are `pr-<PR#>-<mergeCommitSha>-<addon>-<version>-<spec>-<timestamp>` (for PR-triggered runs). Because GitHub sets `GITHUB_SHA` to the PR *merge commit* for `pull_request` events, **each push to a PR produces a new batch prefix** — this is the key to "cancel everything older than the newest batch".

## Cancelling queued or stuck work via the API

**Preferred (kURL-testgrid #1080, merged 2026-10-14): the unified cancel endpoints.** One call per run covers both queued and running work, and runner hosts delete the affected VMs themselves:

- **`POST /api/v1/ref/{refId}/cancel`** (browser-facing, CORS) and **`POST /v1/ref/{refId}/cancel`** — cancels a whole run: pending instances are marked `is_skipped=true` (permanently dequeued), running instances are marked finished with `cancelled_at` set and `failure_reason='cancelled'`. Returns `{"pendingCancelled": N, "runningCancelled": M}`. Cancelled instances are excluded from success/failure counts; the UI shows them as "Cancelled" (amber).
- **`POST /v1/instance/{instanceId}/cancel`** — same for a single instance.
- **`GET /v1/instances/cancelled`** — runner-facing feed of instance IDs cancelled in the last 24h (skipped/pending ones excluded, since no host ever created resources for them).

Host-side reconciliation: each runner's existing 30s loop runs `ReconcileCancelledVMIs`, which polls that feed and deletes local VMIs matched by the `testgrid.kurl.sh/testid` annotation or `{instanceId}-` name prefix (the prefix match also covers annotation-less `-sendlogs` VMs), then reclaims the instance's PVCs (finalizers stripped first), bound PVs + `/var/openebs/local/pvc-*` paths, and `cloud-init-{id}-*` secrets — immediately instead of waiting for the ~8h age-based cleanup. It is idempotent and NotFound-tolerant.

Verify a host has the new code: `strings /bin/tgrun | grep -c ReconcileCancelledVMIs` (nonzero) — the endpoints existing in tgapi is not enough; each host's tgrun must be new enough to reconcile.

Caveat: cancel only touches instances that are pending or running **in the DB**. It cannot help instances that already finished — see "Cleaning up VMs" for the leftover cases.

Legacy/fallback endpoints (still useful for zombies the cancel API can't see):

- **`POST /v1/skip/ref/{refId}`** — cancels every **pending** instance of a run only (`is_skipped=true`, `dequeued_at=now()`).
- **`POST /v1/instance/{instanceId}/finish`** with body `{"success": false, "failureReason": "..."}` — marks an instance finished/failed. Once `finished_at` is set, a late *success* report from the VM is a no-op, but a late *failure* report overwrites `failure_reason` unconditionally — manual failure marks are sticky against success.

All are on the unauthenticated router in OSS; send the token as basic auth `token:<TESTGRID_API_TOKEN>` anyway in case the deployment adds auth.

## Cleaning up VMs on the Testgrid hosts

The runners are three bare-metal hosts, `testgrid-prd-01` / `-02` / `-03`, each its own **single-node Kubernetes cluster** (`ssh testgrid-prd-0N`, then `sudo kubectl ...`). Tests run as KubeVirt VMs.

- The runner creates bare **`VirtualMachineInstance`** objects (no owning `VirtualMachine` controller) in the **`default`** namespace. Deleting the VMI kills its `virt-launcher-*` pod and nothing respawns it — this is also what the runner's own cleanup loop does.
- VMI names are `{instanceId}-{nodeName}` (e.g. `...-initialprimary`, `...-secondary-0`), plus short-lived `{...}-sendlogs` VMs that ship logs for finished tests.
- To kill everything: `sudo kubectl delete vmi -n default --all`. To kill one test's nodes: `kubectl get vmi -n default -o name | grep <instanceId> | xargs -r kubectl delete -n default`.
- Since kURL-testgrid #1080, the cancel API reconciles host VMs automatically, so the classic two-way trap is narrower but not gone. **What still needs manual VMI deletion**: (a) instances that *finished* but whose VMs leaked (cancel only touches pending/running rows — verify with `GET /v1/instance/{id}/status`, which returns `{}` while running and `{"isSuccess": ...}` once finished, plus `GET /v1/instance/{id}/cancelled`); (b) stuck `-sendlogs` VMs, which have no instance row at all and are only reaped by the 8-hour timeout — a Running sendlogs VMI older than ~30 min is a stuck log-shipper and safe to delete (tracked as Shortcut #140012); (c) orphaned secondary/primary VMs of multi-node tests whose initialprimary already went away.
- The reverse half of the trap is unchanged: deleting a VMI does not update the API, so mark the instance `/finish`ed or `/cancel`led as well.
- Deleting VMIs leaves per-node **PVCs** (`{instanceId}-{node}-disk`), **PVs** (local-path under `/var/openebs/local/pvc-<uuid>`), and **`cloud-init-*` secrets**. The runner's `CleanUpData` loop reclaims them by age (PVCs after ~8h, PVs after ~8.3h, secrets after ~9h). For immediate reclamation, strip finalizers before deleting (an OpenEBS webhook bug can wedge them), delete PVC then PV, and `rm -rf` the PV's `spec.local.path` (only ever under `/var/openebs/local/pvc-*`). Test disks are 100Gi sparse images, so actual disk pressure is usually far lower than the PVC count suggests.
- Always check `kubectl get vmi` first and skip anything still legitimately running (e.g. an active release run's instances).
- **Dispatch gate / fleet slow-down diagnostic**: each host's dequeue loop (`canScheduleNewVM`) refuses new work while *any* `virt-launcher-*` pod is Pending, so a resource-saturated host silently stops picking up tests. Symptom: run counters show running-runs stuck at ~15-16 fleet-wide while the queue is deep. Check per host: `sudo kubectl get pods -n default | grep virt-launcher | grep Pending` and `sudo kubectl get vmi -n default | grep -c Running` (watch the Running share that is `-sendlogs` zombies). Runner status heartbeats (free CPU/RAM/active tests per hostname) go to statsd only — there is no TGAPI endpoint for host health.

## Why the queue floods (CI fan-out mechanics)

Understanding this helps when deciding what to cancel:

- `.github/workflows/test-addon-pr.yaml` builds its matrix via `bin/addon-has-changes-matrix.sh`: **one matrix leg per changed add-on version directory**. For template-generated add-ons (containerd, flannel), a cross-cutting change rewrites every version directory, so one push = one Testgrid run per version (containerd: 42 legs × ~61 instances ≈ 2,500 VMs per push).
- The workflow's `paths: addons/**` filter on `pull_request` events is evaluated against the **whole PR diff**, not the pushed commits — every push re-fires the full matrix regardless of what the push changed.
- The workflow's `concurrency: cancel-in-progress: true` cancels outstanding *GitHub jobs* on a new push but **cannot dequeue already-queued Testgrid runs** — they must be cancelled via the API (`POST /api/v1/ref/{refId}/cancel`, see above).
- The matrix is throttled (`max-parallel: 5`), so legs emit runs in waves; a cancelled workflow run may leave later waves unqueued.

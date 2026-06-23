---
name: testgrid-failure-analysis
description: Use when analyzing a failed Testgrid kURL run to fetch the run results, failure logs, and encrypted support bundles from the Testgrid API and write them into a directory for offline analysis; trigger with "testgrid failure analysis", "fetch testgrid logs", "get support bundle from Testgrid", or "analyze Testgrid run".
---

# Testgrid failure analysis

This skill helps an agent collect the artifacts of a failed [Testgrid](https://testgrid.kurl.sh/) run so they can be analyzed locally.

## What it does

1. Queries the Testgrid API for a run by `refId`.
2. Identifies every failed instance (`isSuccess == false`, not unsupported, not skipped, and finished).
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
python3 .opencode/skills/testgrid-failure-analysis/fetch.py \
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

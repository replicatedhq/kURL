#!/usr/bin/env python3
"""Fetch Testgrid failure logs and support bundles for analysis.

Queries the public Testgrid API endpoints:
  GET /api/v1/runs
  POST /api/v1/run/{refId}
  GET /api/v1/instance/{id}/logs
  GET /api/v1/instance/{nodeId}/node-logs
  GET /api/v1/instance/{id}/sonobuoy

For every failed instance in a run, it downloads the instance logs and the per-node
logs, scans them for encrypted support-bundle URLs, downloads the bundles, and
optionally decrypts them with age when an age passphrase is supplied.
"""

import argparse
import base64
import json
import os
import re
import subprocess
import sys
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError


def api_request(url, api_key=None, data=None, method=None, timeout=60):
    headers = {"Accept": "application/json"}
    if api_key:
        creds = base64.b64encode(b"token:" + api_key.encode()).decode()
        headers["Authorization"] = f"Basic {creds}"
    if data is not None:
        method = method or "POST"
        headers["Content-Type"] = "application/json"
    req = Request(url, data=data, headers=headers, method=method)
    with urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8")


def download(url, path, timeout=300):
    req = Request(url, headers={"User-Agent": "testgrid-failure-analysis"})
    with urlopen(req, timeout=timeout) as resp:
        with open(path, "wb") as f:
            f.write(resp.read())


def node_ids(instance_id, num_primary, num_secondary):
    """Return the node IDs the runner creates for a given instance."""
    ids = [f"{instance_id}-initialprimary"]
    for i in range(1, max(1, num_primary)):
        ids.append(f"{instance_id}-primary-{i}")
    for i in range(num_secondary):
        ids.append(f"{instance_id}-secondary-{i}")
    return ids


def save_json(path, obj):
    with open(path, "w") as f:
        json.dump(obj, f, indent=2)


def main():
    parser = argparse.ArgumentParser(
        description="Fetch Testgrid run failures, logs, and support bundles.")
    parser.add_argument(
        "--api-endpoint", required=True,
        help="Testgrid API base URL, e.g. https://api.testgrid.kurl.sh")
    parser.add_argument(
        "--ref-id", required=True,
        help="Testgrid run refId (the run identifier shown in the UI)")
    parser.add_argument(
        "--output-dir", required=True,
        help="Directory where artifacts will be written")
    parser.add_argument(
        "--api-token", "--api-key", dest="api_token",
        default=os.environ.get("TESTGRID_API_TOKEN") or os.environ.get("TESTGRID_API_KEY"),
        help="Optional API token. If the server requires it, sent as basic-auth password with username 'token'. Reads TESTGRID_API_TOKEN (preferred) or TESTGRID_API_KEY (legacy) if not provided.")
    parser.add_argument(
        "--age-passphrase", default=os.environ.get("TESTGRID_AGE_PASSPHRASE"),
        help="Optional age passphrase to decrypt downloaded .age support bundles")
    parser.add_argument(
        "--age-bin", default="age",
        help="Path to the age decryption binary")
    parser.add_argument(
        "--page-size", type=int, default=1000,
        help="Page size for the run query")
    args = parser.parse_args()

    base = args.api_endpoint.rstrip("/")
    if not base.endswith("/api/v1"):
        base = base + "/api/v1"

    out_dir = args.output_dir
    os.makedirs(out_dir, exist_ok=True)

    run_url = f"{base}/run/{args.ref_id}"
    print(f"Fetching run {args.ref_id} ...")
    run_data = json.loads(api_request(
        run_url, args.api_token,
        data=json.dumps({"pageSize": args.page_size}).encode(),
        timeout=120))

    save_json(os.path.join(out_dir, "run.json"), run_data)

    instances = run_data.get("instances", [])
    failures = [
        i for i in instances
        if not i.get("isSuccess")
        and not i.get("isUnsupported")
        and not i.get("isSkipped")
        and i.get("finishedAt")
    ]

    print(f"Found {len(failures)} failed instance(s) out of {len(instances)} total.")
    if not failures:
        return

    bundle_re = re.compile(
        r"https?://[^\s\"]+?\.s3\.amazonaws\.com/[^\s\"]+?bundle\.tgz\.age")

    for inst in failures:
        iid = inst["id"]
        inst_dir = os.path.join(out_dir, iid)
        os.makedirs(inst_dir, exist_ok=True)
        save_json(os.path.join(inst_dir, "instance.json"), inst)

        os_info = f"{inst.get('osName', '?')} {inst.get('osVersion', '?')}"
        print(f"\n{iid} ({os_info}, reason: {inst.get('failureReason', 'unknown')})")

        # Main instance output (usually only populated on VMI startup failures).
        try:
            txt = api_request(f"{base}/instance/{iid}/logs", args.api_token, timeout=60)
            logs = json.loads(txt).get("logs", "")
            if logs:
                with open(os.path.join(inst_dir, "logs.txt"), "w") as f:
                    f.write(logs)
                print("  saved instance logs")
        except (HTTPError, URLError) as e:
            if not isinstance(e, HTTPError) or e.code != 404:
                print(f"  warning: could not fetch instance logs: {e}", file=sys.stderr)

        # Sonobuoy results, if present.
        try:
            txt = api_request(f"{base}/instance/{iid}/sonobuoy", args.api_token, timeout=60)
            results = json.loads(txt).get("results", "")
            if results:
                with open(os.path.join(inst_dir, "sonobuoy.txt"), "w") as f:
                    f.write(results)
                print("  saved sonobuoy results")
        except (HTTPError, URLError) as e:
            if not isinstance(e, HTTPError) or e.code != 404:
                print(f"  warning: could not fetch sonobuoy results: {e}", file=sys.stderr)

        # Per-node logs and support bundles.
        num_primary = inst.get("numPrimaryNodes", 1)
        num_secondary = inst.get("numSecondaryNodes", 0)
        for node_id in node_ids(iid, num_primary, num_secondary):
            try:
                txt = api_request(f"{base}/instance/{node_id}/node-logs", args.api_token, timeout=60)
                logs = json.loads(txt).get("logs", "")
                if not logs:
                    continue

                log_path = os.path.join(inst_dir, f"{node_id}.log.txt")
                with open(log_path, "w") as f:
                    f.write(logs)
                print(f"  saved {node_id} node logs")

                urls = sorted(set(bundle_re.findall(logs)))
                for j, url in enumerate(urls):
                    enc_path = os.path.join(inst_dir, f"bundle-{node_id}-{j}.tgz.age")
                    try:
                        download(url, enc_path)
                        print(f"  downloaded support bundle -> {enc_path}")
                    except Exception as e:
                        print(f"  failed to download bundle {url}: {e}", file=sys.stderr)
                        continue

                    if args.age_passphrase:
                        dec_path = os.path.join(inst_dir, f"bundle-{node_id}-{j}.tgz")
                        try:
                            with open(dec_path, "wb") as dec_file:
                                subprocess.run(
                                    [args.age_bin, "-d", "-p", enc_path],
                                    input=args.age_passphrase.encode(),
                                    stdout=dec_file,
                                    check=True,
                                    stderr=subprocess.PIPE,
                                )
                            print(f"  decrypted support bundle -> {dec_path}")
                        except Exception as e:
                            print(f"  failed to decrypt {enc_path}: {e}", file=sys.stderr)

            except (HTTPError, URLError) as e:
                if not isinstance(e, HTTPError) or e.code != 404:
                    print(f"  warning: could not fetch {node_id} node logs: {e}", file=sys.stderr)

    print(f"\nArtifacts written to: {out_dir}")


if __name__ == "__main__":
    main()

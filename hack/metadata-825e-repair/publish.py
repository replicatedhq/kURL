"""Four conditional metadata PUTs, guarded by VERSION and active workflow checks."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import urllib.request
import uuid

VERSION = 'v2026.09.20-0-825e448f5'
SOURCE = '825e448f54ffbfa1c2084417fbda6277c7b7ffa9'
REPO = 'replicatedhq/kURL'
STAGING_RUN = 36661877760
STAGING_SHA = 'e684c6b7ff86aacfc0565332dcfe02f871241605'
ISOLATED_RUNS = {36663980206, 36663794786}
OWN_RUN = int(os.environ['GITHUB_RUN_ID'])
AUDIT = Path(os.environ['RUNNER_TEMP']) / 'metadata-825e-backup'
AUDIT.mkdir(exist_ok=True)

def gh(path):
    request = urllib.request.Request('https://api.github.com/repos/' + REPO + '/' + path,
        headers={'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'Accept': 'application/vnd.github+json'})
    return json.load(urllib.request.urlopen(request, timeout=45))

def pages(path, field):
    result = []
    for page in range(1, 100):
        separator = '&' if '?' in path else '?'
        batch = gh(path + separator + 'per_page=100&page=' + str(page))[field]
        result.extend(batch)
        if len(batch) < 100:
            return result
    raise RuntimeError('Unexpected pagination size')

def public(key):
    url = 'https://kurl-sh.s3.amazonaws.com/' + key + '?repair_guard=' + uuid.uuid4().hex
    return urllib.request.urlopen(url, timeout=45).read()

def aws(*args):
    response = subprocess.run(['aws', 's3api', *args], check=True, capture_output=True, text=True)
    return json.loads(response.stdout or '{}')

def guard():
    assert public('staging/VERSION').decode().strip() == VERSION, 'Published VERSION changed; abort'
    active = {}
    for status in ['queued', 'in_progress', 'waiting', 'requested', 'pending']:
        for run in pages('actions/runs?status=' + status, 'workflow_runs'):
            active[run['id']] = run
    for run_id, run in active.items():
        if run_id == OWN_RUN or run_id in ISOLATED_RUNS:
            continue  # Parent reviewed these exact two isolated Rook run IDs.
        if run_id != STAGING_RUN:
            raise RuntimeError('Unreviewed active workflow: ' + str(run_id) + ' ' + run['name'])
        assert run['head_sha'] == STAGING_SHA and run['run_attempt'] == 2, 'Staging run changed'
        jobs = pages('actions/runs/' + str(run_id) + '/jobs?filter=latest', 'jobs')
        registry = gh('actions/jobs/109720475009')
        assert registry['run_attempt'] == 2 and registry['conclusion'] == 'failure'
        assert registry['run_id'] == run_id and registry['status'] == 'completed'
        metadata = [job for job in jobs if job['name'] == 'build-addons']
        assert len(metadata) == 1 and metadata[0]['status'] == 'completed', 'Metadata publisher active'
        assert not any(job['name'] == 'set-current-version' and job['status'] != 'completed' for job in jobs), 'VERSION publisher queued/active'
    assert public('staging/VERSION').decode().strip() == VERSION, 'Published VERSION changed; abort'

assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip() == SOURCE
# Refuse to run with an old CLI that silently cannot express conditional writes.
assert 'IfMatch' in aws('put-object', '--generate-cli-skeleton', 'input')
guard()
objects = []
for name in ['addons-gen.json', 'supported-versions-gen.json']:
    for prefix in ['staging/' + VERSION, 'staging']:
        key = prefix + '/' + name
        previous = AUDIT / key.replace('/', '__')
        previous_meta = aws('get-object', '--bucket', 'kurl-sh', '--key', key, str(previous))
        objects.append((name, key, previous_meta['ETag']))
        (previous.with_suffix('.headers.json')).write_text(json.dumps(previous_meta, indent=2))
for name, key, etag in objects:
    guard()  # Immediately before each write; no rebuild or VERSION mutation.
    aws('put-object', '--bucket', 'kurl-sh', '--key', key, '--body', name, '--if-match', etag)
    body = Path(name).read_bytes()
    assert public(key) == body, 'Metadata readback mismatch: ' + key
    print('Restored', key, 'sha256=' + hashlib.sha256(body).hexdigest())
guard()
print('Four exact-source metadata objects restored; published VERSION unchanged.')

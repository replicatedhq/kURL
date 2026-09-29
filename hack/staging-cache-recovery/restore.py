#!/usr/bin/env python3
"""Verify and optionally restore only the audited, unchanged staging cache artifacts."""
import argparse
import concurrent.futures
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent
SOURCE_SHA = '9489f6dc8e13c11e1f59eb28029dac44d749bd96'
TARGET_SHA = 'd86198696006f29714c0eb1bfec0481ba6ec60c2'
PREFIX = 'staging/v2026.09.20-0-9489f6dc8/'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--apply', action='store_true', help='perform verified cache copies; default only verifies and prints plan')
parser.add_argument('--repo', default=str(ROOT.parents[1]))
args = parser.parse_args()
rows = [r for r in json.loads((ROOT / 'staging-cache-audit.json').read_text()) if r['destination_status'] != 200]

def public_head(url):
    r = subprocess.run(['curl', '-fsSI', url], text=True, capture_output=True)
    lines = r.stdout.splitlines()
    codes = [int(s.split()[1]) for s in lines if s.startswith('HTTP/')]
    if not codes:
        raise RuntimeError(f'No HTTP status for {url}: {r.stderr}')
    headers = {s.split(':', 1)[0].lower(): s.split(':', 1)[1].strip() for s in lines if ':' in s}
    return codes[-1], headers

def verify(row):
    package = row['package']
    if not package.startswith(('kotsadm-', 'minio-')) or '/' in package:
        raise RuntimeError(f'Unexpected package: {package}')
    if row['source_gitsha'] != SOURCE_SHA or row['current_main_sha'] != TARGET_SHA or not row['unchanged_source']:
        raise RuntimeError(f'Audit metadata mismatch: {package}')
    subprocess.run(['git', '-C', args.repo, 'diff', '--quiet', SOURCE_SHA, TARGET_SHA, '--', row['source_path']], check=True)
    code, h = public_head(row['source'])
    if code != 200 or h.get('x-amz-meta-gitsha') != SOURCE_SHA or h.get('x-amz-meta-md5') != row['source_md5'] or h.get('content-length') != row['source_size']:
        raise RuntimeError(f'Published source changed: {package}')
    dest_code, _ = public_head(row['destination'])
    if dest_code == 200:
        return row, True
    if dest_code != 403:
        raise RuntimeError(f'Unexpected destination HTTP status {dest_code}: {package}')
    # Public S3 403 is not sufficient authorization to replace an object.
    # Apply mode must additionally obtain an authenticated HeadObject 404.
    return row, False

with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
    verified = list(pool.map(verify, rows))
plans = [row for row, exists in verified if not exists]
skipped = len(rows) - len(plans)
print(f'Verified {len(rows)} unchanged source artifacts against {TARGET_SHA}.')
print(f'Skip {skipped} existing destination objects. Plan {len(plans)} staging-root copies, {sum(int(r["source_size"]) for r in plans)} bytes.')
print('Only kotsadm/minio staging-root package caches are targeted; no VERSION, supported-version registry, production key, or Git tag is changed. Source metadata is preserved.')
if not args.apply:
    print('DRY RUN: no AWS mutation invoked. Apply requires authenticated HeadObject 404 for each destination immediately before copy.')
    for row in plans:
        print(f'PLAN {row["source"]} -> {row["destination"]}')
    sys.exit(0)

def aws_head(key, allow_missing=False):
    p = subprocess.run(['aws', 's3api', 'head-object', '--bucket', 'kurl-sh', '--key', key, '--output', 'json'], text=True, capture_output=True)
    if p.returncode == 0:
        return json.loads(p.stdout)
    if allow_missing and ('(404)' in p.stderr or '(NotFound)' in p.stderr):
        return None
    raise RuntimeError(f'HeadObject failed for {key}: {p.stderr}')

copied = 0
for row in plans:
    package = row['package']
    destination_key = 'staging/' + package
    if aws_head(destination_key, allow_missing=True) is not None:
        print(f'SKIP existing s3://kurl-sh/{destination_key}')
        continue
    source_key = PREFIX + package
    source = aws_head(source_key)
    metadata = source.get('Metadata', {})
    if metadata.get('gitsha') != SOURCE_SHA or metadata.get('md5') != row['source_md5'] or source.get('ContentLength') != int(row['source_size']):
        raise RuntimeError(f'Authenticated source verification failed: {package}')
    subprocess.run(['aws', 's3api', 'copy-object', '--bucket', 'kurl-sh', '--key', destination_key,
                    '--copy-source', 'kurl-sh/' + source_key, '--copy-source-if-match', source['ETag'],
                    '--metadata-directive', 'COPY', '--output', 'json'], check=True, stdout=subprocess.DEVNULL)
    restored = aws_head(destination_key)
    if restored.get('Metadata') != metadata or restored.get('ContentLength') != source['ContentLength']:
        raise RuntimeError(f'Restored metadata/size mismatch: {package}')
    copied += 1
    print(f'COPIED s3://kurl-sh/{destination_key}')
print(f'Restored {copied} cache objects; existing destinations were skipped.')

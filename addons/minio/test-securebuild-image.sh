#!/usr/bin/env bash
# Qualify an immutable SecureBuild image before changing the add-on templates.
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 IMAGE@sha256:DIGEST RELEASE.YYYY-MM-DDTHH-MM-SSZ" >&2
    exit 2
fi
image=$1
release=$2
if [[ ! "$image" =~ @sha256:[a-f0-9]{64}$ ]] || [[ ! "$release" =~ ^RELEASE\.[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}Z$ ]]; then
    echo "An immutable image digest and an upstream MinIO release tag are required" >&2
    exit 2
fi

container=
volume=
cleanup() {
    if [ -n "$container" ]; then docker rm -f "$container" >/dev/null 2>&1 || true; fi
    if [ -n "$volume" ]; then docker volume rm "$volume" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

docker pull --platform linux/amd64 "$image"
version=$(docker run --rm --platform linux/amd64 "$image" --version)
printf '%s\n' "$version"
if [[ "$version" != *"minio version $release "* ]]; then
    echo "Image does not report the requested MinIO release" >&2
    exit 1
fi

volume=$(docker volume create)
# Match the add-on: default entrypoint, --quiet before server, legacy secret names.
# No host ports are exposed. Credentials and the volume are disposable test data.
container=$(docker run -d --platform linux/amd64 \
    -v "$volume:/data" \
    -e MINIO_UPDATE=off \
    -e MINIO_ACCESS_KEY=kurl-test \
    -e MINIO_SECRET_KEY=kurl-test-password \
    "$image" --quiet server /data)

wait_ready() {
    local attempt
    for attempt in $(seq 1 60); do
        if docker exec "$container" sh -c \
            'wget -q -O /dev/null http://127.0.0.1:9000/minio/health/ready && wget -q -O /dev/null http://127.0.0.1:9000/minio/health/live'; then
            return
        fi
        if [ "$(docker inspect -f '{{.State.Running}}' "$container")" != true ]; then break; fi
        sleep 1
    done
    docker logs "$container" >&2
    echo "MinIO did not become healthy" >&2
    return 1
}

configure_client() {
    docker exec "$container" mc alias set local http://127.0.0.1:9000 kurl-test kurl-test-password
}

wait_ready
configure_client
docker exec "$container" mc mb local/kurl-test
printf 'kurl securebuild persistence test\n' | docker exec -i "$container" mc pipe local/kurl-test/object
actual=$(docker exec "$container" mc cat local/kurl-test/object)
test "$actual" = 'kurl securebuild persistence test'
# The installer inspects this file to identify the storage format.
docker exec "$container" cat /data/.minio.sys/format.json
docker stop --time 30 "$container" >/dev/null
test "$(docker inspect -f '{{.State.ExitCode}}' "$container")" = 0
docker start "$container" >/dev/null
wait_ready
configure_client
actual=$(docker exec "$container" mc cat local/kurl-test/object)
test "$actual" = 'kurl securebuild persistence test'
echo "PASS: version, kURL startup, health probes, S3 read/write, format inspection, graceful stop, and persistence"

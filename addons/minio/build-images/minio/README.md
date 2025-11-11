# MinIO Custom Build

Builds MinIO from source using official GitHub releases.

## Why Custom Build?
MinIO stopped publishing pre-built images to Docker Hub. This builds from source.

## Architecture
AMD64 only (matches kURL deployment targets).

## Build Process
Fully automated via GitHub Actions workflow:
- `.github/workflows/build-minio-image.yaml`

### Manual Trigger
1. Go to: https://github.com/replicatedhq/kURL/actions/workflows/build-minio-image.yaml
2. Click "Run workflow"
3. Optional: Specify MinIO version or leave empty for latest
4. Click "Run workflow"

### Automated Weekly Build
Runs every Monday at 00:00 UTC (1 hour before add-on update workflow).

## Image Tags
- `kurlsh/minio:RELEASE.VERSION` (version tag)
- `kurlsh/minio:latest` (latest build)
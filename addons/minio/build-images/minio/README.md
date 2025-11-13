# MinIO Custom Build

Builds MinIO from source using official GitHub releases.

## Why Custom Build?
MinIO stopped publishing pre-built images to Docker Hub. This builds from source.

## Architecture
AMD64 only (matches kURL deployment targets).

## License

**MinIO is licensed under GNU Affero General Public License v3.0 (AGPL-3.0)**

### Source Code
- **MinIO Source**: https://github.com/minio/minio
- **Build Dockerfile**: https://github.com/replicatedhq/kURL/tree/main/addons/minio/build-images/minio
- **Build Workflow**: https://github.com/replicatedhq/kURL/blob/main/.github/workflows/build-minio-image.yaml

### Your Rights Under AGPL v3
The AGPL v3 license grants you the following freedoms:
- **Freedom to Use**: Run the software for any purpose
- **Freedom to Study**: Access and study the source code
- **Freedom to Modify**: Modify the software to suit your needs
- **Freedom to Distribute**: Share copies and modifications with others

### License Requirements
If you modify and distribute MinIO or provide it as a network service:
- You must make your modified source code available under AGPL v3
- You must provide prominent notice of modifications
- You must preserve all copyright and license notices

### Full License
- **AGPL v3 License Text**: https://www.gnu.org/licenses/agpl-3.0.en.html
- **MinIO License File**: https://github.com/minio/minio/blob/master/LICENSE

### Corresponding Source
Per AGPL v3 Section 13, the complete source code for this build is available:
- MinIO source code is available at the links above
- Build instructions are in this directory
- All build automation is in the GitHub Actions workflow

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
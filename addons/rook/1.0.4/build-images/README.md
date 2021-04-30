
1. Test changes to Dockerfile locally with `make build scan`
1. Commit and push changes
1. Go to https://github.com/replicatedhq/kURL/actions/workflows/build-image.yaml
1. Select your branch with updated Dockerfile
1. Enter addons/rook/1.0.4/build-images/ceph and click Run Workflow
1. Enter addons/rook/1.0.4/build-images/rook-ceph and click Run Workflow
1. Update Manifest, cluster/patches/tmpl-ceph-cluster-image.yaml, and operator/ceph-operator.yaml with new images

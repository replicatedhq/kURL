
1. Test changes to Dockerfile locally with `make build scan`
1. Commit and push changes
1. Go to https://github.com/replicatedhq/kURL/actions/workflows/build-image.yaml
1. Select your branch with updated Dockerfile
1. Enter addons/weave/2.6.5/build-images/weave-kube and click Run Workflow
1. Enter addons/weave/2.6.5/build-images/weave-npc and click Run Workflow
1. Update Manifest and daemonset.yaml with new images

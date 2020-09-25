# Add a new version of Kubernetes

1. Download the kubeadm binary for the target version of K8s:
```
curl -LO https://dl.k8s.io/release/v1.19.2/bin/linux/amd64/kubeadm
chmod +x kubeadm
```
1. Run `kubeadm config images list`
1. Create a new directory with the required images in the Manifest
1. Run `make dist/kubernetes-1.19.2.tar.gz` to verify it builds.
1. Add the new version to web/src/installers/index.ts

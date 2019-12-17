![kurl-logo](https://kurl.sh/kurl_logo@2x.png)

Kurl.sh
====================================

Kurl is a Kubernetes installer for airgapped and online clusters.

Kurl relies on `kubeadm` to bring up the Kubernetes control plane, but there are a variety of tasks a system administrator must perform both before and after running kubeadm init in order to have a production-ready Kubernetes cluster, such as installing Docker, configuring Pod networking, or installing kubeadm itself.
The purpose of this installer is to automate those tasks so that any user can deploy a Kubernetes cluster with a single script.

For more information please see [kurl.sh/docs](https://kurl.sh/docs)

Airgapped Kubernetes Appliance (AKA)
====================================

AKA is a Kubernetes installer for airgapped and online clusters.

AKA relies on `kubeadm` to bring up the Kubernetes control plane, but there are a variety of tasks a system administrator must perform both before and after running kubeadm init in order to have a production-ready Kubernetes cluster, such as installing Docker, configuring Pod networking, or installing kubeadm itself.
The purpose of this AKA installer is to automate those tasks so that any user can deploy a Kubernetes cluster with a single script.

## Online Usage

To run the latest stable version of the AKA install script:
```
curl -O https://aka.replicated.com/init.sh | sudo bash
```

Beta:
```
curl -O https://aka.replicated.com/beta/init.sh | sudo bash
```

Unstable:
```
curl -O https://aka.replicated.com/unstable/init.sh | sudo bash
```

## Airgapped Usage

To use AKA in an airgapped environment, first fetch the desired channel installer archive from one of these URLs:

* `curl -O https://s3.amazonaws.com/replicated-aka/aka-stable.tar.gz`
* `curl -O https://s3.amazonaws.com/replicated-aka/aka-beta.tar.gz`
* `curl -O https://s3.amazonaws.com/replicated-aka/aka-unstable.tar.gz`

After copying the archive to your host, untar it and run the install script:

```
tar xvf aka-stable.tar.gz
cat install.sh | sudo bash
```

## Supported Operating Systems

* Ubuntu 16.04
* Ubuntu 18.04 (Recommended)
* CentOS 7.4, 7.5, 7.6
* RHEL 7.4, 7.5, 7.6


## Options

All the AKA install scripts are idempotent. Re-run the scripts with different flags to change the behavior of the installer.

| Flag                             | Usage                                                                                              |
| -------------------------------- | -------------------------------------------------------------------------------------------------- |
| airgap                           | Do not attempt outbound Internet connections while installing                                      |
| bypass-storagedriver-warnings    | Bypass all Docker storagedriver warnings                                                           |
| bootstrap-token                  | Authentication token used by kubernetes when adding additional nodes                               |
| bootstrap-token-ttl              | TTL of the `bootstrap-token`                                                                       |
| disable-contour                  | If present, disables the deployment of the Contour ingress controller                              |
| disable-rook                     | Do not deploy the Rook add-on                                                                      |
| encrypt-network                  | Disable network encryption with `encrypt-network=0`                                                |
| ha                               | Install in multi-master mode                                                                       |
| hard-fail-on-loopback            | If present, aborts the installation if devicemapper on loopback mode is detected                   |
| http-proxy                       | If present, then use proxy                                                                         |
| ip-alloc-range                   | Customize the range of IPs assigned to pods                                                        |
| load-balancer-address            | IP:port of a load balancer for the K8s API servers in ha mode                                      |
| service-cidr                     | Customize the range of virtual IPs assigned to services                                            |
| no-docker                        | Skip docker installation                                                                           |
| no-proxy                         | If present, do not use a proxy                                                                     |
| public-address                   | The public IP address                                                                              |
| private-address                  | The private IP address                                                                             |
| no-ce-on-ee                      | Disable installation of Docker CE onto platforms it does not support - RHEL, SLES and Oracle Linux |
| reset                            | Uninstall Kubernetes                                                                               |
| storage-class                    | The name of an alternative StorageClass that will provision storage for PVCs                       |

## Joining Nodes

The install.sh script will print the command that can be run on worker nodes to join them to your new cluster.
This command will be valid for 24 hours.
To get a new command to join worker nodes, re-run the install.sh script on the master node.

For HA clusters, the install.sh script will print out separate commands for joining workers and joining masters.

## What It Does

### Kubeadm Pre-Init

AKA will perform the following steps on the host prior to delegating to `kubeadm init`.

* Check OS compatibility
* Check Docker compatiblity if pre-installed
* Disable swap
* Check SELinux
* Install Docker
* Install Kubeadm, Kubelet, and Kubectl packages
* Install CNI plugin binaries
* Generate Kubeadm config files from flags passed to the script
* Load kernel modules required for running Kube-proxy in IPVS mode
* Configure Docker and Kubeadm to work behind a proxy if detected

### Add-Ons

After `kubeadm init` has brought up the Kubernetes control plane, AKA will install these components into the cluster:

* [Weave](https://www.weave.works/oss/net/)
* [Rook](https://rook.io/)
* [Contour](https://projectcontour.io/)


## How It Works

The `bundles` directory contains scripts to download and package all required assets, including host commands and Docker images.
There are two bundle directories for each supported OS: docker and k8s.
The docker bundle runs an image for the target OS and uses its package manager to download the docker .dep or .rpm files and all dependencies.
The k8s bundle does the same for kubelet, kubectl, kubeadm, and kubernetes-cni packages.
There is also a bundle of Docker images required to run in the Kubernetes cluster that is not host-specific.

The `yaml` directory holds the yaml that will be applied to the cluster or passed to kubeadm as config files.

The `scripts` directory contains the top-level and helper scripts to prepare the host, run kubeadm, and apply the yaml for addons.

The `web` directory holds a Flask/Nginx app for serving the install scripts.

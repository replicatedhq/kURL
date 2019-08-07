Kurl.sh
====================================

Kurl is a Kubernetes installer for airgapped and online clusters.

Kurl relies on `kubeadm` to bring up the Kubernetes control plane, but there are a variety of tasks a system administrator must perform both before and after running kubeadm init in order to have a production-ready Kubernetes cluster, such as installing Docker, configuring Pod networking, or installing kubeadm itself.
The purpose of this installer is to automate those tasks so that any user can deploy a Kubernetes cluster with a single script.

## Online Usage

To run the latest version of the install script:

```
curl https://kurl.sh/latest | sudo bash
```

HA
```
curl https://kurl.sh/latest | sudo bash -s ha
```

## Airgapped Usage

To install Kubernetes in an airgapped environment, first fetch the installer archive:

```
curl -O https://kurl.sh/airgap.tar.gz
```

After copying the archive to your host, untar it and run the install script:

```
tar xvf airgap.tar.gz
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
| ceph-pool-replicas               | Replication factor of ceph pools. Default is based on number of ready nodes if unset.              |
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

The install script will print the command that can be run on worker nodes to join them to your new cluster.
This command will be valid for 2 hours.
To get a new command to join worker nodes, re-run the install script on the master node.

For HA clusters, the install script will print out separate commands for joining workers and joining masters.

## What It Does

### Kubeadm Pre-Init

Kurl will perform the following steps on the host prior to delegating to `kubeadm init`.

* Check OS compatibility
* Check Docker compatiblity if pre-installed
* Disable swap
* Check SELinux
* Install Docker
* Install Kubeadm, Kubelet, Kubectl and CNI packages
* Generate Kubeadm config files from flags passed to the script
* Load kernel modules required for running Kube-proxy in IPVS mode
* Configure Docker and Kubernetes to work behind a proxy if detected

### Add-Ons

After `kubeadm init` has brought up the Kubernetes control plane, AKA will install these components into the cluster:

* [Weave](https://www.weave.works/oss/net/)
* [Rook](https://rook.io/)
* [Contour](https://projectcontour.io/)

Kustomize is used to deploy addons to the cluster. After running the install script there will be a kustomize/<addon> directory for each addon that was installed.

## How It Works

The `bundles` directory contains scripts to download and package all required assets, including host commands and Docker images.
There are two bundle directories for each supported OS: docker and k8s.
The docker bundle runs an image for the target OS and uses its package manager to download the docker .dep or .rpm files and all dependencies.
The k8s bundle does the same for kubelet, kubectl, kubeadm, and kubernetes-cni packages.
There is also a bundle of Docker images required to run in the Kubernetes cluster that is not host-specific.

The `scripts` directory contains the top-level and helper scripts to prepare the host, run kubeadm, and install addons.

The `addons` directory holds all available versions of all addons. The directory structure is addons/<name>/<version> and must have an install.sh script.
The install.sh script will be sourced dynamically and must provide a function <name> that will be called to install the addon.
For example, the file `addons/weave/2.5.2/install.sh` contains a function named `weave` that will prepare and apply the yaml for weave 2.5.2.

For airgapped installs the addons directory will hold all addon versions configured for the channel.
For dev environments with rsync (see Contributing) the addons directory will have all addons with all versions.
For online installs the version of the addon configured for the channel will be downloaded at runtime and extracted to the addons directory.

The `web` directory holds an Express app for serving the install scripts.

## Contributing

To hack on the installer for Ubuntu 18.04, you'd spin up an instance then run:

```
HOST=<ip or hostname> USER=<me> make watchrsync
```

That will place the installer in your HOME's kurl directory and sync any changes you make locally to the scripts/ or yaml/ directories.
If you rebuild the OS packages, you'll need to manually run `rsync -r build/ ${USER}@${HOST}:kurl` to push those changes.
The `make watchrsync` command requires Node with the `gaze-run-interrupt` package available globally.

On the remote instance run `cd ~/kurl && sudo bash scripts/install.sh` to test your changes.

### Airgap Builds

Run `make dist/airgap.tar.gz` to create an airgap bundle with packages for all supported operating systems.

Copy the bundle to the airgapped instance, untar and run `cd ~/scripts && sudo bash install.sh`.

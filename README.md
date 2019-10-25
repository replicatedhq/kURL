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
curl -LO https://kurl.sh/bundle/latest.tar.gz
```

After copying the archive to your host, untar it and run the install script:

```
tar xvf latest.tar.gz
cat install.sh | sudo bash
```

## Supported Operating Systems

* Ubuntu 16.04
* Ubuntu 18.04 (Recommended)
* CentOS 7.4, 7.5, 7.6
* RHEL 7.4, 7.5, 7.6

## Minimum System Requirements

* 2 CPUs or more
* 4 GB or more of RAM per machine
* TCP ports 6443 and 6783 open
* UDP ports 6783 and 6784 open

## Options

The install scripts are idempotent. Re-run the scripts with different flags to change the behavior of the installer.

| Flag                             | Usage                                                                                              |
| -------------------------------- | -------------------------------------------------------------------------------------------------- |
| airgap                           | Do not attempt outbound Internet connections while installing                                      |
| bypass-storagedriver-warnings    | Bypass all Docker storagedriver warnings                                                           |
| bootstrap-token                  | Authentication token used by kubernetes when adding additional nodes                               |
| bootstrap-token-ttl              | TTL of the `bootstrap-token`                                                                       |
| ceph-pool-replicas               | Replication factor of ceph pools. Default is based on number of ready nodes if unset.              |
| disable-contour                  | If present, disables the deployment of the Contour ingress controller                              |
| disable-prometheus               | If present, disables the deployment of Prometheus monitoring components                            |
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

## Connecting Remotely

You can generate a kubeconfig to use from your local machine with:

```
sudo bash install.sh task=generate-admin-user
```

This will use the load balancer or public address for the Kubernetes API server and generate a new user with full admin privileges.
Be sure to open TCP port 6443 to allow traffic from your local machine.

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

After `kubeadm init` has brought up the Kubernetes control plane, Kurl will install addons into the cluster.
The available addons are:

* [Weave](https://www.weave.works/oss/net/)
* [Rook](https://rook.io/)
* [Contour](https://projectcontour.io/)
* [Docker Registry](https://docs.docker.com/registry/)
* [Prometheus](https://prometheus.io/)

## How It Works

The `bundles` directory holds Dockerfiles used to download the Kubernetes and Docker host packages required for each supported OS.
Make tasks use these Dockerfiles to run an image for the target OS and download .dep or .rpm files and all required dependencies.

The `scripts` directory contains the top-level `install.sh` and `join.sh` scripts along with helper scripts.

The `web` directory holds an Express app for serving the install scripts.

## Contributing

1. Spin up an instance for the target OS, e.g. Ubuntu 18.04.
1. Build the Kubernetes host packages for your desired version of Kubernetes. For K8s 1.15.2 on Ubuntu 18.04 you'd use `make build/packages/kubernetes/1.15.2/ubuntu-18.04`. (For packages that have already been released, you can save time by running `curl -L https://kurl.sh/dist/kubernetes-1.15.2.tar.gz | tar xzvf -` on your server.)
1. Airgap only - build the Docker package: `make build/packages/docker/18.09.8/ubuntu-18.04`
1. OPTIONAL - when developing the kurl-util image `export SYNC_KURL_UTIL_IMAGE=1`
1. Run the task to watch for code changes and copy them to your server: `REMOTES=<user>@<hostname>,<user>@<hostname2> make watchrsync`
1. Edit scripts/Manifest to configure Kubernetes and addons.

That will place the installer in your HOME's kurl directory and sync any changes you make locally to the scripts/ directory.
If you rebuild the OS packages, you'll need to manually run `rsync -r build/ ${USER}@${HOST}:kurl` to push those changes.
The `make watchrsync` command requires Node with the `gaze-run-interrupt` package available globally.

On the remote instance run `cd ~/kurl && sudo bash install.sh` to test your changes.

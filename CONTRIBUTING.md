# Contributing

We welcome contributions to kURL. We appreciate your time and help.

## Supportability

kURL leverage on [kubeadin][kubeadmin]. Then, to test the project, you will need access to a `Linux/amd64`.
You can check its [system requirements][kurl-system-requirements] for further info.

## Pre-requirements

- npm _(i.e. for mac os: `brew install npm`)_
- [Golang](https://go.dev/doc/install) >= 1.19+
- Docker 

**If your local environment is a Mac Os then:** ensure that you install `gnu-sed` and `md5sha1sum` to be able to run 
the scripts with `brew install gnu-sed` and `brew install md5sha1sum`. Otherwise, you might face issues to run the scripts locally
if you need.

## Development Workflow

### Testing released versions

*For packages that have already been released, you can save time by running `curl -L https://k8s.kurl.sh/dist/kubernetes-1.25.2.tar.gz | tar -xzv -C kurl -f -` and `curl -L https://k8s.kurl.sh/dist/docker-20.10.17.tar.gz | tar -xzv -C kurl -f -` on the test server.*  <br />

- 📌 _Ensure that you have a_ **kurl** _directory already created (`mkdir kurl`) from wherever you run the aforementioned commands.
  *If using `containerd` building docker packages is not necessary. Instead of build packages run `make dist/containerd-1.6.8.tar.gz && tar xzvf dist/containerd-1.6.8.tar.gz` or to download already built packages `curl -L https://k8s.kurl.sh/dist/containerd-1.6.8.tar.gz | tar -xzv -C kurl -f -`*
- 📌 *For centos/rhel hosts, `openssl` packages are required. Run `make dist/host-openssl.tar.gz && tar xzvf dist/host-openssl.tar.gz` or to download already built packages `curl -L https://k8s.kurl.sh/dist/host-openssl.tar.gz  | tar -xzv -C kurl -f -`*<br />
- 📌 *In general, when testing local changes to an add-on, you'll need to install the host package(s) required for the particular add-on you're testing. E.g. if you want to install longhorn-1.2.4 with your local changes then you'll need to install the [required host packages](https://github.com/replicatedhq/kURL/blob/main/addons/longhorn/1.2.4/Manifest#L1-L4) prior to running the kURL installer.*

### Testing kURL using Remote Server

1. Set up a 'test server' to test kURL:

Testing can be accomplished on systems capable of hosting supported container runtime. Local or remote Virtual Machine(s) or Instance(s) in a Public cloud provider.

- [Using GCP](#using-gcp)
- [Using Virtual Box on Mac](#virtual-box-on-mac-os)
- [Using QEME on Mac](#QEMU-on-MacOS)

**NOTE**: the remote host must have `rsync` binary installed.

1. Build packages for target OS:

Build the Kubernetes host packages for your desired version of Kubernetes. For K8s `1.15.2` on Ubuntu 18.04
you'd use `make build/packages/kubernetes/1.15.2/ubuntu-18.04`._(For packages that have already been released,
you can save time by running `curl -L https://kurl.sh/dist/kubernetes-1.15.2.tar.gz | tar xzvf` - on your server.)_

**NOTE** If your local environment is Apple Silicon M1/M2 ensure that you run before build the packages:

   ```sh
   export GOOS=linux
   export GOARCH=amd64
   export DOCKER_DEFAULT_PLATFORM=linux/amd64
   ```

    ```sh
    # Local workstation
    make build/packages/kubernetes/1.25.3/ubuntu-22.04
    make build/packages/kubernetes/1.25.3/images
    make build/packages/docker/20.10.17/ubuntu-22.04
    ```

**NOTE**: The bundles directory holds [Dockerfiles under bundles/](./bundles) used to download the Kubernetes and Docker host packages
required for each supported OS. Make tasks use these Dockerfiles to run an image for the target OS and
download `.dep` or `.rpm` files and all required dependencies. The makefile target will build the images and add them
under the [build directory](./build).

#### Why do we need to build these packages?

All automated builds done by kURL _(add-on, bundles and binaries)_ are uploaded to s3 (see the [code](./bin/save-manifest-assets.sh)).
Then, when a kURL installation runs the script downloads all which is packaged _(add-on, bundles and binaries)_ (see the [code](./scripts/common/addon.sh)),
to be installed (see the [code](./scripts/common/host-packages.sh)).

If you are running in the development environment you must either build these bundles
or install the pre-built ones from s3 as described in the section [Testing released versions](#testing-released-versions).

1. Rsync local packages to remote test server.

   Before `resync` you must ensure that the go environment variables are configured with
   the values which are supported by the project:

   ```sh
   export REMOTES="USER@TARGET_SERVER_IP" # Add here the ssh credentials to connect to the remote server
   ```

   ```shell
   npm install
   make watchrsync
   # The job continually synchronizes local builds, keep it running
   ```

   **NOTE:** Note that the scripts, images and binaries will be built under the [build directory](./build) and synchronized
   to the server under the directory `$HOME/kurl` in your remote server. The scripts used to the tests will be moved
   to your `$HOME` where they should be executed. For further info see the code at [bin/watchrsync.js](https://github.com/replicatedhq/kURL/blob/799db33f66f91b0680facf7c14e1222798021c57/bin/watchrsync.js#L29-L32).

1. Validate and run installation on test system

    ```bash
    # On test server
    # validate your expected changes in install.sh|upgrade.sh and|or addons packages
    # run installation
    cd $HOME # You should use the scripts from your home to do the tests 
    sudo bash ./install.sh
    ```

   **NOTE:** `install.sh` runs are idempotent, consecutive runs on changed spec will update kURL installation.

### Configuring the options to test your changes

To test `install.sh` script you will need to ensure that you properly defined what is the configuration
that should be used _(such as it is done via the website https://kurl.sh/). Update the spec `INSTALLER_YAML`
into the [scripts/Manifest](./scripts/Manifest) file such as the following example.

```
KURL_URL=
DIST_URL=
FALLBACK_URL=
INSTALLER_ID=
REPLICATED_APP_URL=https://replicated.app
KURL_UTIL_IMAGE=replicated/kurl-util:alpha
KURL_BIN_UTILS_FILE=
INSTALLER_YAML="apiVersion: cluster.kurl.sh/v1beta1
kind: Installer
metadata:
  name: latest
spec:
  kubernetes:
    version: 1.25.3
  weave:
    version: 2.8.1
  contour:
    version: 1.23.0
  prometheus:
    version: 0.46.0
  registry:
    version: 2.8.1
  containerd:
    version: 1.6.9
  ekco:
    version: 0.24.1
  minio:
    version: 2022-10-20T00-55-09Z

  # OpenEBS is the default PV provisioner, and
  # will work for single node clusters, or for
  # applications that handle data replication
  # between nodes themselves (MongoDB, Cassandra,
  # etc). If your requirements are different than
  # this, see
  # https://kurl.sh/docs/create-installer/choosing-a-pv-provisioner
  #
  openebs:
    version: 3.3.0
    isLocalPVEnabled: true
    localPVStorageClassName: default"
 ```

Assuming you followed up the above steps [Testing kURL using Remote Server](#Testing-kURL-using-Remote-Server), you will
have a terminal tab open. Then you will check that after you change the manifests, the `rsync` will automatically
build the scripts accordingly. You must wait for the message `synced` to test out your changes on the server:

![Screenshot 2022-11-06 at 20 06 35](https://user-images.githubusercontent.com/7708031/200198100-19219107-84dd-4631-a0e4-3200ad5feb99.png)

### Cleaning up the remote server

Currently, it is **not** possible to clean up all that is installed by kURL.
The best effort would to be use the task `sudo bash ./tasks.sh reset`.
However, ideally you will need a new instance/VM for each test scenario.

**NOTE** You can run `make clean` to clean up the `build/` directory locally.

### Running local test versions of Object store and kURL API server

```bash
# To be added
```

## Test environments

### Using GCP

**If you are a Replicated team member then:** ensure that you follow up the doc [Getting Started with your own CodeServer][code-server].

#### :Tips: Convenience functions (change the Default name, the first variable):

```bash
### kURL development helpers:
VM_DEFAULT_NAME="user-kurl"
VM_IMAGE_FAMILY="ubuntu-1804-lts"
VM_IMAGE_PROJECT="ubuntu-os-cloud"
VM_INSTANCE_TYPE="n1-standard-8"

# Creates an instance with a disk device attached.
# For additional instances pass a prefix, example: kurl-dev-make user-kurl2
function kurl-dev-make() {
    local VMNAME="${1:-$VM_DEFAULT_NAME}"
    local VMDISK="$VMNAME-disk1"

    echo "Creating instance $VMNAME..."
    gcloud compute instances create $VMNAME --image-project=$VM_IMAGE_PROJECT --image-family=$VM_IMAGE_FAMILY --machine-type=$VM_INSTANCE_TYPE --boot-disk-size=200G

    local ZONE=$(gcloud compute instances describe $VMNAME --format='value(zone)' | awk -F/ '{print $NF}')
    gcloud compute disks create $VMDISK --size=200GB --zone=$ZONE
    gcloud compute instances attach-disk $VMNAME --disk=$VMDISK

    local VM_IP=$(gcloud compute instances describe $VMNAME --format='value(networkInterfaces[0].accessConfigs[0].natIP)')

    cat <<MAKE_INFO

external IP: $VM_IP
to ssh run: gcloud beta compute ssh $VMNAME
MAKE_INFO
}

function kurl-dev-list() {
    local VMNAME="${1:-$VM_DEFAULT_NAME}"
    echo "Found instances:"
    gcloud compute instances list --filter="name:($VMNAME)"
    echo "Found disks:"
    # TODO: find disks that are attached to an instance
    gcloud compute disks list --filter="name ~ .*$VMNAME.*"
}

function kurl-dev-clean() {
    local VMNAME="${1:-$VM_DEFAULT_NAME}"
    gcloud compute instances delete --delete-disks=all $VMNAME
}
```

### Virtual Box on Mac OS (**Intel only**)

#### Preparation

```bash
# Install Virtual Box
brew install --cask virtualbox virtualbox-extension-pack
# NOTE: Follow Mac OS prompts to set necessary permissions 
wget https://download.linuxvmimages.com/VirtualBox/U/18.04/Ubuntu_18.04.3_VB.zip
unzip Ubuntu_18.04.3_VB.zip

VMNAME=kURL-ubuntu-18-LTS
# Import the VM accepting eula licence agreement
vboxmanage import Ubuntu_18.04.3_VirtualBox_Image_LinuxVMImages.com.ova \
    --vsys 0 --eula accept \
    --cpus 2 \
    --memory 8192 \
    --unit 14 --ignore \
    --unit 15 --ignore \
    --unit 17 --ignore \
    --unit 18 --ignore \
    --unit 19 --ignore \
    --vmname $VMNAME
# Setup networking. NOTE: the port used for forwarding, modify as needed
vboxmanage modifyvm $VMNAME --nic1 nat --natpf1 "guestssh,tcp,,2222,,22"
# Mount kURL repo root to the VM. 
# Replace the path to the location of checked out kURL repo, if you are not in it
vboxmanage sharedfolder add $VMNAME --name kurl-dev --automount --auto-mount-point=/home/ubuntu/kurl --hostpath $(pwd)
```

**NOTE** This option does not work with Apple Silicon `M1/M2`. [More info](https://forums.virtualbox.org/viewtopic.php?f=2&t=106702#p521862)

#### Development cycle

```bash
vboxmanage startvm $VMNAME --type=headless
ssh ubuntu@127.0.0.1 -p 2222
# the kurl folder at $HOME for ubuntu user
# Take a snapshot in a shell on the host
# develop/test
# Restore snapshot as needed
vboxmanage controlvm $VMNAME poweroff
```

**Taking snapshots**

Create initial snapshot - `vboxmanage snapshot $VMNAME take initial`.<br>
Restoring a snapshot - `vboxmanage snapshot $VMNAME restore initial`
Snapshot management requires VM t be powered off.

### QEMU on MacOS

You might want try to use [UTM](https://mac.getutm.app/).

## Documentation

The documentation published in https://kurl.sh/docs/introduction/ is built from
the repository [replicatedhq/kurl.sh][kulr-docs].

## FAQ

### The `error sed: 1: "assets/Manifest": command a expects \ followed by text` or `command md5sum not found` has been faced
when I try to run the `install.sh` script.

The reason for that is because of the commands `sed -i` used on the script. Note that kURL
only supports linux environments and then, you are probably trying to run it from a mac os x. You can
workarround by installing `gnu-sed` and `md5sum` with (`brew install gnu-sed`, `brew install md5sum`).
However, to test the project you must have a `linux/amd64` platform to perform its operations.

[kubeadmin]: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/
[kurl-system-requirements]: https://kurl.sh/docs/install-with-kurl/system-requirements#supported-operating-systems
[kurl-docs]: https://github.com/replicatedhq/kurl.sh
[code-server]: https://github.com/replicatedhq/codeserver/blob/main/docs/first-time.md
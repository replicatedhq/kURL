# Contributing

We welcome contributions to kURL. We appreciate your time and help.

## Supportability

kURL leverages [kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/).
To test the project, you will need access to a `Linux/amd64` instance.
You can check [system requirements](https://kurl.sh/docs/install-with-kurl/system-requirements#supported-operating-systems) for further info.

## Pre-requirements

- npm _(i.e. for mac os: `brew install npm`)_
- [Golang](https://go.dev/doc/install) >= 1.19+
- Docker

**If your local environment is OSX:** ensure that you install `gnu-sed` and `md5sha1sum` to be able to run the scripts.
These can be installed with `brew install gnu-sed` + `PATH="$(brew --prefix)/opt/gnu-sed/libexec/gnubin:$PATH"` and `brew install md5sha1sum`.
The apple-supplied `sed` does not support in-place replace, and OSX does not come with `md5sha1sum`.

## Development Workflow

### Testing released versions

*For packages that have already been released, you can save time by running `curl -L https://k8s.kurl.sh/dist/kubernetes-1.25.2.tar.gz | tar -xzv -C kurl -f -` and `curl -L https://k8s.kurl.sh/dist/docker-20.10.17.tar.gz | tar -xzv -C kurl -f -` on the test server.*  <br />

- 📌 _Ensure that you have a_ **kurl** _directory already created (`mkdir kurl`) from wherever you run the aforementioned commands.
- 📌 *For centos/rhel hosts, `openssl` packages are required. Run `make dist/host-openssl.tar.gz && tar xzvf dist/host-openssl.tar.gz` or to download already built packages `curl -L https://k8s.kurl.sh/dist/host-openssl.tar.gz  | tar -xzv -C kurl -f -`*<br />
- 📌 *In general, when testing local changes to an add-on, you'll need to install the host package(s) required for the particular add-on you're testing. E.g. if you want to install longhorn-1.2.4 with your local changes then you'll need to install the [required host packages](https://github.com/replicatedhq/kURL/blob/main/addons/longhorn/1.2.4/Manifest#L1-L4) prior to running the kURL installer.*

### Testing kURL using Remote Server

1. Set up a 'test server' to test kURL
Note that remote host must have `rsync` binary installed.

Testing can be accomplished on systems capable of hosting supported container runtime. Local or remote Virtual Machine(s) or Instance(s) in a Public cloud provider.

- [Using GCP](#using-gcp)
- [Using Virtual Box on Mac](#virtual-box-on-mac-os)
- [Using QEME on Mac](#QEMU-on-MacOS)

1. Build packages for target OS:
   
   In the following example we will use a helper targeting the ubuntu. 
   **Ensure that you follow the steps to test in a remote server running ubuntu 22.04.**

   If your local environment is Apple Silicon M1/M2 ensure that you run the following before building packages:

   ```sh
   export GOOS=linux
   export GOARCH=amd64
   export DOCKER_DEFAULT_PLATFORM=linux/amd64
   ```

   Then, run from your local machine:

    ```bash
    # To build the sample under testdata targeting ubuntu 22.04
    make build/sample/ubuntu-22.04
   ```

1. Rsync local packages to remote test server.

   ```shell
   npm install
   export REMOTES="USER@TARGET_SERVER_IP" # Add here the ssh credentials to connect to the remote server
   make watchrsync
   # The job continually synchronizes local builds, keep it running
   ```

   **NOTE:** Note that the scripts, images and binaries will be built under the [build directory](./build) and synchronized
   to the server under the directory `$HOME/kurl` in your remote server. The install scripts used for testing will be moved
   to your `$HOME` where they should be executed. For further info see the code at [bin/watchrsync.js](https://github.com/replicatedhq/kURL/blob/799db33f66f91b0680facf7c14e1222798021c57/bin/watchrsync.js#L29-L32).

1. Validate and run installation on test system
    ```bash
    # On test server
    # validate your expected changes in install.sh|upgrade.sh and|or addons packages
    # run installation
    sudo ./install.sh
    ```
    *NOTE: `install.sh` runs are idempotent, consecutive runs on changed spec will update kURL installation.*

### Customizing the spec to do test upgrades and installs

  When you run the target `make build/sample`, the config spec under [script/Manifest](scripts/Manifest) will be replaced with the sample spec in [testdata/sample/Manifest](./testdata/sample/Manifest).
  If you would like to test other configurations you must:

  - replace the spec configuration with that which you would like to test in [script/Manifest](scripts/Manifest)
  - run `make clean` to clean the directories used
  - ensure that you call the makefile targets to build the bundle assets, i.e:

     ```bash
       # Here we are building the bundles for k8s 1.25.3 to target ubuntu 22.02 SO
       make build/packages/kubernetes/1.25.3/ubuntu-22.04
       make build/packages/kubernetes/1.25.3/images
     ```

  - build the addons tarball for the specific versions and untar them, i.e:

     ```bash
       # Here we are building the tarball for containerd version 1.6.9
       make dist/containerd-1.6.9.tar.gz && tar xzvf dist/containerd-1.6.9.tar.gz
     ```

  - ensure that all is rsynced with the remote server before running `./install.sh`

### Cleaning up(teardown)

Currently, it is **not** possible to clean up everything that is installed or modified by kURL.
There is a best effort script that can be run with `sudo bash ./tasks.sh reset`, but it is not always perfect.
Ideally you will need a new instance/VM for each test scenario.

Contributions and bug reports for things that the reset script does not currently handle are welcomed.

**NOTE** You can run `make clean` to clean up the `build/` directory locally.

### Running local test versions of Object store and kURL API server

```bash
# To be added
```

## Test environments

Testing can be accomplished on systems capable of hosting supported container runtime. Local or remote Virtual Machine(s) or Instance(s) in a Public cloud provider.

- [Using GCP](#using-gcp)
- [Using Virtual Box on Mac](#virtual-box-on-mac-os)
- [Using QEME on Mac]
- [Using Kind and kubeVirt]

### Using GCP

**If you are a Replicated team member then:** ensure that you have followed [Getting Started with your own CodeServer](https://github.com/replicatedhq/codeserver/blob/main/docs/first-time.md).

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

**NOTE** This option does **not** work with Apple Silicon `M1/M2`.

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

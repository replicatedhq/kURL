# Contributing

We welcome contributions to kURL. We appreciate your time and help. 

# Development workflow

## Testing kURL

1. Set up a 'test server' to test kURL ([some options](#test-environments)).
Note that remote host must have `rsync` binary installed.
1. Build packages for target OS: 
    ```bash
    # Local workstation
    make build/packages/kubernetes/1.19.3/ubuntu-18.04
    make build/packages/kubernetes/1.19.3/images
    make build/packages/docker/19.03.10/ubuntu-18.04
    make build/packages/docker/19.03.10/images
    ```
    
    *For packages that have already been released, you can save time by running `curl -L https://kurl.sh/dist/kubernetes-1.19.7.tar.gz | tar -xzv -C kurl -f -` and `curl -L https://kurl.sh/dist/docker-19.03.10.tar.gz | tar -xzv -C kurl -f -` on the test server.*  <br />
    📌 _Ensure that you have a_ **kurl** _directory already created (`mkdir kurl`) from wherever you run the aforementioned commands._<br /><br />
    *If using `containerd` building docker packages is not necessary. Instead to build packages run `make dist/containerd-1.4.3.tar.gz && tar xzvf dist/containerd-1.4.3.tar.gz` or to download already built packages `curl -L https://k8s.kurl.sh/dist/containerd-1.4.3.tar.gz | tar -xzv -C kurl -f -`*<br /><br />
    📌 *For centos/rhel hosts, `openssl` packages are required. Run `make dist/host-openssl.tar.gz && tar xzvf dist/host-openssl.tar.gz` or to download already built packages `curl -L https://k8s.kurl.sh/dist/host-openssl.tar.gz  | tar -xzv -C kurl -f -`*<br />
    📌 *In general, when testing local changes to an add-on, you'll need to install the host package(s) required for the particular add-on you're testing. E.g. if you want to install longhorn-1.2.4 with your local changes then you'll need to install the [required host packages](https://github.com/replicatedhq/kURL/blob/main/addons/longhorn/1.2.4/Manifest#L1-L4) prior to running the kURL installer.*
1. Rsync local packages to remote test server. To run the build on MacOS, jump to [Building on MacOS](#building-on-macos).
    ```bash
    # Local workstation
    npm install
    export REMOTES="USER@TARGET_SERVER_IP"
    make watchrsync
    # The job continually synchronizes local builds, keep it running
    ```
1. Customize your spec by editing `scripts/Manifest`

    Example:
    ```bash
    KURL_URL=
    DIST_URL=
    INSTALLER_ID=
    REPLICATED_APP_URL=https://replicated.app
    KURL_UTIL_IMAGE=replicated/kurl-util:alpha
    KURL_BIN_UTILS_FILE=
    INSTALLER_YAML="apiVersion: cluster.kurl.sh/v1beta1
    kind: Installer
    metadata:
      name: testing
    spec:
      kubernetes:
        version: 1.19.7
      weave:
        version: 2.7.0
      openebs:
        version: 1.12.0
        isLocalPVEnabled: true
        localPVStorageClassName: default
      containerd:
        version: 1.4.3
      prometheus:
        version: 0.33.0
      registry:
        version: 2.7.1"
    ```
1. Validate and run installation on test system
    ```bash
    # On test server
    # validate your expected changes in install.sh|upgrade.sh and|or addons packages
    # run installation
    sudo ./install.sh
    ```
    *NOTE: `install.sh` runs are idempotent, consecutive runs on changed spec will update kURL installation.*

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

Convenience functions (change the Default name, the first variable):

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

### Virtual Box on Mac OS

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

### Building on MacOs

To run `make watchrsync`, you'll need to perform the following additional steps.

1. `export GOOS=linux`
2. If you have an M1 or other arm Macbook, you'll also need `export GOARCH=amd64`

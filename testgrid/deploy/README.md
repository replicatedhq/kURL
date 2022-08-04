# Tesgrid server installation 

## Terraform

### Provisioning

> NOTE: Project based token doesn't have sufficient privileges for Spot instance create/destroy operations (*creation works with errors; destroy fails*). Personal token can be used to get sufficient privileges:

#### Getting Personal Token
1. In the top right corner of equinix select your name and choose `Personal API Keys`.
2. + Add New Key
3. Under the actions column choose `Copy` which will copy it to your clipboard.

```bash
export AWS_PROFILE=replicated-production
export METAL_AUTH_TOKEN=<packet-auth-token>
terrafrom plan
terraform apply
```

To view logs for `tgrun` - `journalctl -u tgrun`

### Deprovision
```bash
# make sure all the variables from the previous step are still set in your env
terraform destroy
```

*NOTE: After deprovisioning the instance, Equinix will take some time to release the reservations to our account. Until the reservation is released you will not be able to provision reserved instances. Once the reservation has been released you should see 2 instances on [this page](https://console.equinix.com/projects/bf141b98-6b6d-49c8-b7df-c261e383fc74/create-server/reserved).*

### Tested versions
```bash
Terraform v1.0.4
+ provider registry.terraform.io/hashicorp/aws v4.5.0
+ provider registry.terraform.io/packethost/packet v3.1.0
+ provider registry.terraform.io/equinix/metal v3.1.0
```

### Debugging
On the server, you can run `kubectl get vmi` to view running VMs.
You can exec into a VM with `kubectl virt console <vmi name>`, and the password will be `kurl`.
(The username will vary based on OS - for example `ubuntu`, `root`, `ec2-user` and `centos`)

### Manually running VMs on testgrid

1. Login to https://console.equinix.com/
1. Click on any server
1. Click SSH access, copy the command, and SSH into the server
1. Find the upload proxy IP: kubectl -n cdi get service cdi-uploadproxy --no-headers | awk '{ print $3 }'
1. Download the VM image. Pick image from testgrid/specs/os-full.yaml. `curl -LO https://cloud.centos.org/centos/8/x86_64/images/CentOS-8-GenericCloud-8.3.2011-20201204.2.x86_64.qcow2`
1. Create a PVC from the image: `kubectl virt image-upload --uploadproxy-url=https://<upload proxy IP> --insecure --pvc-name=areed-disk --pvc-size=100Gi --image-path=`pwd`/CentOS-8-GenericCloud-8.3.2011-20201204.2.x86_64.qcow2`
1. Create virtualmachineinstance with config and `kubectl apply` it
```
apiVersion: kubevirt.io/v1alpha3
kind: VirtualMachineInstance
metadata:
  name: areed
  labels:
    kubevirt.io/domain: areed
spec:
  terminationGracePeriodSeconds: 0
  domain:
    machine:
      type: ""
    resources:
      requests:
        memory: 16Gi
        cpu: "4"
    devices:
      disks:
      - name: pvcdisk
        disk:
          bus: virtio
      - name: cloudinitdisk
        cdrom:
          bus: sata
      - name: emptydisk1
        serial: empty
        disk:
          bus: virtio
  volumes:
  - name: pvcdisk
    persistentVolumeClaim:
      claimName: areed-disk
  - name: emptydisk1
    emptyDisk:
      capacity: 50Gi
  - name: cloudinitdisk
    cloudInitNoCloud:
      userData: |-
        #cloud-config
        password: kurl
        chpasswd: { expire: False }
```
1. Access the VM with `kubectl console virt <name>`. Then use the default username and password "kurl" to login.

# Tesgrid server installation 

## Terraform

### Provisioning

> NOTE: Project based token doesn't have sufficient privileges for Spot instance create/destroy operations (*creation works with errors; destroy fails*). Personal token can be used to get sufficient privileges:

```bash
export AWS_PROFILE=replicated-production
export PACKET_AUTH_TOKEN=<packet-auth-token>
terrafrom plan
terraform apply
```

To view logs for `tgrun` - `journalctl -u tgrun`

### Deprovision
```bash
# make sure all the variables from the previous step are still set in your env
terraform destroy
```

### Tested versions
```bash
Terraform v0.14.10
+ provider registry.terraform.io/hashicorp/aws v2.52.0
+ provider registry.terraform.io/hashicorp/template v2.2.0
+ provider registry.terraform.io/packethost/packet v3.1.0
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
1. Download the VM image. Pick image from tgrun/pkg/scheduler/static.go. `curl -LO https://cloud.centos.org/centos/8/x86_64/images/CentOS-8-GenericCloud-8.3.2011-20201204.2.x86_64.qcow2`
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

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

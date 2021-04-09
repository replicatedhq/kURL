# Tesgrid server installation 

## Terraform

### Dependencies

Terraform provider [sops](https://github.com/carlpett/terraform-provider-sops/blob/master/docs/legacy_usage.md)

```bash
mkdir -p ~/.terraform.d/plugins
curl -LO https://github.com/carlpett/terraform-provider-sops/releases/download/v0.6.2/terraform-provider-sops_0.6.2_linux_amd64.zip
unzip terraform-provider-sops_0.6.2_linux_amd64.zip -d ~/.terraform.d/plugins
rm terraform-provider-sops_0.6.2_linux_amd64.zip
```

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
Terraform v0.12.29
+ provider.packet v3.0.1
+ provider.template v2.2.0
```

### Debugging
On the server, you can run `kubectl get vmi` to view running VMs.
You can exec into a VM with `kubectl virt console <vmi name>`, and the password will be `kurl`.
(The username will vary based on OS - for example `ubuntu`, `root`, `ec2-user` and `centos`)

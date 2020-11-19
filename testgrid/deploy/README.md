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
Terraform v0.12.29
+ provider.packet v3.0.1
+ provider.template v2.2.0
```

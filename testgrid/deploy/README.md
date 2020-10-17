# Tesgrid server installation 

## Terraform

### Provisioning

> NOTE: Project based token doesn't have sufficient privileges for Spot instance create/destroy operations (*creation works with errors; destroy fails*). Personal token can be used to get sufficient privileges:

```bash
export TF_VAR_auth_token=<token>
terraform apply
```

### Deprovision
```bash
export TF_VAR_auth_token=<token>
terraform destroy
```

### Tested versions
```bash
Terraform v0.12.29
+ provider.packet v3.0.1
+ provider.template v2.2.0
```

## TODO

- Persist TF state (s3 or any other shared store)
- Install binary or docker image for `tgrun` and configure the service accordantly
- Multi node cluster support
- CI/CD
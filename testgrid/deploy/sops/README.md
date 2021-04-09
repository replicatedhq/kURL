# Encrypting secrets

```bash
terraform init
terraform apply
sops -e --kms $(terraform output aws_kms_key_arn) secrets.example.yaml > ../secrets.enc.yaml
```

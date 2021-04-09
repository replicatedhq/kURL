provider "aws" {
  version = "~> 2.52.0"
  region  = "us-east-1"
}

resource "aws_kms_key" "kurl_testgrid_sops_key" {
  description             = "KMS Key for sops"
  deletion_window_in_days = 7
}

output "aws_kms_key_arn" {
  value = aws_kms_key.kurl_testgrid_sops_key.arn
}

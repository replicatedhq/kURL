terraform {
  backend "s3" {
    bucket = "terraform-testgrid"
    key    = "testgrid-prod/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_kms_key" "kurl_testgrid_sops_key" {
  description             = "KMS Key for sops"
  deletion_window_in_days = 7
}

data "sops_file" "secrets" {
  source_file = "secrets.enc.yaml"
}

variable "sensitive_mask" {
  description = "This is a hack to mask data.sops_file.secrets.data"
  type        = string
  sensitive   = true
  default     = "thisissupersecret"
}

resource "packet_spot_market_request" "base-request" {
  project_id    = var.project_id
  max_bid_price = var.max_bid
  facilities    = var.region
  devices_min   = 1
  devices_max   = 1

  instance_parameters {
    hostname         = var.tg_hostname
    billing_cycle    = "hourly"
    operating_system = var.tg_os
    plan             = var.instance_type
    userdata = templatefile("tg-script.sh.tpl", {
      dockerhub_username = data.sops_file.secrets.data["dockerhub_username"]
      dockerhub_password = data.sops_file.secrets.data["dockerhub_password"]
      sensitive_mask     = var.sensitive_mask
    })
  }
}

data "packet_spot_market_request" "dreq" {
  request_id = packet_spot_market_request.base-request.id
}

output "ids" {
  value = data.packet_spot_market_request.dreq.device_ids
}

resource "packet_spot_market_request" "burst-request" {
  project_id    = var.project_id
  max_bid_price = var.max_bid
  facilities    = var.region
  devices_min   = 1
  devices_max   = 4

  instance_parameters {
    hostname         = var.tg_hostname_burst
    billing_cycle    = "hourly"
    operating_system = var.tg_os
    plan             = var.instance_type
    userdata = templatefile("tg-script.sh.tpl", {
      dockerhub_username = data.sops_file.secrets.data["dockerhub_username"]
      dockerhub_password = data.sops_file.secrets.data["dockerhub_password"]
      sensitive_mask     = var.sensitive_mask
    })
  }
}

data "packet_spot_market_request" "sreq" {
  request_id = packet_spot_market_request.burst-request.id
}
output "burst-ids" {
  value = data.packet_spot_market_request.sreq.device_ids
}

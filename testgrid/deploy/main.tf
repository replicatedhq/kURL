# Configure the Packet Provider. 
provider "packet" {
  auth_token = var.auth_token
}

provider "aws" {
  version = "~> 2.52.0"
  region  = "us-east-1"
}

terraform {
  backend "s3" {
    bucket = "terraform-testgrid"
    key    = "testgrid-prod/terraform.tfstate"
    region = "us-east-1"
  }
}

data "template_file" "tg_setup" {
  template = "${file("${path.module}/tg-script.sh")}"

  vars = {
    dh-email = var.dh_email
    dh-user  = var.dh_user
    dh-pass  = var.dh_pass
  }
}

data "template_cloudinit_config" "config" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/x-shellscript"
    content      = data.template_file.tg_setup.rendered
  }
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
    userdata         = data.template_cloudinit_config.config.rendered
  }
}

resource "packet_spot_market_request" "burst-request" {
  project_id    = var.project_id
  max_bid_price = var.max_bid
  facilities    = var.region
  devices_min   = 0
  devices_max   = 0

  instance_parameters {
    hostname         = var.tg_hostname_burst
    billing_cycle    = "hourly"
    operating_system = var.tg_os
    plan             = var.instance_type
    userdata         = data.template_cloudinit_config.config.rendered
  }
}

data "packet_spot_market_request" "dreq" {
  request_id = packet_spot_market_request.base-request.id
}

data "packet_spot_market_request" "sreq" {
  request_id = packet_spot_market_request.burst-request.id
}

output "ids" {
  value = concat(data.packet_spot_market_request.dreq.device_ids, data.packet_spot_market_request.sreq.device_ids)
}

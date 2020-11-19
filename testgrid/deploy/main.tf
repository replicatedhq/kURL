# Configure the Packet Provider. 
provider "packet" {}

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
    userdata         = file("${path.module}/tg-script.sh")
  }
}

data "packet_spot_market_request" "dreq" {
  request_id = packet_spot_market_request.base-request.id
}

output "ids" {
  value = data.packet_spot_market_request.dreq.device_ids
}

//resource "packet_spot_market_request" "burst-request" {
//  project_id    = var.project_id
//  max_bid_price = var.max_bid
//  facilities    = var.region
//  devices_min   = 1
//  devices_max   = 4
//
//  instance_parameters {
//    hostname         = var.tg_hostname_burst
//    billing_cycle    = "hourly"
//    operating_system = var.tg_os
//    plan             = var.instance_type
//    userdata         = data.template_cloudinit_config.config.rendered
//  }
//}
//
//data "packet_spot_market_request" "sreq" {
//  request_id = packet_spot_market_request.burst-request.id
//}
//output "burst-ids" {
//  value = data.packet_spot_market_request.sreq.device_ids
//}

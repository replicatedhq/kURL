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

resource "metal_spot_market_request" "base-request" {
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
    userdata         = file("tg-script.sh")
  }
}

data "metal_spot_market_request" "dreq" {
  request_id = metal_spot_market_request.base-request.id
}

output "ids" {
  value = data.metal_spot_market_request.dreq.device_ids
}

resource "metal_spot_market_request" "burst-request" {
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
    userdata         = file("tg-script.sh")
  }
}

data "metal_spot_market_request" "sreq" {
  request_id = metal_spot_market_request.burst-request.id
}
output "burst-ids" {
  value = data.metal_spot_market_request.sreq.device_ids
}

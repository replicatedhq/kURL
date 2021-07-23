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

resource "metal_device" "device" {
  count = var.device_count

  project_id       = var.project_id
  facilities       = var.region
  hostname         = "${var.tg_hostname}-${count.index}"
  billing_cycle    = "hourly"
  operating_system = var.tg_os
  plan             = var.instance_type
  user_data        = file("tg-script.sh")
}

output "device_ids" {
  value = metal_device.device.*.id
}

resource "metal_spot_market_request" "spot_req" {
  count = var.device_count_spot > 0 ? 1 : 0

  project_id    = var.project_id
  max_bid_price = var.max_bid
  facilities    = var.spot_region
  devices_min   = min(1, var.device_count_spot)
  devices_max   = max(1, var.device_count_spot)

  instance_parameters {
    hostname         = "${var.tg_hostname}-spot"
    billing_cycle    = "hourly"
    operating_system = var.tg_os
    plan             = var.instance_type
    userdata         = file("tg-script.sh")
  }
}

data "metal_spot_market_request" "spot_dreq" {
  count      = var.device_count_spot > 0 ? 1 : 0
  request_id = element(metal_spot_market_request.spot_req, count.index).id
}

output "device_ids_spot" {
  value = flatten(data.metal_spot_market_request.spot_dreq.*.device_ids)
}

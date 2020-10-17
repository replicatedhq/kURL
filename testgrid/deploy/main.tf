# Configure the Packet Provider. 
provider "packet" {
  auth_token = var.auth_token
}

data "template_file" "tg_setup" {
  template = file("./tg-script.sh")
}

resource "packet_spot_market_request" "req" {
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
    userdata         = data.template_file.tg_setup.rendered
  }
}

data "packet_spot_market_request" "dreq" {
  request_id = packet_spot_market_request.req.id
}

output "ids" {
  value = data.packet_spot_market_request.dreq.device_ids
}

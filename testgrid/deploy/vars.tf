variable "instance_type" {
  type        = string
  default     = "m3.large.x86"
  description = "packet instamce type"
}

variable "region" {
  type        = list(string)
  default     = ["any"]
  description = "Packet regions to deploy testgrid"
}

variable "spot_region" {
  type        = list(string)
  default     = ["sv15"]
  description = "Packet regions to deploy testgrid"
}

variable "max_bid" {
  type        = string
  default     = "1.00"
  description = "Maximum bid price for the instance"
}

variable "project_id" {
  type        = string
  default     = "bf141b98-6b6d-49c8-b7df-c261e383fc74"
  description = "Project name, using Testing as default."
}

variable "device_count" {
  type        = number
  default     = 1
  description = "Number of devices to provision"
}

variable "device_count_spot" {
  type        = number
  default     = 4
  description = "Number of devices to provision"
}

variable "tg_hostname" {
  type    = string
  default = "testgrid-instance"
}

variable "tg_os" {
  type    = string
  default = "ubuntu_18_04"
}

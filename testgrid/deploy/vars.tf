variable "instance_type" {
  type        = string
  default     = "m3.large.x86"
  description = "packet instance type"
}

variable "region" {
  type        = list(string)
  default     = ["any"]
  description = "Packet regions to deploy testgrid"
}

variable "project_id" {
  type        = string
  default     = "bf141b98-6b6d-49c8-b7df-c261e383fc74"
  description = "Project name, using Testing as default."
}

variable "device_count" {
  type        = number
  default     = 5
  description = "Number of devices to provision"
}

variable "reservation_ids" {
  type        = list(string)
  default     = ["860b9195-f454-45d5-8dd0-c24bcb2c4c1f", "021b3a89-6036-494b-a471-206dccb9c685"]
  description = "The ids of hardware reservation which the devices occupy"
}

variable "tg_hostname" {
  type    = string
  default = "testgrid-instance"
}

variable "tg_os" {
  type    = string
  default = "ubuntu_18_04"
}

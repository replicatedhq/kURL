variable instance_type {
  type        = string
  default     = "m3.large.x86"
  description = "packet instamce type"
}

variable auth_token {
  type        = string
}

variable region {
  type        = list(string)
  default     = ["sv15"]
  description = "Packet regions to deploy testgrid"
}

variable project_id {
  type        = string
  default     = "bf141b98-6b6d-49c8-b7df-c261e383fc74"
  description = "Project name, using Testing as default."
}

variable max_bid {
  type        = string
  default     = "0.77"
  description = "Maximum bid price for the instance"
}

variable tg_hostname {
    type      = string
    default   = "testgrid-spot"
}

variable tg_os {
  type        = string
  default     = "ubuntu_18_04"
}

variable instance_type {
  type        = string
  default     = "m3.large.x86"
  description = "packet instamce type"
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

variable tg_hostname_burst {
  type      = string
  default   = "testgrid-spot-burst"
}

variable tg_os {
  type        = string
  default     = "ubuntu_18_04"
}

variable dh_email {
  type        = string
  default     = "pavel@replicated.com"
  description = "Primary email for replicatedtestgrid DockerHub account"
}

variable dh_user {
  type        = string
  default     = "replicatedtestgrid"
}

variable dh_pass {
  type        = string
}

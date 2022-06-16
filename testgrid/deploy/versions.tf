terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.5.0"
    }
    metal = {
      source = "equinix/metal"
      version = "3.1.0"
    }
  }
  required_version = ">= 1.0.0"
}

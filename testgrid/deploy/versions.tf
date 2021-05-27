terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 2.52.0"
    }
    metal = {
      source = "equinix/metal"
      version = "2.1.0"
    }
    template = {
      source = "hashicorp/template"
    }
  }
  required_version = ">= 0.13"
}

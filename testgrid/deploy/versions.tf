terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 2.52.0"
    }
    metal = {
      source = "equinix/metal"
      version = "3.1.0"
    }
    template = {
      source = "hashicorp/template"
    }
  }
  required_version = ">= 1.0.0"
}

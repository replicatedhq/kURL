terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 2.52.0"
    }
    packet = {
      source  = "packethost/packet"
      version = "~> 3.1.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 0.6.2"
    }
    template = {
      source = "hashicorp/template"
    }
  }
  required_version = ">= 0.13"
}

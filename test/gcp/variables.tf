variable "region" {
  description = "GCP region for testing"
  default     = "us-central1"
}

variable "project" {
  description = "GCP project for testing"
  default     = "replicated-qa"
}

variable "id" {
	description = "Added to instance names"
	default= "aka"
}

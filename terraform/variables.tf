variable "project_id" {
  description = "GCP project ID to deploy into."
  type        = string
}

variable "region" {
  description = "Primary GCP region."
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Deployment environment: staging or production. Drives naming and per-environment state/backend selection."
  type        = string

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be either \"staging\" or \"production\"."
  }
}

variable "gke_subnet_cidr" {
  type    = string
  default = "10.10.0.0/20"
}

variable "gke_pods_cidr" {
  type    = string
  default = "10.20.0.0/14"
}

variable "gke_services_cidr" {
  type    = string
  default = "10.30.0.0/20"
}

variable "master_authorized_cidrs" {
  description = "Trusted CIDR ranges allowed to reach the GKE API server (VPN/CI runner ranges). Never include 0.0.0.0/0."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
}

variable "app_node_min_count" {
  type    = number
  default = 3
}

variable "app_node_max_count" {
  type    = number
  default = 10
}

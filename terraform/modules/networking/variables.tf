variable "project_id" {
  description = "GCP project ID where networking resources are created."
  type        = string
}

variable "region" {
  description = "Primary region for regional resources (subnet, router, NAT)."
  type        = string
}

variable "environment" {
  description = "Environment name (staging, production) used for naming/tagging."
  type        = string
}

variable "network_name" {
  description = "Name of the custom VPC network."
  type        = string
  default     = "order-service-vpc"
}

# --- GKE node subnet ---------------------------------------------------

variable "gke_subnet_cidr" {
  description = "Primary CIDR range for the GKE node subnet."
  type        = string
  default     = "10.10.0.0/20" # 4096 IPs for nodes
}

variable "gke_pods_cidr" {
  description = "Secondary CIDR range for GKE pod IPs (VPC-native alias IPs)."
  type        = string
  default     = "10.20.0.0/14" # large range, pods scale independently of nodes
}

variable "gke_services_cidr" {
  description = "Secondary CIDR range for GKE service IPs (VPC-native alias IPs)."
  type        = string
  default     = "10.30.0.0/20"
}

# --- Cloud SQL private services range -----------------------------------

variable "cloudsql_private_range_cidr" {
  description = <<-EOT
    CIDR range reserved for Private Services Access (VPC peering) used by
    Cloud SQL private IP. Deliberately a distinct, non-overlapping range from
    the GKE subnet/secondary ranges above, so GKE and Cloud SQL never share
    address space even though they sit in the same VPC.
  EOT
  type        = string
  default     = "10.60.0.0/20"
}

variable "cloudsql_private_range_name" {
  description = "Name of the allocated private services access IP range for Cloud SQL."
  type        = string
  default     = "cloudsql-psa-range"
}

# --- NAT ------------------------------------------------------------------

variable "nat_min_ports_per_vm" {
  description = "Minimum NAT ports allocated per VM, sized for the outbound connection volume of the order-service (billing API calls, image pulls)."
  type        = number
  default     = 128
}

# --- Firewall ---------------------------------------------------------------

variable "allowed_ingress_cidrs" {
  description = "CIDR ranges allowed to reach the GKE control plane / bastion, e.g. office VPN or CI runner egress IPs. Must never include 0.0.0.0/0."
  type        = list(string)
  default     = []
}

variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "region" {
  type        = string
  description = "Region for the regional GKE cluster."
}

variable "environment" {
  type        = string
  description = "Environment name (staging, production)."
}

variable "cluster_name" {
  type    = string
  default = "order-service-cluster"
}

variable "network_self_link" {
  type        = string
  description = "Self link of the VPC network (from the networking module)."
}

variable "subnetwork_self_link" {
  type        = string
  description = "Self link of the GKE node subnet (from the networking module)."
}

variable "pods_range_name" {
  type        = string
  description = "Name of the secondary IP range used for pod alias IPs."
}

variable "services_range_name" {
  type        = string
  description = "Name of the secondary IP range used for service alias IPs."
}

variable "master_ipv4_cidr_block" {
  type        = string
  description = "RFC1918 /28 for the GKE control plane (private endpoint side)."
  default     = "172.16.0.0/28"
}

variable "master_authorized_cidrs" {
  description = <<-EOT
    List of {cidr_block, display_name} objects allowed to reach the GKE
    control plane API. Must be an explicit, trusted list — never
    0.0.0.0/0.
  EOT
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
}

variable "release_channel" {
  type    = string
  default = "REGULAR"
}

# --- Application node pool sizing -----------------------------------------
# Sizing rationale (see ANSWERS.md for the full breakdown):
#  - ~5,000 req/min peak ≈ 84 req/s.
#  - Each pod requests 250m CPU / 256Mi memory (see k8s/deployment.yaml) and
#    comfortably sustains ~40-60 req/s under typical order-processing latency,
#    so steady state needs roughly 2-3 pods of *work*, with HPA scaling
#    05-20 pods based on real CPU/memory load and traffic bursts.
#  - e2-standard-4 (4 vCPU / 16GB) fits ~10-12 such pods per node after
#    reserving capacity for system/kube-system daemonsets, giving comfortable
#    bin-packing headroom and room for the HPA to scale without immediately
#    needing a new node.
#  - min 3 nodes spread across zones for baseline HA + PDB compliance during
#    node upgrades; max 10 nodes gives ~5-10x burst headroom before hitting
#    a hard ceiling.
variable "app_node_machine_type" {
  type    = string
  default = "e2-standard-4"
}

variable "app_node_min_count" {
  type    = number
  default = 3
}

variable "app_node_max_count" {
  type    = number
  default = 10
}

variable "app_node_disk_size_gb" {
  type    = number
  default = 50
}

variable "app_node_disk_type" {
  type    = string
  default = "pd-balanced"
}

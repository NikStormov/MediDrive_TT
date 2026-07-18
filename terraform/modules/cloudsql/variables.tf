variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "environment" {
  type = string
}

variable "instance_name" {
  type    = string
  default = "order-db"
}

variable "database_name" {
  type    = string
  default = "order_service"
}

variable "database_user" {
  type    = string
  default = "order_service_app"
}

variable "network_self_link" {
  type        = string
  description = "VPC self link (from the networking module)."
}

variable "private_vpc_connection" {
  description = "The google_service_networking_connection resource from the networking module; ensures peering exists before the instance is created."
  type        = any
}

# Production-appropriate dedicated-core tier with HA. db-f1-micro (shared
# core, no HA support) is a dev-only tier and is intentionally not the
# default here — see REVIEW.md issue #4 for the buggy-snippet equivalent.
variable "tier" {
  type    = string
  default = "db-custom-4-16384" # 4 vCPU / 16GB, sized for ~5,000 req/min peak with connection-pooling headroom
}

variable "availability_type" {
  type    = string
  default = "REGIONAL" # HA: synchronous standby in a second zone, automatic failover
}

variable "disk_size_gb" {
  type    = number
  default = 100
}

variable "disk_autoresize" {
  type    = bool
  default = true
}

variable "backup_retained_count" {
  type    = number
  default = 30 # days-equivalent of daily backups retained
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "workload_identity_secret_accessor_member" {
  description = "IAM member (serviceAccount:...) of the Workload Identity GSA allowed to read the DB credentials secret."
  type        = string
}

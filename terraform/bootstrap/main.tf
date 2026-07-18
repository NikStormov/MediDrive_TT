# Bootstrap: GCS bucket used as the Terraform remote state backend.
#
# This is intentionally NOT part of the main `terraform/` root module,
# because the state bucket must exist *before* `terraform init` can
# configure the "gcs" backend for the root module. Apply this once per
# GCP project, with local state, before running the main pipeline.
#
# Usage:
#   cd terraform/bootstrap
#   terraform init
#   terraform apply -var="project_id=<PROJECT_ID>"

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.30"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

resource "google_storage_bucket" "tfstate" {
  project                     = var.project_id
  name                         = "order-service-tfstate-${var.project_id}"
  location                     = var.region
  storage_class                = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy                = false

  versioning {
    enabled = true
  }

  # GCS native locking is automatic for the "gcs" backend (no extra
  # resource needed) as long as uniform bucket-level access + object
  # versioning are enabled, as configured above.

  lifecycle_rule {
    condition {
      num_newer_versions = 20
    }
    action {
      type = "Delete"
    }
  }

  soft_delete_policy {
    retention_duration_seconds = 604800 # 7 days
  }
}

output "bucket_name" {
  value = google_storage_bucket.tfstate.name
}

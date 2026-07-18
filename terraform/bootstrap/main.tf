# Bootstrap: resources that must exist *before* the main pipeline can run
# at all - the Terraform state bucket, and the Artifact Registry repository
# CI pushes images to.
#
# These are intentionally NOT part of the main `terraform/` root module:
# - The state bucket must exist before `terraform init` can configure the
#   "gcs" backend for the root module.
# - The required pipeline shape is
#   [lint+test] -> [build & push image] -> [terraform plan/apply] -> ...
#   i.e. the image is built and pushed to Artifact Registry *before*
#   `terraform apply` ever runs, so the repository can't be created by the
#   main module either - it must already exist ahead of time, same as the
#   state bucket.
#
# Apply this once per GCP project, with local state, before running the
# main pipeline.
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

resource "google_artifact_registry_repository" "order_service" {
  project       = var.project_id
  location      = var.region
  repository_id = "order-service"
  format        = "DOCKER"
  description   = "Container images for order-service, pushed by CI on merge to main."

  docker_config {
    immutable_tags = true # images are tagged with the git SHA and never overwritten (see REVIEW.md issue #2)
  }
}

output "artifact_registry_repository" {
  value = google_artifact_registry_repository.order_service.repository_id
}

output "bucket_name" {
  value = google_storage_bucket.tfstate.name
}

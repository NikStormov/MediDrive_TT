terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.30"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Backend configuration is intentionally left partial. Concrete bucket /
  # prefix values are supplied per environment via -backend-config so that
  # staging and production never share (or collide on) state:
  #
  #   terraform init -backend-config=environments/staging.backend.hcl
  #   terraform init -backend-config=environments/production.backend.hcl
  #
  # The GCS backend provides native state locking (no separate DynamoDB-style
  # lock table needed) and versioned, encrypted-at-rest state storage.
  backend "gcs" {}
}

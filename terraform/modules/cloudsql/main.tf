resource "google_sql_database_instance" "postgres" {
  project             = var.project_id
  name                = "${var.instance_name}-${var.environment}"
  database_version    = "POSTGRES_15"
  region              = var.region
  deletion_protection = var.deletion_protection

  settings {
    tier              = var.tier
    availability_type = var.availability_type # REGIONAL = HA with automatic failover
    disk_size         = var.disk_size_gb
    disk_autoresize   = var.disk_autoresize
    disk_type         = "PD_SSD"

    ip_configuration {
      ipv4_enabled                                 = false # no public IP
      private_network                              = var.network_self_link
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      start_time                     = "03:00"

      backup_retention_settings {
        retained_backups = var.backup_retained_count
        retention_unit    = "COUNT"
      }
    }

    maintenance_window {
      day          = 7 # Sunday
      hour         = 3
      update_track = "stable"
    }

    insights_config {
      query_insights_enabled  = true
      record_application_tags = true
    }

    database_flags {
      name  = "log_min_duration_statement"
      value = "500" # log slow queries (>500ms) to help diagnose latency SLO breaches
    }
  }

  # Cloud SQL private IP requires the VPC peering (Private Services Access)
  # connection to exist first.
  depends_on = [var.private_vpc_connection]

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_sql_database" "order_service" {
  project  = var.project_id
  name     = var.database_name
  instance = google_sql_database_instance.postgres.name
}

# Credentials are generated randomly and never appear in tfvars, CLI args,
# or environment variables — only in Secret Manager and in Terraform state
# (which itself should be encrypted-at-rest in the GCS backend + access
# restricted via IAM, see backend.tf).
resource "random_password" "db_password" {
  length  = 32
  special = true
}

resource "google_sql_user" "app" {
  project  = var.project_id
  name     = var.database_user
  instance = google_sql_database_instance.postgres.name
  password = random_password.db_password.result
}

resource "google_secret_manager_secret" "db_credentials" {
  project   = var.project_id
  secret_id = "order-service-db-credentials-${var.environment}"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_credentials" {
  secret = google_secret_manager_secret.db_credentials.id

  secret_data = jsonencode({
    username         = google_sql_user.app.name
    password         = random_password.db_password.result
    database         = google_sql_database.order_service.name
    host             = google_sql_database_instance.postgres.private_ip_address
    connection_name  = google_sql_database_instance.postgres.connection_name
  })
}

# Only the application's Workload Identity GSA (bound to the Kubernetes
# ServiceAccount used by order-service) can read this secret.
resource "google_secret_manager_secret_iam_member" "app_secret_accessor" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.db_credentials.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = var.workload_identity_secret_accessor_member
}

output "instance_name" {
  value = google_sql_database_instance.postgres.name
}

output "connection_name" {
  description = "Cloud SQL connection name, used by the Cloud SQL Auth Proxy / connector if needed."
  value       = google_sql_database_instance.postgres.connection_name
}

output "private_ip_address" {
  value = google_sql_database_instance.postgres.private_ip_address
}

output "database_name" {
  value = google_sql_database.order_service.name
}

output "secret_id" {
  description = "Secret Manager secret ID holding the DB credentials JSON payload."
  value       = google_secret_manager_secret.db_credentials.secret_id
}

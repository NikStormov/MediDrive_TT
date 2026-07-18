# Values consumed by the CI/CD pipeline (.github/workflows/deploy.yml) and
# by anyone bootstrapping kubectl/gcloud access to the cluster.

output "network_name" {
  value = module.networking.network_name
}

output "gke_cluster_name" {
  value = module.gke.cluster_name
}

output "gke_cluster_endpoint" {
  value     = module.gke.cluster_endpoint
  sensitive = true
}

output "gke_cluster_ca_certificate" {
  value     = module.gke.cluster_ca_certificate
  sensitive = true
}

output "workload_identity_app_sa_email" {
  value = module.gke.workload_identity_app_sa_email
}

output "cloudsql_instance_name" {
  value = module.cloudsql.instance_name
}

output "cloudsql_private_ip" {
  value = module.cloudsql.private_ip_address
}

output "cloudsql_connection_name" {
  value = module.cloudsql.connection_name
}

output "db_credentials_secret_id" {
  value = module.cloudsql.secret_id
}

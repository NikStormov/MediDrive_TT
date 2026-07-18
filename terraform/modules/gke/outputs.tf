output "cluster_name" {
  value = google_container_cluster.primary.name
}

output "cluster_id" {
  value = google_container_cluster.primary.id
}

output "cluster_endpoint" {
  description = "Private endpoint of the GKE control plane."
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  value     = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive = true
}

output "node_service_account_email" {
  value = google_service_account.gke_nodes.email
}

output "workload_identity_app_sa_email" {
  description = "GSA email the Kubernetes ServiceAccount binds to via Workload Identity for Secret Manager access."
  value       = google_service_account.workload_identity_app.email
}

output "workload_pool" {
  value = "${var.project_id}.svc.id.goog"
}

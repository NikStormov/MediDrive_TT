output "network_id" {
  description = "Self link / ID of the VPC network."
  value       = google_compute_network.main.id
}

output "network_name" {
  value = google_compute_network.main.name
}

output "network_self_link" {
  value = google_compute_network.main.self_link
}

output "gke_subnet_id" {
  value = google_compute_subnetwork.gke_nodes.id
}

output "gke_subnet_name" {
  value = google_compute_subnetwork.gke_nodes.name
}

output "gke_subnet_self_link" {
  value = google_compute_subnetwork.gke_nodes.self_link
}

output "gke_pods_range_name" {
  value = "gke-pods"
}

output "gke_services_range_name" {
  value = "gke-services"
}

output "cloudsql_private_vpc_connection" {
  description = "The service networking connection Cloud SQL must depend_on before creating a private-IP instance."
  value       = google_service_networking_connection.cloudsql_psa.network
}

output "router_name" {
  value = google_compute_router.main.name
}

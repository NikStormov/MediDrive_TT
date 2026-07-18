# Custom VPC — not the GCP default network. auto_create_subnetworks is
# disabled so every subnet is explicit and scoped to its purpose.
resource "google_compute_network" "main" {
  project                 = var.project_id
  name                     = "${var.network_name}-${var.environment}"
  auto_create_subnetworks  = false
  routing_mode             = "REGIONAL"
}

# Subnet dedicated to GKE nodes. Secondary ranges provide alias IPs for pods
# and services (VPC-native cluster), kept in a different CIDR block than the
# node primary range and than the Cloud SQL private services range below.
resource "google_compute_subnetwork" "gke_nodes" {
  project       = var.project_id
  name          = "${var.network_name}-gke-nodes-${var.environment}"
  ip_cidr_range = var.gke_subnet_cidr
  region        = var.region
  network       = google_compute_network.main.id

  private_ip_google_access = true # required so private nodes can reach Google APIs (Artifact Registry, Secret Manager, Logging/Monitoring)

  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = var.gke_pods_cidr
  }

  secondary_ip_range {
    range_name    = "gke-services"
    ip_cidr_range = var.gke_services_cidr
  }

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata              = "INCLUDE_ALL_METADATA"
  }
}

# Cloud SQL does not live in a regular subnet — private IP is implemented via
# VPC peering (Private Services Access). We still reserve a dedicated,
# non-overlapping CIDR range for it so the "separate address space per
# workload" requirement holds even though the mechanism differs from a
# regular subnetwork.
resource "google_compute_global_address" "cloudsql_psa_range" {
  project       = var.project_id
  name          = var.cloudsql_private_range_name
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  address       = split("/", var.cloudsql_private_range_cidr)[0]
  network       = google_compute_network.main.id
}

resource "google_service_networking_connection" "cloudsql_psa" {
  network                 = google_compute_network.main.id
  service                  = "servicenetworking.googleapis.com"
  reserved_peering_ranges  = [google_compute_global_address.cloudsql_psa_range.name]
}

# --- Cloud Router + Cloud NAT ---------------------------------------------
# Private GKE nodes have no public IPs. NAT provides outbound-only internet
# access (pulling public images, calling the external billing API) without
# exposing the nodes to inbound traffic.
resource "google_compute_router" "main" {
  project = var.project_id
  name    = "${var.network_name}-router-${var.environment}"
  region  = var.region
  network = google_compute_network.main.id
}

resource "google_compute_router_nat" "main" {
  project                            = var.project_id
  name                               = "${var.network_name}-nat-${var.environment}"
  router                             = google_compute_router.main.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.gke_nodes.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  min_ports_per_vm = var.nat_min_ports_per_vm

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# --- Firewall rules ---------------------------------------------------------
# Default-deny posture: only the traffic explicitly required is allowed.
# GCP custom VPCs already implicit-deny all ingress, so we only need to add
# explicit ALLOW rules for what's needed, plus one explicit deny for clarity.

# Allow intra-VPC traffic between GKE nodes/pods (kubelet, pod-to-pod, DNS).
resource "google_compute_firewall" "allow_internal" {
  project = var.project_id
  name    = "${var.network_name}-allow-internal-${var.environment}"
  network = google_compute_network.main.id

  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [
    var.gke_subnet_cidr,
    var.gke_pods_cidr,
    var.gke_services_cidr,
  ]
  target_tags = ["gke-node"]
}

# Allow GCP health checkers (used by GKE/GCLB) to reach node health check
# endpoints. These are Google-owned ranges, not "the internet".
resource "google_compute_firewall" "allow_health_checks" {
  project = var.project_id
  name    = "${var.network_name}-allow-health-checks-${var.environment}"
  network = google_compute_network.main.id

  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["gke-node"]
}

# Explicit, scoped access for administrators/CI to reach the GKE master via
# master_authorized_networks (enforced on the cluster resource itself); this
# firewall rule additionally restricts SSH/bastion-style access at the VPC
# level to the same trusted CIDRs, never 0.0.0.0/0.
resource "google_compute_firewall" "allow_trusted_admin_access" {
  count   = length(var.allowed_ingress_cidrs) > 0 ? 1 : 0
  project = var.project_id
  name    = "${var.network_name}-allow-admin-${var.environment}"
  network = google_compute_network.main.id

  direction = "INGRESS"
  priority  = 900

  allow {
    protocol = "tcp"
    ports    = ["22", "443"]
  }

  source_ranges = var.allowed_ingress_cidrs
  target_tags   = ["bastion"]
}

# Deny everything else inbound (defense in depth / documentation of intent).
resource "google_compute_firewall" "deny_all_ingress" {
  project = var.project_id
  name    = "${var.network_name}-deny-all-ingress-${var.environment}"
  network = google_compute_network.main.id

  direction = "INGRESS"
  priority  = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
}

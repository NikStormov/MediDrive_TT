# Dedicated GSA for GKE nodes. Nodes only need the minimum scopes to ship
# logs/metrics and pull images from Artifact Registry — application-level
# GCP access (e.g. Secret Manager) is granted per-Kubernetes-ServiceAccount
# via Workload Identity, not through this node-level identity.
resource "google_service_account" "gke_nodes" {
  project      = var.project_id
  account_id   = "gke-node-${var.environment}"
  display_name = "GKE node service account (${var.environment})"
}

resource "google_project_iam_member" "gke_nodes_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/artifactregistry.reader",
    "roles/stackdriver.resourceMetadata.writer",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# Dedicated GSA the application Kubernetes ServiceAccount impersonates via
# Workload Identity to reach Secret Manager (DB credentials, billing API
# key) — see cloudsql module for the secretAccessor binding.
resource "google_service_account" "workload_identity_app" {
  project      = var.project_id
  account_id   = "order-service-wi-${var.environment}"
  display_name = "Workload Identity SA for order-service (${var.environment})"
}

resource "google_binary_authorization_policy" "default" {
  project = var.project_id

  default_admission_rule {
    evaluation_mode  = "REQUIRE_ATTESTATION"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"

    require_attestations_by = []
  }

  # Google-built system images (kube-system components) are exempt so the
  # cluster itself remains functional; the application image still requires
  # attestation.
  admission_whitelist_patterns {
    name_pattern = "gcr.io/gke-release/*"
  }
  admission_whitelist_patterns {
    name_pattern = "gke.gcr.io/*"
  }
}

resource "google_container_cluster" "primary" {
  project  = var.project_id
  name     = "${var.cluster_name}-${var.environment}"
  location = var.region # regional cluster: control plane replicas across 3 zones

  # Nodes are managed entirely through the dedicated node pool below.
  remove_default_node_pool = true
  initial_node_count        = 1

  network    = var.network_self_link
  subnetwork = var.subnetwork_self_link

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  private_cluster_config {
    enable_private_nodes    = true  # nodes have no public IPs
    enable_private_endpoint = false # control plane still reachable from authorized networks below (CI runners, VPN)
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_cidrs
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  release_channel {
    channel = var.release_channel
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = "02:00" # low-traffic window, UTC
    }
  }

  vertical_pod_autoscaling {
    enabled = true
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
    managed_prometheus {
      enabled = true
    }
  }

  addons_config {
    horizontal_pod_autoscaling { disabled = false }
    http_load_balancing        { disabled = false }
    gce_persistent_disk_csi_driver_config { enabled = true }
  }

  depends_on = [
    google_binary_authorization_policy.default,
  ]
}

# Separate node pool dedicated to the order-service application workload,
# isolated from any future system/tooling node pools.
resource "google_container_node_pool" "app" {
  project  = var.project_id
  name     = "app-workload-${var.environment}"
  location = var.region
  cluster  = google_container_cluster.primary.name

  autoscaling {
    min_node_count = var.app_node_min_count
    max_node_count = var.app_node_max_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type    = var.app_node_machine_type
    disk_size_gb    = var.app_node_disk_size_gb
    disk_type       = var.app_node_disk_type
    service_account = google_service_account.gke_nodes.email

    # Nodes have no public IP (enable_private_nodes above); scopes kept
    # minimal since real permissions come from the node SA's IAM roles.
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA" # required for Workload Identity
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = {
      workload    = "order-service"
      environment = var.environment
    }

    tags = ["gke-node", "order-service"]
  }
}

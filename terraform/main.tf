provider "google" {
  project = var.project_id
  region  = var.region
}

module "networking" {
  source = "./modules/networking"

  project_id            = var.project_id
  region                = var.region
  environment           = var.environment
  gke_subnet_cidr       = var.gke_subnet_cidr
  gke_pods_cidr         = var.gke_pods_cidr
  gke_services_cidr     = var.gke_services_cidr
  allowed_ingress_cidrs = var.master_authorized_cidrs[*].cidr_block
}

module "gke" {
  source = "./modules/gke"

  project_id              = var.project_id
  region                  = var.region
  environment             = var.environment
  network_self_link       = module.networking.network_self_link
  subnetwork_self_link    = module.networking.gke_subnet_self_link
  pods_range_name         = module.networking.gke_pods_range_name
  services_range_name     = module.networking.gke_services_range_name
  master_authorized_cidrs = var.master_authorized_cidrs

  app_node_min_count = var.app_node_min_count
  app_node_max_count = var.app_node_max_count
}

module "cloudsql" {
  source = "./modules/cloudsql"

  project_id             = var.project_id
  region                 = var.region
  environment            = var.environment
  network_self_link      = module.networking.network_self_link
  private_vpc_connection = module.networking.cloudsql_private_vpc_connection

  workload_identity_secret_accessor_member = "serviceAccount:${module.gke.workload_identity_app_sa_email}"
}

# Binds the Kubernetes ServiceAccount (namespace/name defined in
# k8s/deployment.yaml) to the GCP Workload Identity GSA, completing the
# chain of trust described in ANSWERS.md Q2.
#
# Explicit depends_on is required: the member string references the
# "<project>.svc.id.goog" identity pool directly as a string literal, not
# as a resource attribute, so Terraform's implicit dependency graph (built
# from module.gke.workload_identity_app_sa_email, which only depends on the
# service account resource) does not know this binding must wait for the
# GKE cluster's Workload Identity pool to actually exist. Without this,
# Terraform applies it in parallel with cluster creation and fails with
# "Identity Pool does not exist".
resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${module.gke.workload_identity_app_sa_email}"
  role                = "roles/iam.workloadIdentityUser"
  member              = "serviceAccount:${var.project_id}.svc.id.goog[order-service/order-service]"

  depends_on = [module.gke]
}

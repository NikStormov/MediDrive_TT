project_id  = "medidrivett"
region      = "us-central1"
environment = "production"

# CI runner / VPN egress ranges allowed to reach the GKE API server.
master_authorized_cidrs = [
  {
    cidr_block   = "203.0.113.0/28"
    display_name = "ci-runner-egress"
  },
  {
    cidr_block   = "198.51.100.0/28"
    display_name = "office-vpn"
  },
]

app_node_min_count = 3
app_node_max_count = 10

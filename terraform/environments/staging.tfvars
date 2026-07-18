project_id  = "medidrivett"
region      = "us-central1"
environment = "staging"

# CI runner / VPN egress ranges allowed to reach the GKE API server.
master_authorized_cidrs = [
  {
    cidr_block   = "8.8.8.8/32"
    display_name = "static-ip"
  },
]

app_node_min_count = 2
app_node_max_count = 6

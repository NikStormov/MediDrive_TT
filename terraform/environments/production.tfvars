project_id  = "medidrivett"
region      = "us-central1"
environment = "production"

# CI runner / VPN egress ranges allowed to reach the GKE API server.
master_authorized_cidrs = [
  {
    cidr_block   = "45.148.148.42/32"
    display_name = "admin-static-ip"
  },
]

app_node_min_count = 3
app_node_max_count = 10

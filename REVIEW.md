# Code Review  Buggy Snippets

This file consolidates the three buggy-snippet reviews required by `task-1 SRE.md`:
**5 Terraform issues + 5 Kubernetes manifest issues + 4 CI/CD pipeline issues.**

---

## Part 1  Terraform

```
resource "google_sql_database_instance" "postgres" {
  name             = "order-db"
  database_version = "POSTGRES_15"
  region           = "us-central1"

  settings {
    tier = "db-f1-micro"

    ip_configuration {
      ipv4_enabled = true
    }

    backup_configuration {
      enabled = false
    }
  }

  deletion_protection = false
}

resource "google_container_cluster" "main" {
  name     = "order-cluster"
  location = "us-central1"

  remove_default_node_pool = false

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block = "0.0.0.0/0"
    }
  }
}
```

### 1. Cloud SQL instance has a public IP enabled

**Location:** `ip_configuration { ipv4_enabled = true }`

**Problem:** The instance is configured with a public IPv4 address.

**Impact:** Violates the "private IP only" requirement, exposes PostgreSQL directly to the internet, and massively increases attack surface (credential stuffing, port scanning, exploitation of unpatched CVEs) since the database would be reachable outside the VPC.

**Fix:**
```
ip_configuration {
  ipv4_enabled                                  = false
  private_network                               = google_compute_network.main.id
  enable_private_path_for_google_cloud_services  = true
}
```
Requires a `google_service_networking_connection` (Private Services Access) to already exist, as provisioned in `terraform/modules/networking`.

---

### 2. Automated backups are disabled

**Location:** `backup_configuration { enabled = false }`

**Problem:** No automated backups are taken.

**Impact:** No recovery path from data corruption, a bad migration, or accidental deletion  a single incident could mean permanent data loss for all customer orders. Violates the "automated backups with appropriate retention" requirement.

**Fix:**
```
backup_configuration {
  enabled                        = true
  point_in_time_recovery_enabled = true
  backup_retention_settings {
    retained_backups = 30
    retention_unit    = "COUNT"
  }
}
```

---

### 3. Deletion protection is disabled

**Location:** `deletion_protection = false`

**Problem:** The instance can be destroyed by a single `terraform destroy`/`apply` or manual console action.

**Impact:** Accidental deletion of the production database  total, unrecoverable data loss and full service outage. Directly violates the explicit requirement.

**Fix:** `deletion_protection = true` (plus a `lifecycle { prevent_destroy = true }` block for defense in depth, as done in `terraform/modules/cloudsql/main.tf`).

---

### 4. `db-f1-micro` tier  no HA, not production-sized

**Location:** `tier = "db-f1-micro"` (and no `availability_type` set, so it defaults to `ZONAL`)

**Problem:** `db-f1-micro` is a shared-core, burstable dev/test tier and does not support regional (HA) availability.

**Impact:** At ~5,000 req/min the instance would be CPU/connection starved almost immediately, and a single zone outage would take the database (and the whole service) down with no automatic failover  violating the HA requirement.

**Fix:**
```
tier              = "db-custom-4-16384"
availability_type = "REGIONAL"
```

---

### 5. GKE master authorized networks allow `0.0.0.0/0`

**Location:** `master_authorized_networks_config { cidr_blocks { cidr_block = "0.0.0.0/0" } }`

**Problem:** The Kubernetes API server is reachable from any IP on the internet.

**Impact:** Exposes the cluster control plane to brute-force/credential attacks and vulnerability scanning from anywhere; combined with any leaked/weak credentials this is a direct path to full cluster compromise. Explicitly forbidden by the requirements.

**Fix:**
```
master_authorized_networks_config {
  cidr_blocks {
    cidr_block   = "203.0.113.0/28"
    display_name = "ci-runner-egress"
  }
}
```
Restrict to specific, known, trusted CIDR ranges only (CI runner egress, VPN/bastion), never a wildcard.

*(Also note, as a bonus observation: `remove_default_node_pool = false` leaves the auto-created default node pool running alongside any dedicated pools, which conflicts with the "separate node pool for the application workload" requirement and wastes cost  it should be `true`, with dedicated `google_container_node_pool` resources instead.)*

---

## Part 2  Kubernetes Manifest

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: order-service
          image: order-service:latest
          resources:
            limits:
              cpu: "4"
              memory: "4Gi"
          livenessProbe:
            httpGet:
              path: /readyz
              port: 8080
            initialDelaySeconds: 0
            failureThreshold: 1
          env:
            - name: DB_PASSWORD
              value: "supersecret123"
```

### 1. `replicas: 1`  no redundancy

**Problem:** Only a single pod runs the service.

**Impact:** Any pod restart, node drain, or rolling update causes a full outage (there is no second pod to serve traffic in the meantime); a `PodDisruptionBudget` also becomes meaningless with one replica. Cannot sustain ~5,000 req/min or survive a node failure.

**Fix:** Set `replicas` based on expected load with the HPA managing the range (see `k8s/deployment.yaml` / `k8s/hpa.yaml`: baseline 6, HPA range 3-15).

---

### 2. `image: order-service:latest`  mutable tag

**Problem:** `:latest` is a floating tag; the exact code running is not traceable, and a redeploy of the same manifest can silently pull a different image than what was tested.

**Impact:** Breaks reproducible deployments and rollbacks  `kubectl rollout undo` cannot reliably restore a previous *version* if the tag always points at whatever was pushed most recently. Explicitly forbidden by the requirements.

**Fix:** Tag images with the immutable git SHA from CI, e.g. `...pkg.dev/PROJECT/order-service/order-service:<git-sha>`, and reference that exact tag in the manifest / `kubectl set image`.

---

### 3. Only `limits` are set  no `resources.requests`

**Problem:** The container defines `resources.limits` (cpu `"4"`, memory `4Gi`) but no `resources.requests`.

**Impact:** Without `requests`, the scheduler has no reservation to bin-pack against, so Kubernetes cannot make informed placement decisions and the **HPA cannot compute CPU/memory utilization** (which is measured against `requests`)  the CPU-based HPA in `k8s/hpa.yaml` would simply not work. A `4`-core CPU **limit** on a shared cluster is also oversized (see `ANSWERS.md` Q6): it invites noisy-neighbor scheduling problems and, ironically, can still cause CFS-quota throttling/latency spikes under bursty load even while overall utilization looks fine.

**Fix:** Set an explicit, right-sized `requests` (e.g. `cpu: 250m`, `memory: 256Mi`) and either drop the CPU limit entirely (see Q6) or size it modestly rather than to a full node's worth of cores; keep a memory limit for OOM isolation.

---

### 4. Liveness probe points at `/readyz` and is misconfigured

**Problem:** `livenessProbe` calls `/readyz` (the readiness/dependency-health endpoint) instead of `/healthz` (the liveness/process-health endpoint), with `initialDelaySeconds: 0` and `failureThreshold: 1`. There is also no separate `readinessProbe` defined at all.

**Impact:** `/readyz` typically reflects the health of dependencies (DB, billing API)  using it for **liveness** means a transient DB hiccup causes Kubernetes to **kill and restart** otherwise-healthy pods (instead of just pulling them out of Service rotation, which is what readiness is for), amplifying an outage. `initialDelaySeconds: 0` gives the process no startup grace period, and `failureThreshold: 1` means a single slow/failed check triggers an immediate restart  together these can cause a restart/crash-loop during normal startup or brief blips.

**Fix:** Point `livenessProbe` at `/healthz` with sane thresholds (e.g. `initialDelaySeconds: 10`, `failureThreshold: 3`), and add a distinct `readinessProbe` against `/readyz` (see `k8s/deployment.yaml`), plus a `startupProbe` to cover slow cold starts without weakening the steady-state liveness thresholds.

---

### 5. `DB_PASSWORD` hardcoded in plaintext

**Problem:** `env: - name: DB_PASSWORD value: "supersecret123"` puts a real credential directly in the manifest.

**Impact:** The password is committed to git history (permanently, even if later removed), visible to anyone with `kubectl get pod -o yaml` / `describe` access in the namespace, and cannot be rotated without a code change and redeploy. Explicitly forbidden by the requirements.

**Fix:** Source it from a Kubernetes `Secret` populated by the Secrets Store CSI Driver from GCP Secret Manager via Workload Identity, using `secretKeyRef`  never a literal `value:` (see `k8s/secret.yaml` and `k8s/deployment.yaml`).

---

## Part 3  CI/CD Pipeline

```yaml
name: Deploy
on:
  push:
    branches: ["*"]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Build and push
        run: |
          docker build -t order-service:latest .
          docker push order-service:latest

      - name: Deploy to production
        run: kubectl set image deployment/order-service order-service=order-service:latest

      - name: Run tests
        run: go test ./...
```

### 1. Deploys to production on every push, to every branch

**Location:** `on: push: branches: ["*"]`

**Problem:** The workflow runs  and deploys straight to production  on a push to *any* branch, including feature/WIP branches, with no PR review gate and no restriction to `main`.

**Impact:** Any developer pushing to any branch (even accidentally, even force-pushing broken WIP code) immediately ships to production users. There is no staging environment, no plan/review step, and no manual approval anywhere in the pipeline.

**Fix:** Trigger `pull_request` for lint/test/`terraform plan` only, and restrict the deploy path to `push: branches: [main]`; gate production behind a manual-approval `environment:` (see `.github/workflows/deploy.yml`).

---

### 2. Image tagged `:latest`, pushed to the default registry (not Artifact Registry)

**Location:** `docker build -t order-service:latest .` / `docker push order-service:latest`

**Problem:** No registry host is specified (defaults to Docker Hub, not GCP Artifact Registry), and the tag is the mutable `:latest` rather than the commit SHA.

**Impact:** No traceability between a deployed image and the commit/PR that produced it; rollbacks are unreliable since `:latest` always points to whatever was last pushed; violates both the "Artifact Registry, not Docker Hub" and "no `latest` tag" requirements; also has no authentication step, so the push would simply fail against a private registry.

**Fix:**
```bash
docker build -t us-central1-docker.pkg.dev/$PROJECT/order-service/order-service:$GITHUB_SHA .
docker push us-central1-docker.pkg.dev/$PROJECT/order-service/order-service:$GITHUB_SHA
```
authenticated via `google-github-actions/auth` (Workload Identity Federation  no static service-account keys), as in `.github/workflows/deploy.yml`.

---

### 3. Production is deployed *before* tests run, with no staging/smoke-test stage

**Location:** Step order: `Build and push` → `Deploy to production` → `Run tests`

**Problem:** `go test ./...` runs **last**, after the image has already been built, pushed, and deployed to production. There is no staging deployment and no smoke test anywhere.

**Impact:** Broken/failing code can reach production before it's ever validated  the entire purpose of running tests in CI is defeated if they run after the deploy. Violates the required pipeline shape (`lint+test → build & push → plan/apply → staging → smoke test → production`).

**Fix:** Run lint/tests first (fail fast, before building anything); insert a staging deploy + `kubectl rollout status` wait + smoke tests (`/healthz`, `/readyz`) between build and production deploy; gate production behind manual approval only after staging smoke tests pass.

---

### 4. No rollout verification and no rollback on failure

**Location:** `kubectl set image deployment/order-service order-service=order-service:latest` (no follow-up)

**Problem:** The pipeline fires the image update and immediately moves on  it never waits for `kubectl rollout status` to confirm the new pods actually become healthy, and there is no rollback step if they don't.

**Impact:** A bad image (crash-looping, failing readiness) can silently sit half-rolled-out or fully rolled out in production, serving errors, with the pipeline reporting a false "success" and no automatic remediation.

**Fix:**
```bash
kubectl rollout status deployment/order-service -n order-service --timeout=5m
```
with an `if: failure()` step running `kubectl rollout undo deployment/order-service -n order-service` to automatically roll back (see `.github/workflows/deploy.yml`, `deploy-production` job).

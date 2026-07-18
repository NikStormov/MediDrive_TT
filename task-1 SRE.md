# SRE Assessment - Senior Level

## Instructions

1. Complete all parts below
2. Push your solution to a **public GitHub repository**
3. Reply to this email with your repository URL
4. Deadline: 5 days from receiving this email - 17.07.2026 recived

---

## Context

You are the SRE responsible for a Go-based order processing service (`order-service`) that:
- Handles ~5,000 requests/min at peak
- Depends on PostgreSQL and an external billing API
- Currently deployed manually — no IaC, no CI/CD, no SLOs, no alerting
- Target platform: **GCP**

Your job is to take this service from zero to production-ready.

---

## Part 1: Infrastructure as Code — Terraform (`terraform/`)

Provision the GCP infrastructure required to run the service using Terraform modules.

### Requirements

**Networking (`terraform/modules/networking/`)**
- Custom VPC (not default)
- Separate subnets for GKE nodes and Cloud SQL — different CIDR ranges, different regions not required but justified
- Cloud NAT for private egress
- Firewall rules scoped to minimum required traffic only

**GKE Cluster (`terraform/modules/gke/`)**
- Private cluster — nodes have no public IPs
- Separate node pool for the application workload
- Node pool sizing appropriate for ~5,000 req/min with headroom for autoscaling
- Workload Identity enabled (no service account key files)
- Binary Authorization enabled
- Master authorized networks restricted — do not allow `0.0.0.0/0`

**Cloud SQL (`terraform/modules/cloudsql/`)**
- PostgreSQL 15, private IP only (no public IP)
- High availability configuration enabled
- Automated backups with appropriate retention
- Deletion protection enabled
- Credentials stored in Secret Manager — not in tfvars or environment variables

**State Backend (`terraform/backend.tf`)**
- GCS bucket for state storage
- State locking via GCS native locking
- Separate state per environment (staging / production)

**Outputs**
- Expose all values downstream modules or the CI/CD pipeline would need

### Buggy Terraform — Find All Issues

This Terraform snippet has 5 problems. List each one in `REVIEW.md` with: location, problem, impact, and fix.

```hcl
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

---

## Part 2: Kubernetes Manifests (`k8s/`)

Write production-grade Kubernetes manifests for the service.

### Requirements

**Deployment (`k8s/deployment.yaml`)**
- Replica count appropriate for the traffic volume — justify in `ANSWERS.md`
- Resource requests and limits set — justify your values
- Liveness and readiness probes configured correctly against the service's `/healthz` and `/readyz` endpoints
- Rolling update strategy that ensures zero downtime
- Credentials sourced from Kubernetes Secrets synced from GCP Secret Manager via Workload Identity — no hardcoded values

**HorizontalPodAutoscaler (`k8s/hpa.yaml`)**
- CPU and memory targets that prevent both under- and over-provisioning
- Scale-down stabilization to prevent flapping

**PodDisruptionBudget (`k8s/pdb.yaml`)**
- Ensure the service stays available during node upgrades and cluster maintenance

### Buggy Manifest — Find All Issues

This manifest has 5 problems. Add each one to `REVIEW.md`:

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

---

## Part 3: CI/CD Pipeline (`.github/workflows/deploy.yml`)

Design a GitHub Actions pipeline:

```
[lint + test] → [build & push image] → [terraform plan/apply] → [deploy staging] → [smoke test] → [deploy production]
```

### Requirements

- Tests run with race detection enabled
- Docker images tagged with git SHA and pushed to **Artifact Registry** (not Docker Hub)
- `terraform plan` runs on every PR and posts the output as a PR comment
- `terraform apply` runs on merge to `main` only, with manual approval
- Staging deploy waits for rollout to complete before smoke tests run
- Smoke tests validate both `/healthz` and `/readyz`
- Production deploy requires a manual approval gate
- Automatic rollback triggered if production deploy fails

### Buggy Pipeline — Find All Issues

This pipeline has 4 problems. Add them to `REVIEW.md`:

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

---

## Part 4: SLOs and Alerting (`observability/`)

### 4.1 SLO Definitions (`observability/slo.yaml`)

Define the following SLOs using Prometheus recording rules:

| SLO | Target | Window |
|-----|--------|--------|
| Availability | 99.9% of requests return non-5xx | 30-day rolling |
| Latency | 95% of requests complete in < 500ms | 30-day rolling |
| Error budget burn | Alert at 5x burn rate | 1-hour window |

### 4.2 Alerting Rules (`observability/alerts.yaml`)

Write Prometheus alerting rules for the following conditions. Each rule must have appropriate labels (`severity`) and annotations (`summary`, `description`, `runbook_url`):

1. Error rate exceeds 1% sustained for 5 minutes — `critical`
2. p99 latency exceeds 1 second sustained for 10 minutes — `warning`
3. Error budget burn rate exceeds 5x over a 1-hour window — `critical`
4. Any pod is crash-looping (more than 3 restarts in 15 minutes) — `warning`
5. Database connection pool is near exhaustion (less than 10% available) sustained for 5 minutes — `critical`

### 4.3 Grafana Dashboard (`observability/dashboard.json`)

Create a Grafana dashboard with the following panels:

1. Request rate broken down by HTTP status code
2. Error rate percentage (5xx / total)
3. Latency percentiles — p50, p95, p99 on a single graph
4. Available replica count
5. Error budget remaining — gauge panel that turns red below 10%

---

## Part 5: Incident Response (`runbooks/`)

### 5.1 Alert Runbook (`runbooks/high-error-rate.md`)

Write an actionable runbook for the `HighErrorRate` alert. It must be usable by an on-call engineer who did not write the service. Include:
- Alert context and user impact
- Step-by-step diagnosis using `kubectl` and PromQL
- Resolution steps ordered from least to most disruptive
- Escalation path and criteria

### 5.2 Postmortem Template (`runbooks/postmortem-template.md`)

Write a blameless postmortem template covering:
- Incident summary (title, date, duration, severity, on-call)
- Timeline: detection → mitigation → resolution
- Root cause analysis using 5 Whys
- Impact: users affected, SLO budget burned
- Action items with owner and due date
- Lessons learned

---

## Questions — Answer in `ANSWERS.md`

**Q1:** Your GKE nodes are in a private subnet with no public IP. Walk through exactly how a pod pulls an image from Artifact Registry. Name every GCP component involved in the network path.

**Q2:** Workload Identity is enabled. Explain how a pod authenticates to GCP Secret Manager without a service account key file. What is the chain of trust?

**Q3:** `terraform plan` shows your Cloud SQL instance will be destroyed and recreated. What do you do before running `terraform apply`? List every step in order.

**Q4:** Your deployment has 3 replicas. During a rolling update the new pod immediately starts returning 500s. Walk through exactly what happens given your readiness probe configuration. What is the state of the old pods? Does the HPA react?

**Q5:** Your 30-day error budget is 43 minutes (0.1% of 30 days). At 3 AM an alert fires: burn rate is 10x. How many minutes of budget are you consuming per hour? How long until the budget is exhausted? What is your response?

**Q6:** A colleague suggests setting CPU limit to 4 cores so the service is never throttled. What is wrong with this in a shared GKE cluster? What would you configure instead and why?

**Q7:** Design a canary deployment strategy using your existing Kubernetes and CI/CD setup — no additional tools required. How do you route 5% of traffic to the new version, automatically promote on success, and automatically rollback if error rate exceeds 1%?

---

## Repository Structure

```
your-repo/
├── terraform/
│   ├── backend.tf
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── modules/
│       ├── networking/
│       ├── gke/
│       └── cloudsql/
├── k8s/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── hpa.yaml
│   ├── pdb.yaml
│   ├── configmap.yaml
│   └── secret.yaml
├── .github/
│   └── workflows/
│       └── deploy.yml
├── observability/
│   ├── slo.yaml
│   ├── alerts.yaml
│   └── dashboard.json
├── runbooks/
│   ├── high-error-rate.md
│   └── postmortem-template.md
├── REVIEW.md
└── ANSWERS.md
```

---

## Evaluation

Your submission will be evaluated against our engineering standards document. Key areas:
- Terraform uses modules with clear separation of concerns (networking / gke / cloudsql)
- No hardcoded credentials anywhere — Secret Manager + Workload Identity throughout
- GKE is a private cluster; Cloud SQL has no public IP
- HA and deletion protection enabled on Cloud SQL
- GCS remote state with per-environment separation
- Kubernetes manifests include correct probes, resource limits, PDB, and HPA
- No `latest` image tag used anywhere in CI/CD or manifests
- `terraform plan` on PRs, `terraform apply` gated on manual approval
- Manual approval before production deploy; automatic rollback on failure
- SLO recording rules are mathematically correct
- All 5 alert rules have severity labels and runbook URLs
- Runbook is actionable without prior knowledge of the service
- All issues found in REVIEW.md: 5 Terraform + 5 manifest + 4 pipeline

---

## Work Log / Session Notes (не часть исходного задания)

> Раздел ведётся отдельно от условия задания выше и не изменяет его. Здесь фиксируются рабочие запросы и статус выполнения по этапам, чтобы не терять контекст между сессиями (в т.ч. между Windows app и VS Code).

### Контекст
- Уровень: junior DevOps (не senior, как указано в задании) — задание используется как учебный трек с помощью ассистента.
- Предыдущий опыт: только DigitalOcean, реализовано в `overdone/` (Terraform droplet/vpc/volume + Ansible hardening/docker/volumes, без GKE/Cloud SQL/GCP).
- Целевая платформа этого задания — **GCP** (VPC, GKE, Cloud SQL), инструментов и опыта по GCP ранее не было.

### Статус по этапам (обновляется по ходу работы)

| Этап | Директория/файл | Статус |
|------|-----------------|--------|
| Part 1 — Terraform networking | `terraform/modules/networking/` | ✅ готово |
| Part 1 — Terraform gke | `terraform/modules/gke/` | ✅ готово |
| Part 1 — Terraform cloudsql | `terraform/modules/cloudsql/` | ✅ готово |
| Part 1 — root + backend | `terraform/backend.tf`, `main.tf`, `variables.tf`, `outputs.tf` | ✅ готово (+ `terraform/bootstrap/` для стейт-бакета, `terraform/environments/*` для staging/production) |
| Part 1 — buggy Terraform review | `REVIEW.md` | ✅ готово |
| Part 2 — k8s manifests | `k8s/*.yaml` | ✅ готово |
| Part 2 — buggy manifest review | `REVIEW.md` | ✅ готово (5 issues) |
| Part 3 — CI/CD pipeline | `.github/workflows/deploy.yml` | ✅ готово |
| Part 3 — buggy pipeline review | `REVIEW.md` | ✅ готово (4 issues) |
| Part 4 — SLO/alerts/dashboard | `observability/*` | ✅ готово |
| Part 5 — runbooks | `runbooks/*.md` | ✅ готово |
| Questions Q1–Q7 | `ANSWERS.md` | ✅ готово |
| Итоговый REVIEW.md (5+5+4) | `REVIEW.md` | ✅ собран (черновики `REVIEW PART 1/2/3.md` оставлены как есть, для истории) |

Легенда: ⬜ не начато · 🟡 в процессе / черновик · ✅ готово

### Рабочие запросы (лог)
1. Создать структуру каталогов/файлов под все части задания (Part 1–5 + REVIEW.md/ANSWERS.md) как основу для последующего наполнения. — выполнено, наполнено полным решением по всем частям (см. таблицу выше).
2. Перед отправкой: заменить плейсхолдеры (`<PROJECT_ID>`, `<org>/<repo>`, CI секреты `WIF_PROVIDER`/`CI_DEPLOYER_SA`, реальные CIDR офиса/CI-раннера) на реальные значения; прогнать `terraform validate`/`terraform fmt`, `kubectl apply --dry-run=client`, и `yamllint`/`actionlint` для workflow перед пушем в публичный репозиторий.

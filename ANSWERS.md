# Answers

## Kubernetes sizing justification (Part 2)

### Replica count

- Peak load: ~5,000 req/min ≈ **84 req/s**.
- Assuming each pod (250m CPU request, typical Go HTTP handler + a DB round-trip) comfortably sustains **~15-20 req/s** before CPU utilization starts pushing past the HPA's 70% target, steady-state peak needs roughly **4-6 pods of real work**.
- Baseline `replicas: 6` in `k8s/deployment.yaml` is set slightly above that minimum so:
  - a `RollingUpdate` with `maxUnavailable: 0` always has spare serving capacity during a deploy,
  - a single node/zone loss (via `topologySpreadConstraints`) doesn't immediately drop below the capacity needed to serve peak load,
  - the `PodDisruptionBudget` (`maxUnavailable: 1`) has room to operate during node upgrades without paging.
- `HorizontalPodAutoscaler` range is **3 (min) – 15 (max)**: 3 is the lowest safe floor for HA off-peak, 15 gives ~2.5-3x headroom above the estimated peak-load pod count for traffic spikes, promotions, or a partial dependency slowdown that increases per-request latency (and therefore CPU-time-per-request).

### Resource requests / limits

- `requests: cpu 250m, memory 256Mi`  sized to what a single Go HTTP handler + DB call/connection pooling typically needs at idle-to-moderate load; this is also the number the HPA's CPU/memory utilization percentages are computed against, so it must reflect real usage, not a placeholder.
- `limits: memory 512Mi` (2x the request)  gives headroom for GC pauses/traffic bursts while still bounding worst-case memory so one runaway pod can't starve node memory for its neighbors (OOM-kill isolation).
- **No CPU limit is set**  see Q6 below for the full reasoning: a CPU limit enforces CFS quota throttling that can hurt tail latency even when average utilization looks fine, while the CPU *request* already gives the scheduler what it needs for correct bin-packing and Quality-of-Service handling.

---

## Q1  How a pod in a private-nodes cluster pulls an image from Artifact Registry

1. **Pod → kubelet**: the kubelet on the (private, no-public-IP) GKE node needs to pull `...-docker.pkg.dev/PROJECT/order-service/order-service:<sha>`.
2. **Node → Google APIs, without a public IP**: the node's subnet (`terraform/modules/networking`) has **Private Google Access** (`private_ip_google_access = true`) enabled. This lets instances with only internal IPs reach Google APIs (including `*.pkg.dev` / Artifact Registry) over Google's internal network, without needing a public IP or routing through Cloud NAT.
3. **DNS resolution**: the Artifact Registry hostname resolves to Google's API IP ranges (the standard public API IPs, reachable privately because of Private Google Access  no NAT/internet egress involved for this call). Cloud NAT is only in the path for traffic to *non-Google* internet destinations (e.g., pulling a public base image from Docker Hub during a build), not for Artifact Registry pulls.
4. **Firewall**: egress from GKE nodes is allowed by default in the custom VPC (only ingress is default-denied in `terraform/modules/networking`), so the outbound HTTPS call to Artifact Registry isn't blocked.
5. **AuthN/AuthZ**: the kubelet authenticates the pull using the **node's Google Service Account** (`gke-node-<env>`, from `terraform/modules/gke`), which has `roles/artifactregistry.reader` granted via `google_project_iam_member`. GKE automatically uses this identity for image pulls  no `imagePullSecrets` or key file needed.
6. **Transfer**: Artifact Registry serves the image manifest + layers over TLS; the kubelet caches layers on the node's local disk and starts the container.

**Components involved:** GKE node (private, no external IP), VPC subnet with Private Google Access, Google's private API backbone, Cloud DNS (public googleapis.com resolution), Artifact Registry, the node's Google Service Account + IAM binding, VPC firewall (egress-allow-by-default), Cloud NAT (only for non-Google internet egress, not this specific path).

---

## Q2  Workload Identity chain of trust to Secret Manager

No service account key file exists anywhere in this chain. The trust chain:

1. The pod runs under a **Kubernetes ServiceAccount (KSA)** `order-service` in namespace `order-service` (`k8s/namespace.yaml`), annotated with `iam.gke.io/gcp-service-account: order-service-wi-<env>@<project>.iam.gserviceaccount.com`.
2. When the app calls a GCP client library, it requests credentials from the GKE **metadata server** (`169.254.169.254`), exactly as it would on a GCE VM  but on GKE with Workload Identity, this call is intercepted by the **GKE metadata server component** running on the node.
3. The GKE metadata server verifies the calling pod's **KSA identity** against the cluster's Workload Identity Pool (`<project>.svc.id.goog`) and checks whether that KSA is authorized to impersonate the annotated **Google Service Account (GSA)**  this authorization is the `google_service_account_iam_member` binding with role `roles/iam.workloadIdentityUser` and member `serviceAccount:<project>.svc.id.goog[order-service/order-service]` (`terraform/main.tf`).
4. If authorized, it exchanges the pod's Kubernetes-issued identity for a **short-lived OAuth2 access token** for the GSA (via GCP's Security Token Service / IAM Credentials API  no static key ever generated).
5. The app uses that token to call **Secret Manager**. Secret Manager checks the GSA's IAM policy: `roles/secretmanager.secretAccessor` was granted only on this specific secret (`google_secret_manager_secret_iam_member` in `terraform/modules/cloudsql`), scoped to that one GSA.
6. If authorized, Secret Manager returns the DB credentials payload; the token is short-lived and automatically rotated by the metadata server  nothing is persisted on disk.

**Chain of trust, end to end:** Kubernetes admission (pod scheduled with a specific KSA) → GKE Workload Identity Pool membership verification → IAM `workloadIdentityUser` binding (KSA→GSA impersonation) → short-lived federated token issuance → Secret Manager resource-level IAM (`secretAccessor` on that one secret only).

---

## Q3  `terraform plan` shows Cloud SQL will be destroyed and recreated

Before running `terraform apply`:

1. **Stop. Do not apply.** A destroy+recreate of the primary database is one of the few Terraform outcomes that can cause irreversible data loss.
2. **Run `terraform plan` with more detail** to identify exactly which attribute is forcing replacement (some Cloud SQL fields, like `name` or certain settings, are immutable and force a new resource).
3. **Determine if the change is intentional.** If it's an accidental side effect of a variable/module change, fix the Terraform config instead of applying  the safest fix is often to avoid the replacement entirely.
4. **Take a fresh, verified backup** outside of the automated schedule (manual on-demand backup / export to GCS) and confirm you can restore from it. Confirm point-in-time recovery is enabled and covers the window you'd need.
5. **Notify stakeholders** and schedule a maintenance window  this is not a change to push silently.
6. **If replacement is genuinely required** (e.g., a deliberate rename or region move), plan an explicit **migrate-then-cutover**, not a Terraform-driven destroy/recreate of the live primary:
   - Provision the new instance under a different resource name/address.
   - Replicate data across (Cloud SQL read replica promotion, Database Migration Service, or `pg_dump`/`pg_restore` for a smaller DB), validate row counts / checksums.
   - Cut the application over (update the Secret Manager connection secret), verify healthy traffic on the new instance.
   - Only then decommission the old instance.
7. Note that in this repo's module, `lifecycle { prevent_destroy = true }` is already set on `google_sql_database_instance.postgres`  `terraform apply` would hard-fail on a destroy attempt, which is a deliberate guardrail forcing a human to consciously remove that block before any destructive apply can proceed.
8. Only apply once the backup/migration path is confirmed safe, during the agreed window, with someone actively monitoring.

---

## Q4  Rolling update, new pod immediately returns 500s (3 replicas, readiness probe configured)

Assume 3 replicas, `RollingUpdate` with `maxUnavailable: 0`, `maxSurge: 25%` (rounds up to 1 extra pod), and a correctly-configured `readinessProbe` against `/readyz`.

1. Kubernetes creates **1 new (4th, surge) pod** with the new image; the 3 old pods are untouched (`maxUnavailable: 0` forbids removing any old pod yet).
2. The new pod starts, but the app immediately starts returning 500s. Since `/readyz` correctly reflects app health, the **readiness probe fails**.
3. A failing readiness probe does **not** restart the container  it only removes the pod from the Service's Endpoints. So the new pod **never receives real user traffic**, and Kubernetes keeps retrying the readiness probe on its configured interval.
4. Because the new pod never becomes `Ready`, the Deployment controller **never proceeds** to update/remove any of the 3 old pods  the rollout **stalls**, sitting at 3 old (Ready) + 1 new (NotReady).
5. **State of the old pods:** all 3 remain fully running and continue serving 100% of production traffic, completely unaffected  this is exactly what `maxUnavailable: 0` is for.
6. If the *liveness* probe (not just readiness) were also failing on `/healthz`, the kubelet would additionally restart the new pod's container repeatedly (crash-loop)  but this still only affects the new pod, not the old ones.
7. A `kubectl rollout status --timeout=...` (as used in this repo's CI, `.github/workflows/deploy.yml`) will eventually **time out** since the rollout never completes, failing the pipeline step; the automatic rollback logic then runs `kubectl rollout undo`.
8. **Does the HPA react?** The HPA's utilization calculation is based on CPU/memory metrics from pods, and Kubernetes explicitly **excludes not-yet-Ready pods** from that calculation (it doesn't count a pod with 0 real traffic/usage as if it were a healthy data point, and won't scale the Deployment based on the broken new pod). So the HPA does not scale up or down *because of* this stuck rollout  it continues reacting only to the real load on the 3 healthy old pods, exactly as if the rollout weren't happening.
9. **Resolution:** without automatic rollback, the Deployment stays stuck in this half-rolled-out state until `kubectl rollout undo` runs (or the underlying bug is fixed forward and a new revision is rolled out).

---

## Q5  3 AM alert: 10x burn rate on a 43-minute (0.1%) 30-day error budget

- 30-day budget = 43 minutes total, over 30 days = 720 hours.
- **Sustainable (1x) burn rate** = 43 / 720 ≈ **0.06 minutes/hour** (≈3.6 seconds/hour)  spend the budget evenly and it lasts exactly 30 days.
- **At 10x burn rate:** consumption = 10 × 0.06 ≈ **0.6 minutes/hour** (~36 seconds of budget every hour).
- **Time to exhaustion** (if sustained from a fully available budget): `30 days / burn_rate` = 30 / 10 = **3 days (72 hours)**. If part of the monthly budget is already spent, the remaining budget would be consumed proportionally sooner.
- **Response:** This maps directly to the `ErrorBudgetBurnRateHigh` alert (`severity: critical`, `observability/alerts.yaml`), which is designed to page immediately, at any hour, precisely because 3 days to exhaustion is far too fast to leave until morning. Immediate action:
  1. Acknowledge the page and open the `high-error-rate.md` runbook.
  2. Confirm current impact via PromQL (`order_service:availability_error_ratio:rate5m`, error breakdown by code/path)  a 10x burn rate this high likely also means the 1%-sustained-5-minutes `HighErrorRate` alert is firing or about to.
  3. Check for a correlated recent deploy; roll back if so.
  4. If not deploy-related, diagnose dependencies (DB pool, billing API) per the runbook.
  5. Do not wait for a "morning review"  a sustained 10x burn rate would blow through the entire monthly budget in 3 days, and if it's actually higher/bursty during the incident, exhaustion could be much sooner.
  6. Once mitigated, open a postmortem (`runbooks/postmortem-template.md`) since this crossed the `critical` burn-rate threshold.

---

## Q6  Why a 4-core CPU limit is wrong on a shared GKE cluster

**The problem:** CPU `limits` in Kubernetes are enforced via the Linux **CFS bandwidth controller (quota)**, not by reserving physical cores. Setting `cpu limit: 4` does not guarantee 4 dedicated cores  it only sets an upper *throttling* ceiling, while the CPU **request** is what the scheduler uses to reserve capacity and bin-pack pods onto nodes.

Consequences of "just raise the limit so it's never throttled":
- If `requests.cpu` stays small/unset while `limits.cpu` is large, the pod can *burst* up to 4 cores at the expense of other pods on the same node  creating exactly the noisy-neighbor problem the limit was meant to prevent for *this* service, now inflicted on others.
- CFS quota is enforced in discrete scheduling periods (default 100ms). A container can still get **throttled within a period** even if its *average* usage over a longer window is well under the limit  this causes intermittent tail-latency spikes that are hard to diagnose and are the opposite of "never throttled."
- A large limit wastes schedulable headroom for bin-packing and complicates capacity planning  the node has to assume this pod *might* use 4 cores even if it typically uses 0.25.
- It doesn't provide the guarantee the colleague thinks it does; it addresses the wrong lever entirely.

**What to configure instead:**
- Set an accurate **`requests.cpu`** based on measured typical usage (e.g., `250m`)  this is what actually reserves scheduling capacity and is what the HPA's CPU-utilization percentage is computed against.
- **Omit the CPU `limit` entirely** (or set it only modestly above the request, not to a whole node's worth of cores). Running CPU-`Burstable` without a hard CPU ceiling is a well-established SRE practice for latency-sensitive services: it avoids CFS throttling while the CPU *request* + the kernel's relative CPU shares still prevent one pod from permanently starving others.
- Keep a **memory `limit`**, since memory has no equivalent "throttle and continue" behavior  exceeding it triggers an OOM kill, so a hard ceiling is the correct tool there (unlike CPU).
- Let the **HPA** (CPU/memory utilization-based, `k8s/hpa.yaml`) and **cluster autoscaler** handle real load growth by adding replicas/nodes, rather than over-provisioning one pod's ceiling.

---

## Q7  Canary deployment using only the existing Kubernetes + CI/CD setup

No service mesh / Argo Rollouts / Flagger  traffic splitting is approximated via **replica-count ratio** behind a single Kubernetes `Service`, which load-balances round-robin across all matching, Ready pod endpoints.

**Setup**
- Two Deployments share the same Service selector (`app: order-service`): `order-service-stable` and `order-service-canary`, distinguished by an additional `track: stable` / `track: canary` label that is *not* part of the Service's selector.
- Total desired replica count stays constant during the canary window; **canary replicas ≈ 5% of the total**, e.g. 19 stable + 1 canary out of 20 → new pods receive ~5% of Service traffic via round-robin.
- The canary Deployment is kept at a **fixed replica count** during the test window (not attached to the HPA), so the ~5% ratio stays predictable; the stable Deployment keeps its normal HPA.

**Pipeline flow (extends `.github/workflows/deploy.yml`'s `deploy-production` job)**
1. After the existing manual-approval gate, deploy the new image as `order-service-canary` at ~5% of current total replicas (`kubectl apply` + `kubectl rollout status` to confirm it's Ready) instead of updating `order-service-stable` directly.
2. **Automated analysis window** (e.g., 10 minutes): a CI step polls Prometheus for the canary's own error rate, scoped by pod label:
   ```promql
   sum(rate(http_requests_total{pod=~"order-service-canary-.*", code=~"5.."}[5m]))
     / sum(rate(http_requests_total{pod=~"order-service-canary-.*"}[5m]))
   ```
3. **Auto-rollback:** if that ratio exceeds 1% at any check during the window, immediately scale `order-service-canary` to 0 (or delete it)  100% of traffic reverts to the unaffected `order-service-stable` pods, no manual step needed for this path.
4. **Auto-promote:** if the error rate stays under 1% for the full window, update `order-service-stable`'s image to the new version and let its normal `RollingUpdate` (zero-downtime, same as today) roll it out fully; then scale `order-service-canary` back to 0.
5. The existing `PodDisruptionBudget` selector is loosened to match `app: order-service` (both tracks) so voluntary disruptions never remove too much combined capacity while two Deployments are temporarily running side by side.

This reuses only what's already in the repo (Kubernetes Deployments/Services, the existing HPA/PDB, and GitHub Actions), at the cost of the traffic split being an approximation (round-robin over replica ratio, not exact per-request weighting) rather than a true weighted/header-based canary.

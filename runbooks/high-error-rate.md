# Runbook: HighErrorRate

## Alert context

- **Fires when:** `order_service:availability_error_ratio:rate5m > 0.01` for 5 minutes (>1% of requests returning 5xx).
- **Severity:** `critical`
- **SLO impact:** Directly burns the 99.9% availability error budget (30-day budget = ~43 minutes of downtime-equivalent). See `observability/alerts.yaml` and `ANSWERS.md` Q5.
- **User impact:** A visible share of order-processing requests are failing. Depending on which endpoints are affected, users may see failed checkouts, failed order status updates, or failed billing calls. Retries from clients may amplify load further.

---

## Step 1 — Confirm scope and impact (PromQL)

Run these against Prometheus / Grafana before touching anything:

```promql
# Current error ratio and trend
order_service:availability_error_ratio:rate5m

# Error rate broken down by status code — which code is dominant?
sum by (code) (rate(http_requests_total{job="order-service"}[5m]))

# Is it one endpoint/path or everything?
sum by (path, code) (rate(http_requests_total{job="order-service", code=~"5.."}[5m]))

# Is latency also degraded (errors from timeouts)?
order_service:latency_p99:rate10m

# Is the DB pool a likely cause?
1 - (sum(db_pool_open_connections{job="order-service"}) / sum(db_pool_max_connections{job="order-service"}))
```

Answer, in order:
1. Is this global or isolated to a subset of pods/nodes/zones?
2. Did it start right after a deploy (check the last `kubectl rollout history`)?
3. Is it correlated with a dependency (PostgreSQL, billing API) rather than the app itself?

## Step 2 — Diagnose with `kubectl`

```bash
# Are pods healthy / ready?
kubectl get pods -n order-service -o wide

# Any recent restarts / crash loops?
kubectl get pods -n order-service --sort-by=.status.containerStatuses[0].restartCount

# Recent events (OOMKilled, failed probes, scheduling issues)
kubectl get events -n order-service --sort-by=.lastTimestamp | tail -n 50

# Logs from the pods currently serving errors
kubectl logs -n order-service deploy/order-service --tail=200 --since=10m

# Rollout status / history — did a bad deploy cause this?
kubectl rollout status deployment/order-service -n order-service
kubectl rollout history deployment/order-service -n order-service

# Is the DB reachable? (exec into a pod)
kubectl exec -n order-service deploy/order-service -- sh -c 'nc -zv $DB_HOST 5432'
```

## Step 3 — Identify likely cause

| Symptom | Likely cause |
|---|---|
| Errors started right after a new revision rolled out | Bad deploy (regression, bad config, missing secret) |
| `OOMKilled` events, restart count climbing | Memory limit too low / memory leak |
| DB pool near exhaustion alert also firing | PostgreSQL saturation, slow queries, connection leak |
| 5xx correlated with billing API timeouts in logs | External billing API degradation |
| Errors across all pods simultaneously, no recent deploy | Shared dependency (Cloud SQL, network) issue |

## Step 4 — Resolution steps (least → most disruptive)

1. **Do nothing rash for the first minute.** Confirm this isn't a known, already-mitigating transient blip (check for an in-flight HPA scale-up event).
2. **If a recent deploy correlates:** roll back immediately —
   ```bash
   kubectl rollout undo deployment/order-service -n order-service
   kubectl rollout status deployment/order-service -n order-service --timeout=5m
   ```
3. **If it's a single/few unhealthy pods (not all):** delete them to force a fresh, ready replacement — the Deployment/ReplicaSet recreates them and the readiness probe keeps bad ones out of rotation:
   ```bash
   kubectl delete pod -n order-service <pod-name>
   ```
4. **If the DB connection pool is exhausted:** check for a long-running query or lock in PostgreSQL (Cloud SQL Insights / `pg_stat_activity`); kill the offending query as a last resort before restarting the app.
5. **If the external billing API is degraded:** verify with their status page; if the app doesn't already have a circuit breaker/timeout around billing calls, this is a follow-up hardening item — for now, this is largely outside your direct control, so focus on containing blast radius (e.g., temporarily increasing client-facing timeouts, if that keeps user-facing errors from cascading).
6. **If everything looks healthy at the pod level but errors persist:** scale out capacity as a stopgap while investigating —
   ```bash
   kubectl scale deployment/order-service -n order-service --replicas=<higher-number>
   ```
   (Note: the HPA will fight a manual scale down, but scaling up manually is safe and the HPA will simply take over afterward.)
7. **Most disruptive — full restart:** only if nothing above resolves it and you suspect a stuck/deadlocked process across all pods:
   ```bash
   kubectl rollout restart deployment/order-service -n order-service
   ```

## Step 5 — Verify resolution

```bash
# Error ratio back under 1%?
order_service:availability_error_ratio:rate5m

# All pods ready?
kubectl get pods -n order-service
```
Watch for 10-15 minutes before declaring the incident mitigated (avoid closing out on a transient dip).

## Escalation path and criteria

- **Escalate immediately (page secondary on-call)** if:
  - Error ratio > 5% and rising, or
  - Rollback does not resolve the issue within 10 minutes, or
  - Root cause appears to be Cloud SQL itself (failover, corruption, unreachable primary).
- **Escalate to the database/platform team** if the DB connection pool / PostgreSQL is the root cause and requires instance-level intervention (failover, scaling tier, maintenance).
- **Notify stakeholders (#incidents channel)** once severity is confirmed `critical` and impact is customer-visible, regardless of whether escalation is needed yet.
- **Open a postmortem** (see `runbooks/postmortem-template.md`) for any incident that paged on `HighErrorRate` or breached >5% error rate for more than 5 minutes.

# Postmortem: <Incident Title>

> Blameless postmortem. The goal is to understand systemic causes and
> improve the system/process, not to assign individual blame.

## Incident summary

| Field | Value |
|---|---|
| Title | |
| Date | |
| Duration | (detection → resolution) |
| Severity | (critical / high / medium / low) |
| On-call engineer(s) | |
| Incident commander | |
| Services affected | order-service / PostgreSQL / billing API |

## Timeline

All times in UTC.

| Time | Event |
|---|---|
| T+00:00 | (First user/system impact begins) |
| T+00:00 | Alert fired: `<AlertName>` |
| T+00:00 | On-call acknowledged |
| T+00:00 | Diagnosis started |
| T+00:00 | Mitigating action taken: `<action>` |
| T+00:00 | Error rate / latency returned to baseline |
| T+00:00 | Incident declared resolved |

**Detection → Mitigation:** `<X minutes>`
**Mitigation → Resolution:** `<X minutes>`
**Total incident duration:** `<X minutes>`

## Root cause analysis (5 Whys)

1. **Why did the incident happen?**
   -
2. **Why did that happen?**
   -
3. **Why did that happen?**
   -
4. **Why did that happen?**
   -
5. **Why did that happen (root cause)?**
   -

## Impact

- **Users affected:** (number/percentage of requests, or "all order-service traffic")
- **User-visible symptoms:** (e.g., failed order submissions, elevated checkout latency)
- **SLO / error budget burned:**
  - Availability SLO error budget consumed: `<X minutes>` of the 30-day 43-minute budget (`<X%>`)
  - Latency SLO impact: (yes/no, detail)
- **Revenue / business impact (if known):**

## Action items

| Action | Owner | Due date | Priority |
|---|---|---|---|
| | | | |
| | | | |

## Lessons learned

**What went well:**
-

**What went poorly:**
-

**Where we got lucky:**
-

**Follow-up needed (monitoring/alerting/runbook gaps surfaced by this incident):**
-

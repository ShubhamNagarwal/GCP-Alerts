# Alerts Reference

Complete reference for all 8 alerts in this repo.

## 1. Compute Engine — Active Instances Exceed 50

| Property | Value |
|----------|-------|
| **Type** | Cloud Monitoring (metric) |
| **Severity** | CRITICAL |
| **Metric** | `compute.googleapis.com/instance/uptime` |
| **Resource** | `gce_instance` |
| **Threshold** | Instance count > 50 |
| **Definition** | [`monitoring-alerts/compute-instances-exceed-50.json`](../monitoring-alerts/compute-instances-exceed-50.json) |

**Why:** Catches abnormal instance growth. In March 2026, GKE autoscaled from 52 → 1,945 instances.

---

## 2. Cloud Logging — k8s Container Logs Exceed 100 GB/day

| Property | Value |
|----------|-------|
| **Type** | Cloud Monitoring (metric) |
| **Severity** | CRITICAL |
| **Metric** | `logging.googleapis.com/billing/bytes_ingested` |
| **Filter** | `metric.labels.resource_type="k8s_container"` |
| **Threshold** | 107,374,182,400 bytes (100 GB) |
| **Definition** | [`monitoring-alerts/k8s-container-logs-100gb.json`](../monitoring-alerts/k8s-container-logs-100gb.json) |

**Why:** k8s_container logs accounted for 93% of the March logging cost spike (+$3,190).

---

## 3. Cloud Logging — Daily Ingestion Exceeds 500 GB

| Property | Value |
|----------|-------|
| **Type** | Cloud Monitoring (metric) |
| **Severity** | CRITICAL |
| **Metric** | `logging.googleapis.com/billing/bytes_ingested` (all sources) |
| **Threshold** | 536,870,912,000 bytes (500 GB) |
| **Definition** | [`monitoring-alerts/total-log-ingestion-500gb.json`](../monitoring-alerts/total-log-ingestion-500gb.json) |

**Why:** Catches ingestion spikes from any source not specific to k8s.

---

## 4. GKE — Node Count Exceeds 20

| Property | Value |
|----------|-------|
| **Type** | Cloud Monitoring (metric) |
| **Severity** | WARNING |
| **Metric** | `kubernetes.io/node/cpu/allocatable_cores` |
| **Resource** | `k8s_node` |
| **Threshold** | Node count > 20 |
| **Definition** | [`monitoring-alerts/gke-node-count-20.json`](../monitoring-alerts/gke-node-count-20.json) |

**Why:** GKE autoscaler is the root cause of cascading cost spikes. Early warning of scaling events.

---

## 5. Network Egress — Daily Exceeds 500 GB

| Property | Value |
|----------|-------|
| **Type** | Cloud Monitoring (metric) |
| **Severity** | WARNING |
| **Metric** | `compute.googleapis.com/instance/network/sent_bytes_count` |
| **Threshold** | 536,870,912,000 bytes (500 GB) |
| **Definition** | [`monitoring-alerts/network-egress-500gb.json`](../monitoring-alerts/network-egress-500gb.json) |

**Why:** Egress jumped from 2.9 TB to 9.4 TB in March 2026; March 22 alone hit 1,800 GB in one day.

---

## 6. IAM Audit Config Change — SetIamPolicy

| Property | Value |
|----------|-------|
| **Type** | Cloud Monitoring (log-based) |
| **Severity** | CRITICAL |
| **Filter** | `protoPayload.methodName="SetIamPolicy" AND protoPayload.request.policy.auditConfigs:*` |
| **Definition** | [`monitoring-alerts/iam-audit-config-change.json`](../monitoring-alerts/iam-audit-config-change.json) |

**Why:** Modifications to Data Access audit log configuration can cause massive Cloud Logging cost increases if DATA_READ/DATA_WRITE are re-enabled for all services.

---

## 7. VM Lifecycle & Configuration Changes

| Property | Value |
|----------|-------|
| **Type** | Log Router → Pub/Sub → Cloud Function |
| **Severity** | CRITICAL / HIGH / MEDIUM |
| **Sink** | `vm-change-alerts` |
| **Topic** | `vm-alerts` |
| **Function** | [`cloud-functions/vm-alert-to-slack/`](../cloud-functions/vm-alert-to-slack/) |

### Methods Captured

**Lifecycle:**
- `v1.compute.instances.start` → STARTED (HIGH)
- `v1.compute.instances.stop` → STOPPED (CRITICAL)
- `v1.compute.instances.delete` → DELETED (CRITICAL)
- `v1.compute.instances.reset` → RESTARTED (HIGH)
- `v1.compute.instances.insert` → CREATED (HIGH)

**Configuration:**
- `setMachineType`, `attachDisk`, `detachDisk`, `setMetadata`,
  `setServiceAccount`, `updateNetworkInterface`, `setLabels`, `setTags` → all MEDIUM

### Filter Notes

- **Service accounts excluded:** `NOT protoPayload.authenticationInfo.principalEmail=~"gserviceaccount.com"` filters out GKE autoscaler noise.
- **Deduplication:** `operation.last=true` ensures one alert per action (GCP creates two log entries per operation).

---

## 8. Billing Budget Alert

| Property | Value |
|----------|-------|
| **Type** | GCP Budget → Pub/Sub → Cloud Function |
| **Severity** | DYNAMIC (based on budget usage) |
| **Topic** | `billing-alerts` |
| **Function** | [`cloud-functions/billing-alert-to-slack/`](../cloud-functions/billing-alert-to-slack/) |

### Severity Levels

| Budget Usage | Severity | Color |
|--------------|----------|-------|
| >= 100% | CRITICAL | Red |
| >= 90% | HIGH | Orange |
| >= 75% | MEDIUM | Yellow |
| < 75% | INFO | Green |

### Information Displayed in Slack

- Billing period (month start → current date)
- Days elapsed
- Actual MTD spend
- Budget limit, used %, remaining
- Daily run rate
- Projected month-end cost

---

## Notification Channel

All alerts route to a single Slack channel via a Cloud Monitoring notification channel:
- **Channel Type:** Slack
- **Slack Channel:** `#GCP-Alerts-Nonprod` (configurable)
- **Email Notifications:** Disabled

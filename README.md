<div align="center">

# GCP Alert Hub

### Slack-first GCP monitoring & alerting for cost spikes, VM changes, and billing.

Eight production alerts. Three pipelines. One Slack channel.
Built after a **+65% cost spike** in March 2026 to make sure the next one is caught in hours, not on the next month's bill.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Python](https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white)](https://www.python.org/)
[![Google Cloud](https://img.shields.io/badge/Google%20Cloud-Functions%20Gen2-4285F4?logo=googlecloud&logoColor=white)](https://cloud.google.com/functions)
[![Cloud Monitoring](https://img.shields.io/badge/Cloud%20Monitoring-Alert%20Policies-34A853?logo=googlecloud&logoColor=white)](https://cloud.google.com/monitoring)
[![Pub/Sub](https://img.shields.io/badge/Pub%2FSub-Topics-FBBC04?logo=googlecloud&logoColor=white)](https://cloud.google.com/pubsub)
[![Slack](https://img.shields.io/badge/Slack-Webhooks-4A154B?logo=slack&logoColor=white)](https://api.slack.com/messaging/webhooks)
[![Status](https://img.shields.io/badge/status-production-success)](#)

[Quickstart](#quickstart) ·
[Architecture](#architecture) ·
[Alerts](#alerts-included) ·
[Sample output](#sample-slack-notifications) ·
[Docs](#documentation) ·
[Why](#why-this-exists)

</div>

---

## Highlights

- **8 production alerts** across compute, GKE, logging, network egress, IAM, VM lifecycle, and billing.
- **Slack-only delivery** with severity colors, action emojis, deep links, and full incident context.
- **Three independent pipelines** (Cloud Monitoring, Log Router to Cloud Function, Budget to Cloud Function), all funneling into one channel.
- **VM change attribution** - captures *who* did *what* (start / stop / delete / restart / config change) with timestamp, zone, and project.
- **Smart deduplication** using `operation.last=true` so each action fires exactly one Slack message.
- **GKE autoscaler noise filtered** by excluding `gserviceaccount.com` principals - only human actions trigger alerts.
- **Billing intelligence** - actual MTD spend, daily run rate, projected month-end cost, and dynamic severity (75 / 90 / 100% thresholds).

---

## Table of contents

1. [Architecture](#architecture)
2. [Alerts included](#alerts-included)
3. [Quickstart](#quickstart)
4. [Repository layout](#repository-layout)
5. [Sample Slack notifications](#sample-slack-notifications)
6. [Documentation](#documentation)
7. [Why this exists](#why-this-exists)
8. [License](#license)

---

## Architecture

The idea is simple: **GCP detects something, the event reaches a Cloud Function or a Notification Channel, and a Slack message is posted.**

```
   GCP   ───►   Pipeline   ───►   Slack
```

There are three pipelines, each handling a different kind of event. All three end up in the same Slack channel.

### Pipeline 1 - Metric alerts (the simplest one)

Used for: instance count, GKE nodes, log volume, network egress, IAM config changes.

```
GCP Metric  ─►  Cloud Monitoring Alert Policy  ─►  Slack Notification Channel  ─►  Slack
```

GCP already collects the metrics. We just create an alert policy that says "fire when value > threshold" and point it at a Slack notification channel.

### Pipeline 2 - VM change alerts (audit logs)

Used for: VM start, stop, delete, restart, machine-type change, disk attach/detach, IAM changes on VMs.

```
VM Audit Log  ─►  Log Router Sink  ─►  Pub/Sub topic  ─►  Cloud Function  ─►  Slack
```

GCP writes an audit log every time someone touches a VM. A Log Router sink filters those logs and pushes them into a Pub/Sub topic. A Cloud Function reads the topic, extracts *who did what*, and posts a formatted message to Slack.

We use a Cloud Function (instead of a plain notification channel) because we want a rich message with the user's email, the action, the VM name, and a deep link. A native alert can't do that.

### Pipeline 3 - Billing alerts

Used for: monthly budget thresholds (75%, 90%, 100%).

```
GCP Budget  ─►  Pub/Sub topic  ─►  Cloud Function  ─►  Slack
```

GCP Budgets natively publish to a Pub/Sub topic when a threshold is crossed. A Cloud Function reads the message, calculates the daily run rate and projected month-end spend, and posts a Slack message with a severity color (green / yellow / orange / red) based on usage %.

### Why this split?

| Need | Pipeline used | Reason |
|------|---------------|--------|
| Threshold on a metric | Pipeline 1 | Cloud Monitoring already supports it. No code needed. |
| Rich message with user attribution | Pipeline 2 | Native alerts can't read fields out of an audit log. We need code. |
| Billing with projections | Pipeline 3 | Native budget alerts only show "you crossed 90%". We add run-rate and projection. |

Full design and trade-offs: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## Alerts included

| # | Alert | Type | Severity |
|---|-------|------|:--------:|
| 1 | Compute Engine - Active instances exceed 50 | Metric | `CRITICAL` |
| 2 | Cloud Logging - k8s container logs > 100 GB/day | Metric | `CRITICAL` |
| 3 | Cloud Logging - Daily ingestion > 500 GB | Metric | `CRITICAL` |
| 4 | GKE - Node count exceeds 20 | Metric | `WARNING` |
| 5 | Network egress - Daily > 500 GB | Metric | `WARNING` |
| 6 | IAM audit-config change (`SetIamPolicy`) | Log-based | `CRITICAL` |
| 7 | VM lifecycle & configuration changes | Pipeline | `CRITICAL / HIGH / MEDIUM` |
| 8 | Billing budget alerts | Pipeline | `DYNAMIC` (INFO to CRITICAL) |

Full reference for every alert (metric, filter, threshold, JSON definition): [`docs/ALERTS.md`](docs/ALERTS.md).

---

## Quickstart

> Goal: get every alert deployed against your GCP project, posting to your Slack channel, in under 10 minutes.

### Prerequisites

| Tool / Resource | Why |
|-----------------|-----|
| GCP project with billing enabled | Hosts the alerts and Cloud Functions |
| `gcloud` CLI authenticated | Deploys everything |
| Slack incoming webhook URL | Destination for all alerts ([create one](https://api.slack.com/messaging/webhooks)) |
| Slack notification channel ID (Cloud Monitoring) | Used by metric alerts |
| IAM roles: `roles/monitoring.editor`, `roles/logging.admin`, `roles/cloudfunctions.developer`, `roles/pubsub.editor` | To create alerts, sinks, topics, functions |

### 1. Set environment variables

```bash
export GCP_PROJECT_ID="your-project-id"
export GCP_REGION="us-central1"
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/XXX/YYY/ZZZ"
export SLACK_CHANNEL_ID="your-monitoring-channel-id"
```

### 2. Deploy everything

```bash
./scripts/deploy-all.sh
```

Or deploy each pipeline individually:

```bash
./scripts/deploy-monitoring-alerts.sh   # 6 metric alerts
./scripts/deploy-vm-alerts.sh           # VM change pipeline
./scripts/deploy-billing-alerts.sh      # Billing budget pipeline
```

### 3. Smoke test

```bash
./scripts/test-billing-alert.sh
./scripts/test-vm-alert.sh
```

Step-by-step deployment + troubleshooting: [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md), [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md).

---

## Repository layout

```
gcp-alert-hub/
├── README.md
├── LICENSE
├── .gitignore
├── .env.example
│
├── cloud-functions/
│   ├── billing-alert-to-slack/    # Budget to Slack with projections
│   │   ├── main.py
│   │   ├── requirements.txt
│   │   └── README.md
│   └── vm-alert-to-slack/         # VM audit logs to Slack
│       ├── main.py
│       ├── requirements.txt
│       └── README.md
│
├── monitoring-alerts/             # JSON definitions for the 6 metric alerts
│   ├── compute-instances-exceed-50.json
│   ├── k8s-container-logs-100gb.json
│   ├── total-log-ingestion-500gb.json
│   ├── gke-node-count-20.json
│   ├── network-egress-500gb.json
│   └── iam-audit-config-change.json
│
├── scripts/
│   ├── deploy-all.sh
│   ├── deploy-monitoring-alerts.sh
│   ├── deploy-vm-alerts.sh
│   ├── deploy-billing-alerts.sh
│   ├── test-billing-alert.sh
│   └── test-vm-alert.sh
│
├── docs/
│   ├── ALERTS.md             # Detailed alert reference
│   ├── ARCHITECTURE.md       # System architecture
│   ├── DEPLOYMENT.md         # Step-by-step deployment guide
│   ├── TROUBLESHOOTING.md    # Common issues and fixes
│   └── COST_CONTEXT.md       # The incident that prompted this repo
│
└── examples/
    └── sample-payloads/
        ├── budget-alert.json
        └── vm-audit-log.json
```

---

## Sample Slack notifications

### VM lifecycle change

```text
GCP VM Alert  -  HIGH

VM STARTED
==============================
VM Name      :  testing-instance
Action       :  STARTED
Category     :  Lifecycle Change
Done By      :  user@company.com
Time         :  Apr 03, 2026 12:13:32 UTC
Zone         :  us-central1-b
Project      :  your-project-id

View VM in Console
```

### Billing alert (under threshold)

```text
GCP Budget Alert  -  INFO

Current Month Billing Status
==============================
Billing Period   :  Apr 01, 2026  to  Apr 03, 2026
Days Elapsed     :  2 of ~30 days

Actual Amount from GCP Billing
==============================
Actual Spend (MTD)  :  $295.02 USD
Budget Limit        :  $7,000.00 USD
Budget Used         :  4.2%
Remaining Budget    :  $6,704.98 USD

Projections
==============================
Daily Run Rate      :  $147.51 / day
Projected Month-End :  $4,425.30 USD
```

### Severity color coding (billing)

| Budget used | Severity | Slack color |
|:-----------:|:--------:|:-----------:|
| `< 75%`  | `INFO`     | green |
| `>= 75%` | `MEDIUM`   | yellow |
| `>= 90%` | `HIGH`     | orange |
| `>= 100%`| `CRITICAL` | red |

---

## Documentation

| Doc | What's inside |
|-----|---------------|
| [`docs/ALERTS.md`](docs/ALERTS.md) | Every alert: metric, filter, threshold, JSON definition |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Three-pipeline design and rationale |
| [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) | Step-by-step deployment runbook |
| [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) | Common issues and fixes |
| [`docs/COST_CONTEXT.md`](docs/COST_CONTEXT.md) | The March 2026 incident that prompted this repo |
| [`cloud-functions/billing-alert-to-slack/README.md`](cloud-functions/billing-alert-to-slack/README.md) | Billing function details |
| [`cloud-functions/vm-alert-to-slack/README.md`](cloud-functions/vm-alert-to-slack/README.md) | VM function details |
| [`examples/README.md`](examples/README.md) | Sample payloads + manual test recipes |

---

## Why this exists

In **March 2026**, the `satschel-nonprod` GCP project bill jumped **+65%** (from **$6,741** to **$11,149**) driven by a GKE autoscaling cascade:

| Service | Normal | March peak | Multiplier |
|---------|-------:|-----------:|:----------:|
| Compute instances | 52 | 1,945 | **37x** |
| Cloud Logging (k8s_container) | 644 GB/mo | 7 TB/mo | **11x** |
| Network egress | 2.9 TB/mo | 9.4 TB/mo | **3.2x** |
| Network egress (single day) | ~100 GB | 1,800 GB (Mar 22) | **18x** |

Logging alone accounted for **93%** of the cost increase, because every additional container produced proportional log volume.

This repo is the alerting we wished we had **before** that incident: early-warning signals for every layer that contributed to the spike, plus VM attribution and billing projections so the next incident is caught in hours.

Full incident analysis and lessons: [`docs/COST_CONTEXT.md`](docs/COST_CONTEXT.md).

---

## License

Released under the [MIT License](LICENSE). Use it freely inside your organization or as a starting point for your own alerting layer. Attribution appreciated but not required.

---

<div align="center">

Built by [**Shubham Nagarwal**](https://github.com/ShubhamNagarwal)

If this saved your team a 65% cost spike, star the repo.

</div>

# GCP Alert Hub

A complete GCP monitoring and alerting solution with **Slack-first notifications**. Built to detect cost spikes, infrastructure changes, and security events in real time.

> Implemented for `satschel-nonprod` after a 65% cost spike in March 2026 ($6,741 → $11,149) triggered by GKE autoscaling. All alerts route exclusively to Slack — no email noise.

---

## Features

- **8 Production Alerts** covering compute, logging, network, security, and billing
- **Slack-only notifications** with rich formatting (severity colors, action emojis, full context)
- **VM change detection** — captures who did what (start/stop/delete/restart/config changes)
- **Smart deduplication** — one notification per action (uses `operation.last=true`)
- **GKE autoscaler filtering** — excludes service account noise, only human actions trigger alerts
- **Billing intelligence** — actual MTD spend, daily run rate, projected month-end cost
- **Dynamic severity levels** based on budget usage thresholds (75/90/100%)

---

## Architecture

```
GCP Metrics ──────► Cloud Monitoring Alert Policy ──┐
                                                    │
GCP Audit Logs ──► Log Router Sink ──► Pub/Sub ─────┼──► Cloud Function ──► Slack
                                                    │
GCP Budget ─────────────────────────► Pub/Sub ──────┘    #GCP-Alerts-Nonprod
```

Three pipelines, one destination:

| Pipeline | Use Case | Triggers |
|----------|----------|----------|
| **Cloud Monitoring** | Threshold-based metric alerts | Compute, GKE, Logging, Egress |
| **Log Router → Cloud Function** | Detailed audit log alerts | VM changes, IAM changes |
| **Budget → Cloud Function** | Billing alerts with projections | Monthly budget thresholds |

---

## Quickstart

### Prerequisites

- GCP project with billing enabled
- `gcloud` CLI authenticated
- Slack workspace with an incoming webhook URL
- IAM roles: `roles/monitoring.editor`, `roles/logging.admin`, `roles/cloudfunctions.developer`, `roles/pubsub.editor`

### 1. Set environment variables

```bash
export GCP_PROJECT_ID="your-project-id"
export GCP_REGION="us-central1"
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/XXX/YYY/ZZZ"
export SLACK_CHANNEL_ID="your-monitoring-channel-id"  # GCP notification channel
```

### 2. Deploy everything

```bash
./scripts/deploy-all.sh
```

Or deploy individually:

```bash
./scripts/deploy-monitoring-alerts.sh   # 6 metric alerts
./scripts/deploy-vm-alerts.sh           # VM change pipeline
./scripts/deploy-billing-alerts.sh      # Billing budget pipeline
```

### 3. Test

```bash
./scripts/test-billing-alert.sh
./scripts/test-vm-alert.sh
```

---

## Alerts Included

| # | Alert | Type | Severity |
|---|-------|------|----------|
| 1 | Compute Engine — Active Instances Exceed 50 | Metric | CRITICAL |
| 2 | Cloud Logging — k8s Container Logs > 100 GB/day | Metric | CRITICAL |
| 3 | Cloud Logging — Daily Ingestion > 500 GB | Metric | CRITICAL |
| 4 | GKE — Node Count Exceeds 20 | Metric | WARNING |
| 5 | Network Egress — Daily Exceeds 500 GB | Metric | WARNING |
| 6 | IAM Audit Config Change — SetIamPolicy | Log-based | CRITICAL |
| 7 | VM Lifecycle & Configuration Changes | Pipeline | CRITICAL |
| 8 | Billing Budget Alerts | Pipeline | DYNAMIC |

See [docs/ALERTS.md](docs/ALERTS.md) for full details on each alert.

---

## Repository Layout

```
gcp-alert-hub/
├── README.md
├── LICENSE
├── .gitignore
│
├── cloud-functions/
│   ├── billing-alert-to-slack/    # Budget → Slack with projections
│   │   ├── main.py
│   │   ├── requirements.txt
│   │   └── README.md
│   └── vm-alert-to-slack/         # VM audit logs → Slack
│       ├── main.py
│       ├── requirements.txt
│       └── README.md
│
├── monitoring-alerts/             # JSON definitions for all metric alerts
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
│   ├── ALERTS.md             # Detailed alert documentation
│   ├── ARCHITECTURE.md       # System architecture
│   ├── DEPLOYMENT.md         # Step-by-step deployment guide
│   ├── TROUBLESHOOTING.md    # Common issues and fixes
│   └── COST_CONTEXT.md       # Why these alerts exist
│
└── examples/
    ├── slack-message-vm-alert.png
    ├── slack-message-billing.png
    └── sample-payloads/
        ├── budget-alert.json
        └── vm-audit-log.json
```

---

## Sample Slack Notifications

### VM Lifecycle Change
```
⚠️ GCP VM Alert - HIGH

▶️ VM STARTED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
VM Name:     testing-instance
Action:      STARTED
Category:    Lifecycle Change
Done By:     user@company.com
Time:        Apr 03, 2026 12:13:32 UTC
Zone:        us-central1-b
Project:     your-project-id

🔗 View VM in Console
```

### Billing Alert
```
✅ GCP Budget Alert - INFO

📅 Current Month Billing Status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Billing Period: Apr 01, 2026 → Apr 03, 2026
Days Elapsed:   2 of ~30 days

💰 Actual Amount from GCP Billing
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Actual Spend (MTD):  $295.02 USD
Budget Limit:        $7,000.00 USD
Budget Used:         4.2%
Remaining Budget:    $6,704.98 USD

📈 Projections
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Daily Run Rate:      $147.51/day
Projected Month-End: $4,425.30 USD
```

---

## Why This Exists

In March 2026, our `satschel-nonprod` GCP project bill jumped **+65%** ($6,741 → $11,149) due to GKE autoscaling cascading into log ingestion (644 GB → 7 TB), network egress (2.9 TB → 9.4 TB), and compute costs.

This repo provides the alerting we wished we had **before** that incident — early warning signals for every layer that contributed to the spike.

See [docs/COST_CONTEXT.md](docs/COST_CONTEXT.md) for the full incident analysis.

---

## License

MIT — see [LICENSE](LICENSE)

---

## Author

Built by [Shubham Nagarwal](https://github.com/ShubhamNagarwal) at Satschel.

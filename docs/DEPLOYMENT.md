# Deployment Guide

Step-by-step deployment of the GCP Alert Hub to a new project.

## Prerequisites

- GCP project with billing enabled
- `gcloud` CLI authenticated (`gcloud auth login`)
- Required APIs enabled (the deploy scripts will fail with helpful errors if any are missing):
  - `monitoring.googleapis.com`
  - `logging.googleapis.com`
  - `cloudfunctions.googleapis.com`
  - `pubsub.googleapis.com`
  - `cloudbuild.googleapis.com`
  - `eventarc.googleapis.com`
  - `run.googleapis.com`
- Slack workspace with an incoming webhook URL

## Step 1: Create a Slack Notification Channel in GCP

This is a one-time setup. The notification channel ID is reused by all metric alerts.

1. Go to **Cloud Monitoring → Alerting → Notification channels**
2. Click **Add new** → **Slack**
3. Authorize the GCP Slack app for your workspace
4. Select the channel (e.g. `#GCP-Alerts-Nonprod`)
5. Save and copy the **channel ID** (a long number like `15058480963135784543`)

## Step 2: Get a Slack Incoming Webhook URL

For the Cloud Functions (VM and billing pipelines), you need a separate webhook URL.

1. Go to https://api.slack.com/apps → **Create New App** → **From scratch**
2. Add **Incoming Webhooks** feature
3. Click **Add New Webhook to Workspace**, select your channel
4. Copy the webhook URL (starts with `https://hooks.slack.com/services/...`)

## Step 3: Set Environment Variables

```bash
export GCP_PROJECT_ID="your-project-id"
export GCP_REGION="us-central1"
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/XXX/YYY/ZZZ"
export SLACK_CHANNEL_ID="15058480963135784543"
export GCP_BILLING_ACCOUNT="012345-ABCDEF-678901"  # Optional, for billing report link
```

## Step 4: Deploy

### Option A: Deploy everything

```bash
./scripts/deploy-all.sh
```

### Option B: Deploy individually

```bash
./scripts/deploy-monitoring-alerts.sh   # 6 metric/log-based alerts
./scripts/deploy-vm-alerts.sh           # VM pipeline (sink + topic + function)
./scripts/deploy-billing-alerts.sh      # Billing pipeline (topic + function)
```

## Step 5: Connect GCP Budget to Pub/Sub

Budget alerts must be manually connected to the Pub/Sub topic (gcloud doesn't support this).

1. Go to **Billing → Budgets & alerts → [Your budget] → Edit**
2. Scroll to **Manage notifications**
3. Enable **Connect a Pub/Sub topic to this budget**
4. Project: `<your project>`
5. Topic: `billing-alerts`
6. Save

## Step 6: Test

```bash
./scripts/test-billing-alert.sh
./scripts/test-vm-alert.sh
```

Expected: Slack message received in your channel within ~10s.

## Verifying

```bash
# List monitoring alerts
gcloud monitoring policies list --project=$GCP_PROJECT_ID

# Check Cloud Function logs
gcloud functions logs read billing-alert-to-slack \
  --project=$GCP_PROJECT_ID --region=$GCP_REGION --limit=10

gcloud functions logs read vm-alert-to-slack \
  --project=$GCP_PROJECT_ID --region=$GCP_REGION --limit=10

# Verify Log Router sink
gcloud logging sinks describe vm-change-alerts --project=$GCP_PROJECT_ID
```

## Customizing

- **Thresholds:** Edit JSON files in [`monitoring-alerts/`](../monitoring-alerts/) before deploying. The default thresholds are tuned to detect anomalies relative to a ~$6,500/month baseline.
- **Slack formatting:** Edit `text` in `cloud-functions/*/main.py`.
- **Methods captured by VM pipeline:** Edit `SINK_FILTER` in `scripts/deploy-vm-alerts.sh` and `ACTION_MAP` in the Cloud Function.

## Removing

```bash
# Delete monitoring alert policies
for policy in $(gcloud monitoring policies list --format="value(name)"); do
    gcloud monitoring policies delete "$policy" --quiet
done

# Delete VM pipeline
gcloud functions delete vm-alert-to-slack --region=$GCP_REGION --quiet
gcloud logging sinks delete vm-change-alerts --quiet
gcloud pubsub topics delete vm-alerts --quiet

# Delete billing pipeline
gcloud functions delete billing-alert-to-slack --region=$GCP_REGION --quiet
gcloud pubsub topics delete billing-alerts --quiet
```

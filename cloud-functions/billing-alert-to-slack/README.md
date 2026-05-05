# billing-alert-to-slack

Cloud Function that receives GCP Budget Alert messages from Pub/Sub and sends a formatted notification to Slack with current month status, daily run rate, and projected month-end cost.

## Trigger

Pub/Sub topic: `billing-alerts`

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `SLACK_WEBHOOK_URL` | Yes | Slack incoming webhook URL |
| `GCP_PROJECT_ID` | No | Project ID for Slack message context |
| `GCP_BILLING_ACCOUNT` | No | Billing account ID for the report link |

## Deploy

```bash
gcloud functions deploy billing-alert-to-slack \
  --project=$GCP_PROJECT_ID \
  --region=us-central1 \
  --runtime=python312 \
  --trigger-topic=billing-alerts \
  --entry-point=billing_alert_to_slack \
  --source=. \
  --set-env-vars="SLACK_WEBHOOK_URL=$SLACK_WEBHOOK_URL,GCP_PROJECT_ID=$GCP_PROJECT_ID" \
  --gen2 \
  --memory=256MB \
  --timeout=60s
```

## Test

```bash
gcloud pubsub topics publish billing-alerts \
  --message='{"budgetDisplayName":"Test","costAmount":500,"budgetAmount":7000,"currencyCode":"USD","alertThresholdExceeded":0.07,"costIntervalStart":"2026-04-01T00:00:00Z"}'
```

## Severity Thresholds

| Budget Used | Severity | Color |
|-------------|----------|-------|
| >= 100% | CRITICAL | Red |
| >= 90% | HIGH | Orange |
| >= 75% | MEDIUM | Yellow |
| < 75% | INFO | Green |

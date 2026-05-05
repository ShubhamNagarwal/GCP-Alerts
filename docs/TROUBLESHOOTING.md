# Troubleshooting

Common issues and fixes.

## No Slack message received

### Step 1: Check Cloud Function logs

```bash
gcloud functions logs read vm-alert-to-slack \
  --project=$GCP_PROJECT_ID --region=us-central1 --limit=20

gcloud functions logs read billing-alert-to-slack \
  --project=$GCP_PROJECT_ID --region=us-central1 --limit=20
```

### Step 2: Look for these common errors

| Log Line | Meaning | Fix |
|----------|---------|-----|
| `Webhook HTTPError: 404 Not Found` body: `no_service` | Webhook URL invalid or app deleted | Regenerate webhook in Slack and redeploy with new `SLACK_WEBHOOK_URL` |
| `Webhook HTTPError: 403` | Slack app does not have permission to post | Re-authorize the app in Slack |
| `SLACK_WEBHOOK_URL not configured` | Env var missing | Redeploy with `--set-env-vars="SLACK_WEBHOOK_URL=..."` |
| `Error parsing event` | Pub/Sub data format unexpected | Check the Pub/Sub message manually with `gcloud pubsub subscriptions pull` |

## Webhook returns 404 / no_service

This happens when:
1. The Slack app was renamed or modified (which can rotate the webhook URL)
2. The webhook was manually deleted
3. The Slack workspace was changed

**Fix:** Get the new webhook URL from Slack (https://api.slack.com/apps → your app → Incoming Webhooks) and redeploy:

```bash
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/NEW/URL/HERE"
./scripts/deploy-vm-alerts.sh
./scripts/deploy-billing-alerts.sh
```

## Duplicate VM alerts

GCP creates two audit log entries per VM operation: one when the operation starts (`operation.first=true`) and one when it completes (`operation.last=true`). Without filtering, you'll get two alerts per action.

**Fix:** Make sure the Log Router sink filter includes:

```
AND operation.last=true
```

Verify with:
```bash
gcloud logging sinks describe vm-change-alerts --project=$GCP_PROJECT_ID
```

## VM alerts firing for GKE autoscaler

GKE creates/deletes nodes via the `service-PROJECT_NUMBER@container-engine-robot.iam.gserviceaccount.com` service account. These are normal cluster operations, not human changes.

**Fix:** Make sure the Log Router sink filter excludes service accounts:

```
AND NOT protoPayload.authenticationInfo.principalEmail=~"gserviceaccount.com"
```

## Cloud Monitoring alert not sending to Slack

```bash
gcloud monitoring policies list --format=json | python3 -c "
import json, sys
for p in json.load(sys.stdin):
    print(p['displayName'], '->', p.get('notificationChannels', []))
"
```

If a policy has no `notificationChannels` or the wrong one, update it:

```bash
POLICY_NAME="projects/$GCP_PROJECT_ID/alertPolicies/POLICY_ID"
curl -X PATCH \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  "https://monitoring.googleapis.com/v3/${POLICY_NAME}?updateMask=notificationChannels" \
  -d "{\"notificationChannels\":[\"projects/$GCP_PROJECT_ID/notificationChannels/$SLACK_CHANNEL_ID\"]}"
```

## Budget alert not received

GCP Budget alerts must be **manually connected** to the Pub/Sub topic. The deploy script doesn't do this because it requires Billing API permissions that often aren't granted.

1. Go to **Billing → Budgets & alerts → [Budget] → Edit**
2. Enable **Connect a Pub/Sub topic**
3. Select project + topic `billing-alerts`
4. Save

Then test by manually publishing to the topic:

```bash
./scripts/test-billing-alert.sh
```

## Useful Diagnostic Commands

```bash
# List all alert policies
gcloud monitoring policies list --project=$GCP_PROJECT_ID

# List notification channels
gcloud beta monitoring channels list --project=$GCP_PROJECT_ID

# Recent VM audit logs (raw)
gcloud logging read 'resource.type="gce_instance" AND
  protoPayload.methodName=~"instances.(start|stop|delete)"' \
  --project=$GCP_PROJECT_ID --limit=10

# Test Pub/Sub topic reachability
gcloud pubsub subscriptions create vm-alerts-debug \
  --topic=vm-alerts --project=$GCP_PROJECT_ID
gcloud pubsub subscriptions pull vm-alerts-debug --auto-ack \
  --project=$GCP_PROJECT_ID

# Check Cloud Function deployment status
gcloud functions describe vm-alert-to-slack \
  --region=us-central1 --project=$GCP_PROJECT_ID
```

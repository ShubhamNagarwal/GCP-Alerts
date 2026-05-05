# vm-alert-to-slack

Cloud Function that receives VM audit log entries via a Log Router sink → Pub/Sub, then sends a detailed Slack notification with VM name, action, who did it, and where.

## Architecture

```
GCP Audit Logs → Log Router Sink (vm-change-alerts)
              → Pub/Sub (vm-alerts)
              → This Cloud Function
              → Slack #GCP-Alerts-Nonprod
```

## Trigger

Pub/Sub topic: `vm-alerts`

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `SLACK_WEBHOOK_URL` | Yes | Slack incoming webhook URL |
| `GCP_PROJECT_ID` | No | Project ID fallback for Slack message |

## Events Detected

### Lifecycle (CRITICAL/HIGH severity)
- `v1.compute.instances.start` → STARTED
- `v1.compute.instances.stop` → STOPPED (CRITICAL)
- `v1.compute.instances.delete` → DELETED (CRITICAL)
- `v1.compute.instances.reset` → RESTARTED
- `v1.compute.instances.insert` → CREATED

### Configuration (MEDIUM severity)
- `setMachineType` → MACHINE TYPE CHANGED
- `attachDisk` / `detachDisk` → DISK ATTACHED/DETACHED
- `setMetadata` → METADATA CHANGED
- `setServiceAccount` → SERVICE ACCOUNT CHANGED
- `updateNetworkInterface` → NETWORK CHANGED
- `setLabels` → LABELS CHANGED
- `setTags` → FIREWALL TAGS CHANGED

## Deploy

```bash
gcloud functions deploy vm-alert-to-slack \
  --project=$GCP_PROJECT_ID \
  --region=us-central1 \
  --runtime=python312 \
  --trigger-topic=vm-alerts \
  --entry-point=vm_alert_to_slack \
  --source=. \
  --set-env-vars="SLACK_WEBHOOK_URL=$SLACK_WEBHOOK_URL,GCP_PROJECT_ID=$GCP_PROJECT_ID" \
  --gen2 \
  --memory=256MB \
  --timeout=60s
```

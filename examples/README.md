# Examples

## Sample Payloads

### `budget-alert.json`
The JSON shape that GCP Budget alerts publish to Pub/Sub. The Cloud Function uses these fields:
- `budgetDisplayName`, `costAmount`, `budgetAmount`, `currencyCode`
- `alertThresholdExceeded`, `costIntervalStart`

### `vm-audit-log.json`
A representative VM audit log entry routed through the Log Router → Pub/Sub → Cloud Function pipeline. Key fields:
- `protoPayload.methodName` — what action was performed
- `protoPayload.authenticationInfo.principalEmail` — who did it
- `protoPayload.resourceName` — the VM (last segment is the VM name)
- `resource.labels.zone`, `resource.labels.instance_id` — location & ID
- `operation.last=true` — only the completion log entry triggers a notification

## Manual Testing

Send a test payload through the pipeline:

```bash
# Billing pipeline
gcloud pubsub topics publish billing-alerts \
  --project=$GCP_PROJECT_ID \
  --message="$(cat examples/sample-payloads/budget-alert.json)"

# VM pipeline
gcloud pubsub topics publish vm-alerts \
  --project=$GCP_PROJECT_ID \
  --message="$(cat examples/sample-payloads/vm-audit-log.json)"
```

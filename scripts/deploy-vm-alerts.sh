#!/bin/bash
# Deploy the VM alert pipeline:
#   - Pub/Sub topic
#   - Log Router sink (audit logs -> Pub/Sub)
#   - Cloud Function (Pub/Sub -> Slack)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FN_DIR="$SCRIPT_DIR/../cloud-functions/vm-alert-to-slack"

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID is required}"
: "${GCP_REGION:=us-central1}"
: "${SLACK_WEBHOOK_URL:?SLACK_WEBHOOK_URL is required}"

TOPIC_NAME="vm-alerts"
SINK_NAME="vm-change-alerts"
FN_NAME="vm-alert-to-slack"

echo "==============================================================="
echo " Deploying VM Alert Pipeline"
echo "==============================================================="

# 1. Create Pub/Sub topic
echo "[1/3] Creating Pub/Sub topic: $TOPIC_NAME"
gcloud pubsub topics create "$TOPIC_NAME" --project="$GCP_PROJECT_ID" 2>/dev/null \
    || echo "      Topic already exists, skipping."

# 2. Create Log Router sink
echo "[2/3] Creating Log Router sink: $SINK_NAME"
SINK_FILTER='resource.type="gce_instance" AND protoPayload.methodName=~"(v1.compute.instances.start|v1.compute.instances.stop|v1.compute.instances.delete|v1.compute.instances.reset|v1.compute.instances.insert|v1.compute.instances.setMachineType|v1.compute.instances.attachDisk|v1.compute.instances.detachDisk|v1.compute.instances.setMetadata|v1.compute.instances.setServiceAccount|v1.compute.instances.updateNetworkInterface|v1.compute.instances.setLabels|v1.compute.instances.setTags)" AND NOT protoPayload.authenticationInfo.principalEmail=~"gserviceaccount.com" AND operation.last=true'

gcloud logging sinks create "$SINK_NAME" \
    "pubsub.googleapis.com/projects/$GCP_PROJECT_ID/topics/$TOPIC_NAME" \
    --project="$GCP_PROJECT_ID" \
    --log-filter="$SINK_FILTER" 2>/dev/null \
    || gcloud logging sinks update "$SINK_NAME" \
        "pubsub.googleapis.com/projects/$GCP_PROJECT_ID/topics/$TOPIC_NAME" \
        --project="$GCP_PROJECT_ID" \
        --log-filter="$SINK_FILTER"

# Grant Pub/Sub publisher role to the sink's service account
PROJECT_NUMBER=$(gcloud projects describe "$GCP_PROJECT_ID" --format='value(projectNumber)')
SINK_SA="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-logging.iam.gserviceaccount.com"

gcloud pubsub topics add-iam-policy-binding "$TOPIC_NAME" \
    --project="$GCP_PROJECT_ID" \
    --member="$SINK_SA" \
    --role="roles/pubsub.publisher" >/dev/null

# 3. Deploy the Cloud Function
echo "[3/3] Deploying Cloud Function: $FN_NAME"
gcloud functions deploy "$FN_NAME" \
    --project="$GCP_PROJECT_ID" \
    --region="$GCP_REGION" \
    --runtime=python312 \
    --trigger-topic="$TOPIC_NAME" \
    --entry-point=vm_alert_to_slack \
    --source="$FN_DIR" \
    --set-env-vars="SLACK_WEBHOOK_URL=$SLACK_WEBHOOK_URL,GCP_PROJECT_ID=$GCP_PROJECT_ID" \
    --gen2 \
    --memory=256MB \
    --timeout=60s

echo "VM Alert Pipeline deployed."

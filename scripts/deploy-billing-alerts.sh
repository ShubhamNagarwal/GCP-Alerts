#!/bin/bash
# Deploy the Billing Alert pipeline:
#   - Pub/Sub topic
#   - Cloud Function (Pub/Sub -> Slack)
#
# After deployment, attach the Pub/Sub topic to your GCP Budget alert in:
#   https://console.cloud.google.com/billing/<account>/budgets
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FN_DIR="$SCRIPT_DIR/../cloud-functions/billing-alert-to-slack"

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID is required}"
: "${GCP_REGION:=us-central1}"
: "${SLACK_WEBHOOK_URL:?SLACK_WEBHOOK_URL is required}"
: "${GCP_BILLING_ACCOUNT:=}"

TOPIC_NAME="billing-alerts"
FN_NAME="billing-alert-to-slack"

echo "==============================================================="
echo " Deploying Billing Alert Pipeline"
echo "==============================================================="

# 1. Create Pub/Sub topic
echo "[1/2] Creating Pub/Sub topic: $TOPIC_NAME"
gcloud pubsub topics create "$TOPIC_NAME" --project="$GCP_PROJECT_ID" 2>/dev/null \
    || echo "      Topic already exists, skipping."

# 2. Deploy the Cloud Function
echo "[2/2] Deploying Cloud Function: $FN_NAME"
ENV_VARS="SLACK_WEBHOOK_URL=$SLACK_WEBHOOK_URL,GCP_PROJECT_ID=$GCP_PROJECT_ID"
if [ -n "$GCP_BILLING_ACCOUNT" ]; then
    ENV_VARS="$ENV_VARS,GCP_BILLING_ACCOUNT=$GCP_BILLING_ACCOUNT"
fi

gcloud functions deploy "$FN_NAME" \
    --project="$GCP_PROJECT_ID" \
    --region="$GCP_REGION" \
    --runtime=python312 \
    --trigger-topic="$TOPIC_NAME" \
    --entry-point=billing_alert_to_slack \
    --source="$FN_DIR" \
    --set-env-vars="$ENV_VARS" \
    --gen2 \
    --memory=256MB \
    --timeout=60s

echo ""
echo "==============================================================="
echo " Billing Alert Pipeline deployed."
echo ""
echo " NEXT STEP: Attach the Pub/Sub topic to your GCP Budget."
echo " Go to: https://console.cloud.google.com/billing/<your-account>/budgets"
echo " Edit your budget -> Connect a Pub/Sub topic -> select '$TOPIC_NAME'"
echo "==============================================================="

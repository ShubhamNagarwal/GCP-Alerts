#!/bin/bash
# Deploy all GCP Alert Hub components: monitoring alerts, VM pipeline, billing pipeline.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID is required}"
: "${GCP_REGION:=us-central1}"
: "${SLACK_WEBHOOK_URL:?SLACK_WEBHOOK_URL is required}"
: "${SLACK_CHANNEL_ID:?SLACK_CHANNEL_ID is required (GCP notification channel ID)}"

echo "==============================================================="
echo " GCP Alert Hub - Full Deployment"
echo "==============================================================="
echo " Project: $GCP_PROJECT_ID"
echo " Region:  $GCP_REGION"
echo "==============================================================="

bash "$SCRIPT_DIR/deploy-monitoring-alerts.sh"
bash "$SCRIPT_DIR/deploy-vm-alerts.sh"
bash "$SCRIPT_DIR/deploy-billing-alerts.sh"

echo ""
echo "==============================================================="
echo " Deployment complete!"
echo "==============================================================="
echo " Test with:"
echo "   ./scripts/test-billing-alert.sh"
echo "   ./scripts/test-vm-alert.sh"
echo "==============================================================="

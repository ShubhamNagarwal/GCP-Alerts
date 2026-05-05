#!/bin/bash
# Send a test billing alert to the Pub/Sub topic.
set -euo pipefail

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID is required}"

gcloud pubsub topics publish billing-alerts \
    --project="$GCP_PROJECT_ID" \
    --message='{"budgetDisplayName":"TEST Budget","costAmount":1500,"budgetAmount":7000,"currencyCode":"USD","alertThresholdExceeded":0.21,"costIntervalStart":"2026-04-01T00:00:00Z"}'

echo ""
echo "Test message sent. Check Cloud Function logs:"
echo "  gcloud functions logs read billing-alert-to-slack --project=$GCP_PROJECT_ID --region=us-central1 --limit=5"

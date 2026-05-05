#!/bin/bash
# Deploy all 6 Cloud Monitoring alert policies from JSON definitions.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALERTS_DIR="$SCRIPT_DIR/../monitoring-alerts"

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID is required}"
: "${SLACK_CHANNEL_ID:?SLACK_CHANNEL_ID is required}"

echo "Deploying 6 Cloud Monitoring alert policies..."

ACCESS_TOKEN=$(gcloud auth print-access-token)

for alert_file in "$ALERTS_DIR"/*.json; do
    alert_name=$(basename "$alert_file" .json)
    echo "  -> Creating: $alert_name"

    # Substitute the Slack channel placeholder
    body=$(sed "s|\${SLACK_CHANNEL_ID}|projects/$GCP_PROJECT_ID/notificationChannels/$SLACK_CHANNEL_ID|g" "$alert_file")

    response=$(curl -s -X POST \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        "https://monitoring.googleapis.com/v3/projects/$GCP_PROJECT_ID/alertPolicies" \
        -d "$body")

    if echo "$response" | grep -q '"displayName"'; then
        display_name=$(echo "$response" | python3 -c "import json,sys; print(json.load(sys.stdin).get('displayName',''))")
        echo "     OK -> $display_name"
    else
        echo "     ERROR: $response"
    fi
done

echo "Monitoring alerts deployed."

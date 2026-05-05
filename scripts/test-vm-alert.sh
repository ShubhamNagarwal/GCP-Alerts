#!/bin/bash
# Send a test VM alert to the Pub/Sub topic.
set -euo pipefail

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID is required}"

gcloud pubsub topics publish vm-alerts \
    --project="$GCP_PROJECT_ID" \
    --message='{
      "protoPayload": {
        "methodName": "v1.compute.instances.start",
        "authenticationInfo": {"principalEmail": "test-user@example.com"},
        "resourceName": "projects/'"$GCP_PROJECT_ID"'/zones/us-central1-b/instances/test-instance"
      },
      "resource": {
        "labels": {
          "instance_id": "1234567890",
          "project_id": "'"$GCP_PROJECT_ID"'",
          "zone": "us-central1-b"
        }
      },
      "timestamp": "2026-04-03T12:00:00.000000Z"
    }'

echo ""
echo "Test message sent. Check Cloud Function logs:"
echo "  gcloud functions logs read vm-alert-to-slack --project=$GCP_PROJECT_ID --region=us-central1 --limit=5"

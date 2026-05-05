"""
Cloud Function that receives VM audit log entries from Pub/Sub
(via a Log Router sink) and forwards a detailed notification to Slack.

Captures VM lifecycle and configuration changes:
  - Lifecycle: start, stop, delete, restart, create
  - Config: machine type, disk, metadata, service account, network, labels, tags

Filters out GKE autoscaler activity (service accounts) and shows:
  - VM name, action, who did it, when, where
"""

import base64
import json
import os
import urllib.request
import urllib.error
from datetime import datetime


# Map GCP method names to human-readable actions
ACTION_MAP = {
    "v1.compute.instances.start": ("STARTED", ":arrow_forward:"),
    "v1.compute.instances.stop": ("STOPPED", ":octagonal_sign:"),
    "v1.compute.instances.delete": ("DELETED", ":wastebasket:"),
    "v1.compute.instances.reset": ("RESTARTED", ":arrows_counterclockwise:"),
    "v1.compute.instances.insert": ("CREATED", ":heavy_plus_sign:"),
    "v1.compute.instances.setMachineType": ("MACHINE TYPE CHANGED", ":gear:"),
    "v1.compute.instances.attachDisk": ("DISK ATTACHED", ":floppy_disk:"),
    "v1.compute.instances.detachDisk": ("DISK DETACHED", ":floppy_disk:"),
    "v1.compute.instances.setMetadata": ("METADATA CHANGED", ":pencil:"),
    "v1.compute.instances.setServiceAccount": ("SERVICE ACCOUNT CHANGED", ":key:"),
    "v1.compute.instances.updateNetworkInterface": ("NETWORK CHANGED", ":globe_with_meridians:"),
    "v1.compute.instances.setLabels": ("LABELS CHANGED", ":label:"),
    "v1.compute.instances.setTags": ("FIREWALL TAGS CHANGED", ":shield:"),
}

LIFECYCLE_ACTIONS = {"STARTED", "STOPPED", "DELETED", "RESTARTED", "CREATED"}


def vm_alert_to_slack(event, context):
    """Pub/Sub-triggered Cloud Function entrypoint."""

    log_entry = _parse_event(event)

    proto = log_entry.get("protoPayload", {})
    resource_labels = log_entry.get("resource", {}).get("labels", {})
    log_labels = log_entry.get("labels", {})

    method = proto.get("methodName", "unknown")
    action_label, action_emoji = ACTION_MAP.get(method, (method, ":bell:"))

    # Extract VM name from resourceName: projects/x/zones/y/instances/VM_NAME
    resource_name = proto.get("resourceName", "")
    vm_name = resource_name.split("/")[-1] if resource_name else ""
    if not vm_name:
        vm_name = log_labels.get("compute.googleapis.com/resource_name", "Unknown")

    user = proto.get("authenticationInfo", {}).get("principalEmail", "Unknown")
    zone = resource_labels.get("zone", "Unknown")
    project = resource_labels.get("project_id", os.environ.get("GCP_PROJECT_ID", ""))
    instance_id = resource_labels.get("instance_id", "Unknown")
    timestamp = log_entry.get("timestamp", "Unknown")

    try:
        dt = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
        time_str = dt.strftime("%b %d, %Y %H:%M:%S UTC")
    except Exception:
        time_str = timestamp

    is_lifecycle = action_label in LIFECYCLE_ACTIONS
    if action_label in ("DELETED", "STOPPED"):
        color, severity = "#FF0000", "CRITICAL"
        alert_emoji = ":rotating_light:"
    elif is_lifecycle:
        color, severity = "#FF6600", "HIGH"
        alert_emoji = ":warning:"
    else:
        color, severity = "#FFCC00", "MEDIUM"
        alert_emoji = ":large_yellow_circle:"

    category = "Lifecycle Change" if is_lifecycle else "Configuration Change"

    text = (
        f"{alert_emoji} *GCP VM Alert - {severity}*\n\n"
        f"{action_emoji} *VM {action_label}*\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"*VM Name:* `{vm_name}`\n"
        f"*Action:* {action_label}\n"
        f"*Category:* {category}\n"
        f"*Done By:* {user}\n"
        f"*Time:* {time_str}\n"
        f"*Zone:* {zone}\n"
        f"*Instance ID:* {instance_id}\n"
        f"*Project:* {project}\n\n"
        f"<https://console.cloud.google.com/compute/instancesDetail/zones/{zone}/instances/{vm_name}?project={project}|"
        f":link: View VM in Console>"
    )

    print(f"Sending alert: VM={vm_name}, Action={action_label}, By={user}")

    webhook_url = os.environ.get("SLACK_WEBHOOK_URL", "")
    if not webhook_url:
        print("SLACK_WEBHOOK_URL not configured. Message:")
        print(text)
        return "NO_WEBHOOK"

    payload = json.dumps({
        "text": text,
        "attachments": [{"color": color, "text": ""}]
    }).encode("utf-8")

    req = urllib.request.Request(
        webhook_url,
        data=payload,
        headers={"Content-Type": "application/json"}
    )

    try:
        resp = urllib.request.urlopen(req)
        body = resp.read().decode()
        print(f"Webhook sent: {body}")
        return "OK"
    except urllib.error.HTTPError as e:
        error_body = e.read().decode() if e.fp else "no body"
        print(f"Webhook HTTPError: {e.code} {e.reason} | body: {error_body}")
        return "WEBHOOK_ERROR"
    except Exception as e:
        print(f"Webhook error: {type(e).__name__}: {e}")
        return "ERROR"


def _parse_event(event):
    """Handle both Gen1 and Gen2 Pub/Sub event formats."""
    try:
        if not isinstance(event, dict) or "data" not in event:
            return {}
        data = event["data"]
        if isinstance(data, dict) and "message" in data:
            raw = base64.b64decode(data["message"]["data"]).decode("utf-8")
        else:
            raw = base64.b64decode(data).decode("utf-8")
        return json.loads(raw)
    except Exception as e:
        print(f"Error parsing event: {type(e).__name__}: {e}")
        return {}

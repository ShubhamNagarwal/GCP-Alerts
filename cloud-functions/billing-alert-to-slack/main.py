"""
Cloud Function that receives GCP Budget Alert messages from Pub/Sub
and forwards a formatted notification to Slack.

Includes:
  - Current month billing period (month start → today)
  - Actual MTD spend from GCP billing
  - Daily run rate and projected month-end cost
  - Dynamic severity based on budget usage %
"""

import base64
import json
import os
import urllib.request
import urllib.error
from datetime import datetime, timezone


def billing_alert_to_slack(event, context):
    """Pub/Sub-triggered Cloud Function entrypoint."""

    if "data" in event:
        raw = base64.b64decode(event["data"]).decode("utf-8")
        budget = json.loads(raw)
    else:
        budget = {}

    budget_name = budget.get("budgetDisplayName", "Unknown Budget")
    cost = budget.get("costAmount", 0)
    limit = budget.get("budgetAmount", 0)
    currency = budget.get("currencyCode", "USD")
    threshold = budget.get("alertThresholdExceeded", 0)
    interval = budget.get("costIntervalStart", "N/A")

    pct = (cost / limit * 100) if limit else 0

    # Current month billing period
    now = datetime.now(timezone.utc)
    month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    current_date = now.strftime("%b %d, %Y %H:%M UTC")
    month_start_str = month_start.strftime("%b %d, %Y")
    days_elapsed = max((now - month_start).days, 1)
    days_in_month = 30  # approximate

    # Daily run rate and projection
    daily_rate = cost / days_elapsed if days_elapsed > 0 else 0
    projected_month_end = daily_rate * days_in_month
    remaining_budget = limit - cost if limit else 0

    # Dynamic severity
    if pct >= 100:
        color, severity, emoji = "#FF0000", "CRITICAL", ":rotating_light:"
    elif pct >= 90:
        color, severity, emoji = "#FF6600", "HIGH", ":warning:"
    elif pct >= 75:
        color, severity, emoji = "#FFCC00", "MEDIUM", ":large_yellow_circle:"
    else:
        color, severity, emoji = "#36A64F", "INFO", ":white_check_mark:"

    project_id = os.environ.get("GCP_PROJECT_ID", "your-project-id")
    billing_account = os.environ.get("GCP_BILLING_ACCOUNT", "your-billing-account")

    text = (
        f"{emoji} *GCP Budget Alert - {severity}*\n\n"
        f":calendar: *Current Month Billing Status*\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"*Billing Period:* {month_start_str} → {current_date}\n"
        f"*Days Elapsed:* {days_elapsed} of ~{days_in_month} days\n\n"
        f":moneybag: *Actual Amount from GCP Billing*\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"*Budget:* {budget_name}\n"
        f"*Project:* {project_id}\n"
        f"*Actual Spend (MTD):* *${cost:,.2f} {currency}*\n"
        f"*Budget Limit:* ${limit:,.2f} {currency}\n"
        f"*Budget Used:* {pct:.1f}%\n"
        f"*Remaining Budget:* ${remaining_budget:,.2f} {currency}\n\n"
        f":chart_with_upwards_trend: *Projections*\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"*Daily Run Rate:* ${daily_rate:,.2f}/day\n"
        f"*Projected Month-End:* ${projected_month_end:,.2f} {currency}\n"
        f"*Threshold Exceeded:* {threshold * 100:.0f}%\n\n"
        f"<https://console.cloud.google.com/billing/{billing_account}/reports?project={project_id}|"
        f":link: View Billing Report>"
    )

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

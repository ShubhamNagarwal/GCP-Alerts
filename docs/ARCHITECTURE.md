# Architecture

The GCP Alert Hub uses three independent pipelines, all delivering to a single Slack channel.

## Pipeline 1: Cloud Monitoring Alerts

Metric and log-based alerts evaluated by GCP Cloud Monitoring.

```
┌───────────────┐     ┌─────────────────────────┐     ┌──────────────────────┐     ┌──────────┐
│ GCP Metrics & │ ──► │ Cloud Monitoring Alert  │ ──► │ Notification Channel │ ──► │  Slack   │
│  Audit Logs   │     │       Policies          │     │      (Slack)         │     │ Channel  │
└───────────────┘     └─────────────────────────┘     └──────────────────────┘     └──────────┘
```

**Used for:** Compute, Logging, GKE, Egress, IAM (alerts 1-6)

---

## Pipeline 2: VM Audit Logs → Cloud Function

Captures VM lifecycle and configuration audit logs and enriches them with VM name, action, and user identity.

```
┌──────────────┐    ┌────────────────────────┐    ┌──────────────┐    ┌────────────────────┐    ┌──────────┐
│ Compute      │ ──►│ Log Router Sink        │ ──►│ Pub/Sub      │ ──►│ Cloud Function     │ ──►│  Slack   │
│ Audit Logs   │    │ "vm-change-alerts"     │    │ "vm-alerts"  │    │ vm-alert-to-slack  │    │ Channel  │
└──────────────┘    └────────────────────────┘    └──────────────┘    └────────────────────┘    └──────────┘
```

**Why a pipeline (not native Cloud Monitoring):** The native log-based alert documentation field is static. To show *VM name, who did it, and what happened* dynamically in Slack, we parse the log entry in a Cloud Function and craft a rich message.

**Filter:** Excludes `gserviceaccount.com` (GKE autoscaler noise) and uses `operation.last=true` to dedupe.

---

## Pipeline 3: Billing Budget → Cloud Function

GCP Budget alerts publish to Pub/Sub when thresholds are crossed; the Cloud Function adds context and projections.

```
┌──────────────┐    ┌────────────────────┐    ┌─────────────────────────┐    ┌──────────┐
│ GCP Billing  │ ──►│ Pub/Sub            │ ──►│ Cloud Function          │ ──►│  Slack   │
│   Budget     │    │ "billing-alerts"   │    │ billing-alert-to-slack  │    │ Channel  │
└──────────────┘    └────────────────────┘    └─────────────────────────┘    └──────────┘
```

**Why a pipeline:** Native budget notifications only show the threshold/cost. We add daily run rate, projected month-end, days elapsed, remaining budget, and dynamic severity color-coding.

---

## Why Slack-Only

In the original incident:
- Email alerts were ignored (signal-to-noise too low)
- Multiple recipients led to "someone else will handle it" diffusion
- Lack of conversation thread meant context died with the alert

A single Slack channel:
- One source of truth, visible to the whole team
- Rich formatting (colors, emojis, links)
- Threadable so investigation history stays attached
- No CC/BCC, no inbox bankruptcy

## Component Summary

| Component | Type | Purpose |
|-----------|------|---------|
| Cloud Monitoring Alert Policies | GCP Service | Threshold and log-based alerts |
| Notification Channel (Slack) | GCP Service | Connects alert policies to Slack |
| Log Router Sink (`vm-change-alerts`) | GCP Service | Routes audit logs to Pub/Sub |
| Pub/Sub Topic (`vm-alerts`) | GCP Service | Decouples log routing from processing |
| Pub/Sub Topic (`billing-alerts`) | GCP Service | Receives budget notifications |
| Cloud Function (`vm-alert-to-slack`) | Gen2, Python 3.12 | Parses logs, formats Slack message |
| Cloud Function (`billing-alert-to-slack`) | Gen2, Python 3.12 | Adds projections to budget alerts |
| Slack Incoming Webhook | Slack | Posts message to channel |

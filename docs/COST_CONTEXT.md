# Cost Context — Why These Alerts Exist

This repo was built in response to a real cost incident on the `satschel-nonprod` GCP project in March 2026.

## Monthly Bills (Dec 2025 → April 2026)

| Month | Total Bill | Change | Notes |
|-------|-----------|--------|-------|
| December 2025 | $6,101.38 | — | Baseline |
| January 2026 | $6,316.18 | +3.5% | Normal |
| February 2026 | $6,741.23 | +6.7% | Slight increase |
| **March 2026** | **$11,149.51** | **+65.4%** | **GKE autoscaling spike** |
| April 2026 (2 days) | $147.51 | Normalized | ~$4,500 projected |

## What Happened in March 2026

A GKE autoscaling event caused instance count to surge from **52 → 1,945 instances**, which then cascaded into other services:

| Service | Normal | March Peak | Increase |
|---------|--------|-----------|----------|
| Compute (instances) | 52 | 1,945 | 37x |
| Cloud Logging (k8s_container) | 644 GB/mo | 7 TB/mo | 11x (+$3,190) |
| Network egress | 2.9 TB/mo | 9.4 TB/mo | 3.2x |
| Network egress (single day) | ~100 GB | 1,800 GB (Mar 22) | 18x |

**Logging alone accounted for 93% of the cost increase** because every container generated more logs proportional to instance count.

## What These Alerts Catch

| Alert | What It Would Have Caught |
|-------|--------------------------|
| Compute Engine — Instances > 50 | First indicator of unusual scaling |
| GKE — Node Count > 20 | Root cause: autoscaler running away |
| Cloud Logging — k8s > 100 GB/day | Cascading log ingestion increase |
| Cloud Logging — Total > 500 GB/day | Other log sources spiking |
| Network Egress > 500 GB/day | Egress cost driver |
| Billing Budget Alert | Final fallback, total spend hit threshold |
| VM Lifecycle Changes | Unauthorized human VM creation |
| IAM Audit Config Change | Audit log scope being modified |

If we had these alerts in February 2026, we could have caught the runaway scaling within hours instead of discovering it on the next month's bill.

## Lessons

1. **Single signals don't tell the whole story.** A logging cost spike is a *symptom* of a compute event. Alert on multiple layers.
2. **Routing matters.** Email alerts have lower engagement than Slack channels. A single channel beats a distribution list.
3. **Context matters.** "Budget exceeded" is less actionable than "Spending is $X with daily run rate of $Y, projected to hit $Z by month-end". The Cloud Function pipelines add this context.
4. **Filtering matters.** Without `gserviceaccount.com` exclusion, GKE autoscaling would generate hundreds of false-positive VM alerts daily.
5. **Deduplication matters.** GCP creates two audit log entries per operation. Filtering for `operation.last=true` halves notification volume.

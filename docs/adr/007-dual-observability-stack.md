# ADR-007: Dual Observability Stack (CloudWatch Container Insights + kube-prometheus-stack)

**Status:** Accepted  
**Date:** 2026-05-19

## Context

The platform must provide observability for both platform operators and application teams. Two distinct audiences have different tools and access patterns:

- **Platform operators / AWS support** — work in the AWS console, use CloudWatch for alarming, cost correlation, and AWS support case escalation.
- **Application teams** — need self-service dashboards for their workload metrics and logs without requiring AWS console access.

A decision is needed on which observability tooling to install as shared cluster add-ons, and whether a single stack can serve both audiences or two stacks are needed.

## Decision

Two observability components are deployed as shared cluster add-ons:

1. **CloudWatch Container Insights** — AWS-managed Fluent Bit DaemonSet + CloudWatch agent DaemonSet. Ships node metrics, pod metrics, and container logs to CloudWatch.
2. **kube-prometheus-stack** — Prometheus Operator, Prometheus, Alertmanager, and Grafana deployed in the `monitoring` namespace. Grafana is exposed via an internal ALB Ingress (VPC-only access).

Both stacks run on system nodes. They are independent — neither depends on the other.

## Rationale

### Why CloudWatch Container Insights?

- **AWS support requirement.** AWS support engineers work in CloudWatch. When a support case is opened for node-level issues (CPU throttling, OOM, networking), CloudWatch Container Insights provides the baseline telemetry AWS expects to be present.
- **Cost Explorer integration.** Container Insights metrics feed into AWS Cost Explorer's container cost allocation features, enabling per-namespace cost attribution.
- **CloudWatch alarms.** Platform-level alarms (e.g., node disk pressure, API server error rate) are configured in CloudWatch and integrate with SNS for paging — a pattern the operations team already uses for other AWS services.
- **Managed data retention.** CloudWatch handles log retention, encryption, and cross-account access without additional infrastructure.

### Why kube-prometheus-stack?

- **Team self-service.** Application teams can log in to Grafana and view dashboards for their namespace's CPU/memory usage, HTTP error rates, and custom application metrics — without needing AWS console access or CloudWatch IAM permissions.
- **Richer Kubernetes-native metrics.** The Prometheus Operator scrapes `kube-state-metrics` and `node-exporter`, providing Kubernetes object-level metrics (Deployment replica count, HPA status, PVC usage) that CloudWatch Container Insights does not expose in the same granularity.
- **Custom dashboards and alerting.** Teams can add their own `PrometheusRule` and `ServiceMonitor` resources to define custom alerts and scrape their application metrics, without requiring platform team involvement.
- **Standard tooling.** Prometheus and Grafana are the de facto standard in the Kubernetes ecosystem. Operational runbooks, PromQL examples, and community dashboards are widely available.

### Why not a single unified stack?

- CloudWatch is not replaceable for the AWS support and cost allocation use cases — it is required.
- Prometheus/Grafana cannot be replaced with CloudWatch for the team self-service use case without requiring every team to have CloudWatch IAM permissions and learn the CloudWatch Metrics Insights query language.
- The two stacks are complementary, not redundant. Their resource overhead is acceptable given they run on dedicated system nodes.

## Resource footprint (approximate, system nodes)

| Component | CPU request | Memory request |
|-----------|-------------|----------------|
| CloudWatch agent (DaemonSet, per node) | 200m | 200Mi |
| Fluent Bit (DaemonSet, per node) | 100m | 128Mi |
| Prometheus | 500m | 1Gi |
| Grafana | 100m | 256Mi |
| kube-state-metrics | 100m | 128Mi |
| node-exporter (DaemonSet, per node) | 50m | 64Mi |

System nodes (`m6i.large`, 2 vCPU / 8 GiB) can accommodate the Prometheus/Grafana stack alongside the other add-ons. The DaemonSet components run on all nodes (system and application) but with very low per-node overhead.

## Alternatives Considered

### CloudWatch Container Insights only

Use only CloudWatch for all observability. Teams access metrics via the CloudWatch console or CloudWatch Metrics Insights.

**Rejected because:**
- Requires all application teams to have CloudWatch IAM read permissions — a privilege that should not be granted to all developers on a shared account.
- CloudWatch Metrics Insights is less ergonomic than PromQL/Grafana for application-layer observability.
- No native support for custom application metric scraping (Prometheus `ServiceMonitor` pattern) without additional tooling.

### kube-prometheus-stack only, export to CloudWatch via remote_write

Run only Prometheus and use `remote_write` to push metrics to CloudWatch via the CloudWatch agent.

**Rejected because:**
- `remote_write` to CloudWatch is not the same as Container Insights — it does not populate the Container Insights dashboards or the ECS/EKS cost allocation features.
- Adds complexity (remote_write configuration, authentication) for uncertain benefit.
- AWS support still expects Container Insights to be present for node-level diagnostics.

### Third-party SaaS observability (Datadog, New Relic, etc.)

**Deferred:** A reasonable future addition for teams that want APM-level traces. For the initial platform, the dual CloudWatch + Prometheus/Grafana stack covers the required use cases without a SaaS dependency or per-host licensing cost.

## Consequences

- System nodes must have sufficient capacity for the Prometheus server's memory requirements (~1 GiB + TSDB storage). PersistentVolumeClaims backed by EBS gp3 are used for Prometheus and Grafana persistence.
- Grafana is accessible only from within the VPC (internal ALB). Teams must use VPN or a bastion to access Grafana dashboards.
- Platform team is responsible for Prometheus scrape configuration and Grafana datasource setup. Teams self-serve dashboards within those constraints.
- Two sets of Helm values must be maintained and upgraded independently.

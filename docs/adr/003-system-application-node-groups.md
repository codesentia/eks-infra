# ADR-003: System vs Application Node Group Split

**Status:** Accepted  
**Date:** 2026-05-19

## Context

EKS worker nodes can be organised into one or more managed node groups. The platform runs two categories of workloads:

1. **Platform add-ons** — cluster-critical shared services (ALB controller, cluster autoscaler, external-dns, cert-manager, ArgoCD, observability stack). These must remain available even under tenant load pressure.
2. **Tenant workloads** — application pods from multiple teams, which are subject to resource quotas but can still generate significant scheduling pressure.

A scheduling failure of a platform add-on (e.g., the cluster autoscaler being evicted) can cascade into a cluster-wide incident. A decision is needed on whether to co-locate these workloads on the same node group or segregate them.

## Decision

Two managed node groups are created per cluster:

| Node group | Taint | Purpose | Instance family | Dev sizing | Prod sizing |
|------------|-------|---------|-----------------|------------|-------------|
| `system` | `CriticalAddonsOnly=true:NoSchedule` | Platform add-ons | `m6i.large` | min 2 / max 4 | min 2 / max 4 |
| `application` | _(none)_ | Tenant workloads | `m6i.xlarge` (dev) / `m7i.xlarge` (prod) | min 2 / max 20 | min 3 / max 50 |

Platform add-ons carry the corresponding toleration and a `nodeSelector` targeting the `system` node group. Tenant workloads have neither toleration nor selector, so they land exclusively on `application` nodes.

## Rationale

### Why segregate at the node group level?

Kubernetes resource quotas limit how much CPU/memory a namespace can *request*, but they do not prevent burst usage from pushing the scheduler into a resource-constrained state. If an add-on pod is evicted due to node pressure (OOM, CPU throttling), it may be temporarily unavailable while the cluster autoscaler provisions a new node — but the autoscaler itself could be the pod under pressure, creating a deadlock.

By placing platform add-ons on a dedicated `system` node group with a `NoSchedule` taint, tenant pods are physically excluded from those nodes. The system nodes cannot be saturated by tenant workload.

### Why `CriticalAddonsOnly=true:NoSchedule`?

This taint key is used by Kubernetes itself for DaemonSet tolerations and is the conventional key for critical add-ons. Using the same key means well-behaved upstream Helm charts (e.g., CoreDNS, kube-proxy) already carry the matching toleration and will schedule correctly on system nodes without custom configuration.

### Instance family choices

- **`m6i.large` for system nodes:** Add-ons have modest, predictable resource requirements. `m6i.large` (2 vCPU, 8 GiB) is cost-effective and provides enough headroom for the full add-on stack without overprovisioning.
- **`m6i.xlarge` / `m7i.xlarge` for application nodes:** Tenant workloads are unpredictable. Larger instances reduce the scheduler fragmentation caused by many small pods competing for the last few millicores on a node. `m7i` is used in prod for better price/performance with newer Intel architecture.

### Why managed node groups (not self-managed or Fargate)?

- Managed node groups handle AMI updates, node drain, and instance termination via the EKS managed node group lifecycle — reducing operational overhead.
- Fargate is appropriate for bursty, isolated workloads but lacks support for DaemonSets (required for the observability stack) and has higher per-pod cost at sustained load.

## Alternatives Considered

### Single node group for all workloads

A single managed node group serving both platform add-ons and tenant workloads.

**Rejected because:**
- A misbehaving tenant workload (memory leak, missing resource limits) could starve or evict the cluster autoscaler, external-dns, or cert-manager.
- No mechanism to guarantee compute availability for cluster-critical services without per-pod PriorityClass tuning across all tenant-facing charts.

### Three node groups (system, tenant-standard, tenant-burstable)

Add a third tier for burst-tolerant tenant workloads (e.g., batch jobs, CI runners).

**Deferred:** A reasonable future extension, but premature for the initial platform. The `application` node group can be split later if tenant workload profiles diverge significantly.

## Consequences

- Platform add-on Helm charts must explicitly set `nodeSelector` and `tolerations` in their `values.yaml`.
- Tenant workloads that accidentally add the `CriticalAddonsOnly` toleration will schedule on system nodes — teams must be informed not to do this, and it can be blocked via OPA/Kyverno in a future policy layer.
- The system node group has a fixed maximum of 4 nodes. If the add-on stack grows significantly, this cap must be revisited.

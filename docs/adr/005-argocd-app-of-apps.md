# ADR-005: ArgoCD with App of Apps Pattern

**Status:** Accepted  
**Date:** 2026-05-19

## Context

The platform requires a GitOps controller to reconcile the desired state of the cluster (add-ons and team namespace manifests) from the git repository. Without a GitOps controller, cluster state drifts from the repository over time as operators make ad-hoc changes.

Two leading GitOps tools were considered: **Flux** and **ArgoCD**. A decision is also needed on how the controller is structured internally — in particular, how it manages the two distinct reconciliation concerns of this platform: shared add-ons (high blast radius, manual approval required) and team namespaces (low blast radius, safe to auto-apply).

## Decision

**ArgoCD** is the GitOps controller. It uses the **App of Apps** pattern: a single root `Application` resource (bootstrapped manually once) manages child `Application` resources that own specific directories in the repository.

### Directory structure

```
eks-infra/
└── apps/
    ├── root.yaml          ← bootstrapped once; manages all other Applications
    ├── addons.yaml        ← Application: points at addons/, manual sync only
    └── namespaces.yaml    ← Application: points at namespaces/, automated sync
```

### Sync policy per layer

| Application | Sync policy | Rationale |
|-------------|-------------|-----------|
| `addons` | Manual (no `syncPolicy.automated`) | Shared services; an unreviewed upgrade could affect all tenants simultaneously |
| `namespaces` | Automated (`syncPolicy.automated.prune: true`) | Low blast radius; team namespace manifests are reviewed via PR before merge |

### RBAC

Only the platform team has the `applications, sync` action on the `addons` Application in ArgoCD's RBAC config. Team leads can view sync status but cannot trigger syncs for shared add-ons.

## Rationale

### Why ArgoCD over Flux?

Both tools are production-grade and support this repository structure. ArgoCD was chosen primarily for its UI:

- **Multi-team visibility.** ArgoCD's web UI gives teams a self-service view of their Application sync status, resource tree, and recent sync history — without requiring `kubectl` access to the cluster.
- **Manual sync approval workflow.** ArgoCD's UI makes the "approve and sync" workflow for add-on upgrades explicit and auditable. Flux's approach to manual sync is less visible.
- **Broad adoption.** ArgoCD has wider adoption in multi-tenant shared platform contexts, meaning more operational runbooks and community patterns are available.

Flux remains a viable alternative and the directory structure is compatible with Flux if a future migration is needed.

### Why App of Apps?

The App of Apps pattern allows a single bootstrapping action (`kubectl apply -f apps/root.yaml`) to hand all ongoing reconciliation to ArgoCD. After that point, adding a new team namespace or a new add-on is a git operation only — no operator needs to configure ArgoCD directly.

The pattern also makes sync policy a per-Application concern. `addons.yaml` and `namespaces.yaml` can have independent sync policies, health checks, and notification hooks without affecting each other.

### Why separate automated vs manual sync by layer?

- **`namespaces/` — automated:** A team namespace manifest (ResourceQuota, NetworkPolicy, RBAC) is low risk. If a PR is merged, the change should land in the cluster promptly. Manual sync would create toil for every team onboarding.
- **`addons/` — manual:** A Helm values change for `kube-prometheus-stack` or `aws-load-balancer-controller` affects every tenant. Requiring a human to review the ArgoCD diff and click "Sync" provides a final gate before the change is applied. The PR review is not sufficient alone because the diff in git does not show rendered Kubernetes resources — the ArgoCD diff does.

## Alternatives Considered

### Flux with Kustomization resources

Flux `Kustomization` resources can achieve the same directory-to-cluster mapping. Flux's `HelmRelease` controller is more native to Helm than ArgoCD's Helm support.

**Not selected because:**
- Flux lacks a built-in UI for multi-team sync status visibility.
- The manual approval workflow in Flux requires suspending and resuming reconciliation, which is less ergonomic than ArgoCD's sync button with RBAC.

### Single ArgoCD Application pointing at the repo root

One Application that reconciles everything under `eks-infra/` at once.

**Rejected because:**
- No mechanism to have different sync policies for add-ons vs namespaces.
- A sync of the entire repository triggers re-evaluation of every resource — too coarse for a shared platform.

### No GitOps controller (manual `kubectl apply`)

Operators apply manifests manually from the repository.

**Rejected because:**
- Cluster state drifts from git over time (manual hotfixes that never get committed back).
- No automatic self-healing if a manifest is accidentally deleted or modified in-cluster.
- Does not scale as team count grows.

## Consequences

- An `apps/` directory must be added to the repository containing ArgoCD `Application` manifests.
- ArgoCD itself is bootstrapped via `helm upgrade --install` (a one-time imperative step); after that it manages itself via the App of Apps.
- Add-on upgrades require a two-step process: merge the PR to git, then manually trigger the ArgoCD sync. This is intentional — the friction is the safety mechanism.
- Operators need familiarity with the ArgoCD UI and CLI (`argocd` CLI or `kubectl` port-forward to the ArgoCD server) for day-two operations.

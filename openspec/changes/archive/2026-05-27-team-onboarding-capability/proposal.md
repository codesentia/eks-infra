## Why

The `thor` EKS cluster is deployed with networking, IAM roles, and VPC CNI configured, but no mechanism exists for teams to deploy and operate applications. Teams need isolated namespaces with RBAC, resource quotas, network policies, and a GitOps workflow to deploy containerized workloads. Without this capability, the platform cannot fulfill its purpose as a shared multi-tenant environment.

## What Changes

- New Python onboarding script (`scripts/onboard_team.py`) to create per-team namespace with RBAC roles, resource quotas, and network policies from a template
- New namespace manifest templates under `namespaces/templates/` that define the baseline security and resource configuration
- Decision: **Install ArgoCD as a prerequisite** to enable GitOps-driven application deployment; teams will own application manifests in their own repos, referenced by ArgoCD ApplicationSets
- New `Makefile` targets: `install-argocd` (deploy ArgoCD to `argocd` namespace with IRSA role for ECR pull), `onboard-team` (run onboarding script with team parameters)
- IAM: New IRSA role for ArgoCD to pull from ECR (`iam/argocd-ecr-role.yaml`), optionally per-team IRSA roles for workload pods if workloads need AWS API access
- Documentation: `docs/runbooks/team-onboarding.md` with step-by-step process, prerequisites checklist, and troubleshooting for common namespace/RBAC issues
- Validation script (`scripts/validate_team_setup.py`) to verify namespace resources, RBAC bindings, and network policy enforcement post-onboarding

## Capabilities

### New Capabilities

- `team-onboarding`: Automated creation of isolated team namespaces with baseline RBAC, quotas, and network policies via Python script and manifest templates
- `argocd-gitops`: ArgoCD installation and configuration for GitOps-driven application deployments, including IRSA for ECR image pulls and ApplicationSet patterns for multi-team repos

### Modified Capabilities

_(none — this is net-new capability; existing cluster and IAM infrastructure remain unchanged)_

## Impact

- **New shared service**: ArgoCD deployed to `argocd` namespace, becomes a critical cluster dependency
- **IAM**: New IRSA role for ArgoCD controller; optional per-team IRSA roles created on demand
- **Namespace sprawl**: each onboarded team adds one namespace; cluster autoscaling must handle increased pod density
- **GitOps contract**: teams must structure application repos to work with ArgoCD ApplicationSet discovery patterns (documented in runbook)
- **Security boundary**: network policies enforce namespace isolation; misconfiguration could leak cross-tenant traffic (validation script mitigates this risk)

## Non-goals

- Multi-cluster federation (single cluster `thor` only)
- Namespace-level cost allocation or chargeback (future enhancement)
- Automated offboarding or namespace deletion (manual operator task for now)
- Integration with external identity provider for RBAC (cluster-local service accounts only in this change)

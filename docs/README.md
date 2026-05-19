# EKS Platform Documentation

## Architecture

| Document | Description |
|----------|-------------|
| [Network Topology](architecture/network-topology.md) | VPC layout, subnet tiers, traffic flows, namespace isolation diagrams |
| [IAM and Security Model](architecture/iam-security-model.md) | Node role, IRSA template, per-component roles, Cloudflare token model |
| [GitOps and Deployment Model](architecture/gitops-deployment-model.md) | Ownership boundaries, ArgoCD App of Apps, bootstrap sequence, change management policy |
| [Team Onboarding Model](architecture/team-onboarding-model.md) | Namespace isolation, RBAC, IRSA per team, onboarding and offboarding process |

## Architecture Decision Records

| ADR | Title | Status |
|-----|-------|--------|
| [ADR-001](adr/001-dedicated-vpc-per-cluster.md) | Dedicated VPC per cluster | Accepted |
| [ADR-002](adr/002-three-tier-subnet-layout.md) | Three-tier subnet layout (public / private / intra) | Accepted |
| [ADR-003](adr/003-system-application-node-groups.md) | System vs application node group split | Accepted |
| [ADR-004](adr/004-irsa-pod-iam.md) | IRSA for all pod-level AWS access | Accepted |
| [ADR-005](adr/005-argocd-app-of-apps.md) | ArgoCD with App of Apps pattern | Accepted |
| [ADR-006](adr/006-cloudflare-dns-certificates.md) | Cloudflare for DNS and certificate issuance | Accepted |
| [ADR-007](adr/007-dual-observability-stack.md) | Dual observability stack (CloudWatch + kube-prometheus-stack) | Accepted |

## Runbooks

| Runbook | Description |
|---------|-------------|
| `runbooks/cluster-bootstrap.md` | Ordered sequence to bring a new cluster from zero to GitOps-managed state _(to be authored during implementation)_ |
| `runbooks/team-onboarding.md` | End-to-end team onboarding procedure _(to be authored during implementation)_ |
| `runbooks/cloudflare-token-rotation.md` | Rotating the Cloudflare API token without downtime _(to be authored during implementation)_ |
| `runbooks/addon-upgrade.md` | Upgrading a shared cluster add-on through the ArgoCD gate _(to be authored during implementation)_ |
| `runbooks/cluster-upgrade.md` | Kubernetes version upgrade procedure _(to be authored during implementation)_ |

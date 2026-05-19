## Why

The EKS platform repository exists but has no infrastructure code — teams have no cluster to onboard to, no shared services, and no RBAC boundaries. This change establishes the complete infrastructure design (VPC, cluster, IAM, add-ons, and namespace management) so that implementation can proceed in clearly-scoped, independently-deployable increments.

## What Changes

- New CFN templates for a dual-AZ (dev) and tri-AZ (prod) VPC with public, private, and intra (pod-to-pod) subnet tiers
- New eksctl `ClusterConfig` YAMLs for `dev` and `prod` environments, with managed node groups and OIDC issuer enabled
- New CFN templates for the EKS node IAM role and a baseline set of IRSA roles (ALB controller, cluster autoscaler, external-dns, EBS CSI driver)
- New Helm values / Kustomize overlays for shared cluster add-ons: AWS Load Balancer Controller, cluster-autoscaler, external-dns, cert-manager, and a CloudWatch / Prometheus-based observability stack — **high blast radius: these run once per cluster and affect all tenants**
- New per-team namespace manifests (ResourceQuota, LimitRange, NetworkPolicy, RoleBinding)
- New Python/Bash onboarding scripts that wire together namespace creation, RBAC, and IRSA role vending

## Capabilities

### New Capabilities

- `vpc-networking`: VPC topology (CIDR layout, subnet tiers, NAT gateways, VPC endpoints) and associated security groups via CFN
- `eks-cluster`: eksctl ClusterConfig for dev and prod — managed node groups, OIDC provider, Kubernetes version pinning, and logging config
- `iam-roles`: Node IAM role and per-component IRSA roles (ALB controller, cluster autoscaler, external-dns, EBS CSI driver) with least-privilege inline policies via CFN
- `cluster-addons`: Shared add-on stack — AWS Load Balancer Controller, cluster-autoscaler, external-dns, cert-manager, CloudWatch Container Insights, and kube-prometheus-stack
- `namespace-management`: Namespace manifest schema (ResourceQuota, LimitRange, NetworkPolicy defaults, admin/developer RoleBindings) for per-team isolation
- `team-onboarding`: Automation scripts for provisioning a new team namespace, vending an IRSA role, and validating the resulting RBAC/network posture

### Modified Capabilities

_(none — greenfield repository)_

## Non-goals

- Application-level Helm charts or workload deployments (tenant responsibility)
- Multi-region active-active setup (single-region per environment for now)
- Service mesh (Istio / Linkerd) — NetworkPolicy provides sufficient L4 isolation initially
- Secrets injection tooling (External Secrets Operator) — teams use SDK-native Secrets Manager access via IRSA
- Automated cluster upgrades — upgrade runbook will be documented but not automated in this phase

## Impact

- All directories under `eks-infra/` are currently empty; this change populates `vpc/`, `clusters/`, `iam/`, `addons/`, `namespaces/`, `scripts/`, and `docs/`
- IAM permission boundaries must be defined before any IRSA role CFN stacks are deployed
- The cluster-addons add-on stack is a shared service dependency for all subsequent team onboarding
- No existing production systems are affected (greenfield)

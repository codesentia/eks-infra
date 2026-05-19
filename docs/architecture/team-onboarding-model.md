# Team Onboarding Model

## Overview

Each application team that deploys workloads on the EKS platform is provisioned with:
- A dedicated **Kubernetes namespace** with resource isolation controls
- An **IRSA role** for AWS service access from their pods
- **RBAC bindings** for their admin and developer groups

This model ensures teams are isolated from each other at the network, resource, and IAM layers, while sharing the cluster's compute and platform services.

---

## Namespace Isolation Model

Every team namespace is provisioned with the following resources:

### ResourceQuota

Limits the total CPU and memory the namespace may consume across all pods. Prevents a single team from exhausting cluster capacity.

**Default tier values:**

| Resource | Request limit | Hard limit |
|----------|--------------|------------|
| `requests.cpu` | 4 cores | — |
| `limits.cpu` | — | 8 cores |
| `requests.memory` | 8Gi | — |
| `limits.memory` | — | 16Gi |

Quota values are parameterised per team at onboarding time. Teams that need higher limits must request an increase through the platform team.

### LimitRange

Sets default resource requests and limits on containers that do not specify their own. Without a LimitRange, a pod with no resource spec consumes unaccounted resources and can trigger eviction of other pods.

**Default values:**

| Resource | Default request | Default limit |
|----------|----------------|--------------|
| CPU | `100m` | `500m` |
| Memory | `128Mi` | `512Mi` |

Teams should override these in their pod specs when their workload has known resource requirements.

### NetworkPolicy

A default-deny NetworkPolicy is applied at namespace creation. It blocks all ingress and egress traffic by default, then explicitly permits:

| Direction | Allowed | Blocked |
|-----------|---------|---------|
| Ingress | From pods within the same namespace | From all other namespaces |
| Ingress | From the `kube-system` namespace (ALB controller, ingress routing) | From the internet (direct pod access) |
| Egress | To pods within the same namespace | To all other namespaces |
| Egress | To `kube-dns` (`kube-system`, UDP/TCP 53) | Cross-namespace service calls (must be explicitly added) |

Teams that need to call services in another namespace must submit a PR adding an explicit NetworkPolicy allow rule. This is intentional — cross-namespace calls are an architectural decision, not a default behaviour.

### RBAC

Two role bindings are created per namespace:

| Binding | Group | Role | Permissions |
|---------|-------|------|------------|
| `<team>-admins` | `<team>-admins` (IdP group) | `admin` (ClusterRole) | Full control of all resources in the namespace |
| `<team>-developers` | `<team>-developers` (IdP group) | `developer` (custom Role) | Read/write: Deployments, Services, ConfigMaps, Ingresses; Read-only: Pods, Events, Logs; No access: RBAC resources, Secrets (direct), ResourceQuota |

The `developer` role deliberately excludes direct Secret access — teams should use IRSA and the AWS SDK to read secrets from Secrets Manager, not store them as Kubernetes Secrets.

---

## IRSA Role per Team

Each team is provisioned with an IRSA role scoped to their namespace and a designated service account:

- **Role name:** `eks-<cluster>-<team>-role`
- **Namespace:** `<team-name>`
- **Service account:** `<team-name>-sa`

The policy attached to this role is defined at onboarding time based on the team's stated AWS access requirements (e.g., specific Secrets Manager paths, S3 bucket ARNs). The platform team reviews and approves the policy before deployment.

Teams annotate their pods' service accounts with the role ARN to receive credentials:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: <team>-sa
  namespace: <team>
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<ACCOUNT>:role/eks-<cluster>-<team>-role
```

---

## Onboarding Process

### Inputs required from the team

| Input | Example | Notes |
|-------|---------|-------|
| Team name | `payments` | Becomes the namespace name; must be lowercase, alphanumeric, hyphens |
| Environment | `dev` or `prod` | |
| Admin group name | `payments-admins` | Must exist in the IdP (SSO/LDAP) |
| Developer group name | `payments-developers` | Must exist in the IdP |
| AWS access requirements | Secrets Manager paths, S3 buckets | Used to author the IRSA policy |
| Quota tier | `standard` / `large` | Determines ResourceQuota values |

### What the operator does vs what is automated

| Step | Who | How |
|------|-----|-----|
| Gather inputs from team | Operator | Team fills out onboarding form or opens a ticket |
| Author namespace manifest bundle | Automated | `scripts/onboard-team.py` generates from template |
| Author IRSA policy document | Operator | Review team's AWS access requirements, write minimal policy |
| Open PR for namespace manifests + IRSA CFN stack | Automated (script) or Operator | PR reviewed by platform team |
| PR merged → namespace applied | ArgoCD (auto-sync) | Within minutes of merge |
| IRSA CFN stack deployed | Operator | `aws cloudformation deploy` with change set |
| Validate namespace posture | Operator | `scripts/validate-namespace.py --team <team> --env <env>` |
| Notify team | Operator | Share namespace name, service account name, IRSA role ARN |

### Idempotency

The onboarding script is idempotent — running it a second time for the same team produces no changes and returns successfully. This allows the script to be re-run safely to regenerate or repair a namespace bundle.

---

## Offboarding

When a team is removed from the platform:

1. Annotate the namespace manifest in `namespaces/<team-name>/` with a deletion marker (or simply delete the directory).
2. Open a PR — platform team reviews and confirms no running workloads remain.
3. PR merged → ArgoCD prunes the namespace and all resources within it (`prune: true` in sync policy).
4. Delete the IRSA CFN stack: `aws cloudformation delete-stack --stack-name iam-irsa-<team>-<env>`.
5. Delete the Cloudformation IAM role.
6. Archive or delete the team's ECR repositories as appropriate.

Namespace deletion via ArgoCD prune will terminate all running pods in the namespace. Confirm workload migration before merging the offboarding PR.

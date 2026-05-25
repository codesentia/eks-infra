# IAM and Security Model

## Overview

The platform uses two distinct IAM identities for AWS access:

1. **Node IAM role** — attached to the EC2 instances in every node group. Contains only the permissions the instance needs to function as an EKS worker node. Pods do not use this role.
2. **IRSA roles** — one per component (and one per tenant team). Bound to a specific Kubernetes service account in a specific namespace via the EKS OIDC provider. Pods use these roles to call AWS APIs.

This model ensures every AWS API call can be attributed to a specific Kubernetes workload identity and carries only the permissions that workload legitimately requires.

---

## Node IAM Role

**CFN stack:** `iam-node-role-dev` (template: `iam/node-role.yaml`)  
**Role name:** `eks-thor-node-role`  
**ARN export:** `iam-node-role-dev-NodeRoleArn`  
**Attached to:** All managed node group instances (both `system` and `application` node groups)  
**Trust policy:** `ec2.amazonaws.com` only — no other service can assume this role

### Attached AWS managed policies

| Policy | Why required |
|--------|-------------|
| `AmazonEKSWorkerNodePolicy` | Allows the node to describe the cluster and register with the EKS control plane |
| `AmazonEC2ContainerRegistryReadOnly` | Allows the node (kubelet) to pull container images from ECR |
| `AmazonEKS_CNI_Policy` | Allows the VPC CNI plugin (`aws-node` DaemonSet) to manage pod networking ENIs — assign, unassign, and describe ENIs on the instance. Will be migrated to a VPC CNI IRSA role once the cluster OIDC provider is available. |
| `AmazonSSMManagedInstanceCore` | Enables SSM Session Manager access to nodes — no SSH ports required |

### Explicitly excluded

The node role does **not** grant:
- `AmazonEBSCSIDriverPolicy` — EBS CSI access is granted via a dedicated IRSA role; attaching it here would give all pods implicit EBS access via the node identity
- `cloudwatch:PutMetricData` / `logs:*` — CloudWatch agent and Fluent Bit use IRSA roles, not node-level permissions
- `s3:*` — no bucket access at the node level
- `secretsmanager:*` — secrets are accessed via IRSA only
- Any cross-account or cross-service permissions

### Consuming the role ARN

The eksctl ClusterConfig references the node role ARN via the CFN export:

```yaml
# clusters/thor.yaml (excerpt)
managedNodeGroups:
  - name: system
    iam:
      instanceRoleARN: !ImportValue iam-node-role-dev-NodeRoleArn
```

---

## IRSA Role Template

**CFN template:** `iam/irsa-role.yaml`  
**Role name pattern:** `eks-<cluster-name>-<component-name>-role`

### CFN Parameters

| Parameter | Description |
|-----------|-------------|
| `ClusterName` | EKS cluster name (e.g., `eks-dev`) |
| `OIDCIssuerUrl` | Cluster OIDC issuer URL, read from Parameter Store at `/eks/<env>/oidc-issuer-url` |
| `Namespace` | Kubernetes namespace of the service account |
| `ServiceAccountName` | Kubernetes service account name |
| `ComponentName` | Used to construct the role name suffix (e.g., `alb-controller`) |
| `PolicyDocument` | JSON inline policy document for this role |

### Trust policy structure

The trust policy binds the role to a single service account in a single namespace, using the `StringEquals` condition on both the subject (`sub`) and audience (`aud`) claims:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/<OIDC_ISSUER>"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "<OIDC_ISSUER>:sub": "system:serviceaccount:<NAMESPACE>:<SERVICE_ACCOUNT_NAME>",
          "<OIDC_ISSUER>:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
```

Using `StringEquals` (not `StringLike`) on the `sub` claim prevents wildcard abuse — a service account in a different namespace cannot assume this role even if it has the same name.

### How the role is consumed

The Kubernetes service account is annotated with the role ARN at creation time:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: <SERVICE_ACCOUNT_NAME>
  namespace: <NAMESPACE>
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<ACCOUNT_ID>:role/eks-<cluster>-<component>-role
```

The EKS Pod Identity webhook injects a projected service account token into pods using this service account. The AWS SDK credential chain automatically exchanges this token for temporary STS credentials via `sts:AssumeRoleWithWebIdentity`.

---

## Per-Component IRSA Roles

| Component | Namespace | Service Account | Permission scope | Policy source |
|-----------|-----------|-----------------|-----------------|---------------|
| AWS Load Balancer Controller | `kube-system` | `aws-load-balancer-controller` | Create/update/delete ALBs, NLBs, target groups, listeners, security groups, WAF associations | `iam/policies/alb-controller-policy.json` (AWS-published) |
| Cluster Autoscaler | `kube-system` | `cluster-autoscaler` | `autoscaling:Describe*`, `autoscaling:SetDesiredCapacity`, `autoscaling:TerminateInstanceInAutoScalingGroup` — scoped to ASGs tagged with `k8s.io/cluster-autoscaler/<cluster-name>=owned` | `iam/policies/cluster-autoscaler-policy.json` |
| EBS CSI Driver | `kube-system` | `ebs-csi-controller-sa` | Create/delete/attach/detach EBS volumes; create snapshots — AWS-managed `AmazonEBSCSIDriverPolicy` | AWS managed policy |
| Team workloads (per-team) | `<team-name>` | `<team-name>-sa` | Scoped to that team's Secrets Manager paths, S3 buckets, etc. | Defined at team onboarding time |

### Why the ALB controller policy is large

The ALB controller manages the full lifecycle of AWS load balancers on behalf of Kubernetes `Ingress` resources. This requires permissions across EC2 (security groups, target groups), Elastic Load Balancing (ALB/NLB), ACM (certificate lookup), and WAF. The AWS-published policy is the minimal set required — it cannot be meaningfully reduced without breaking functionality.

### Why the autoscaler policy is tag-scoped

The autoscaler only needs to scale the node groups in its own cluster. Using an IAM condition on the `k8s.io/cluster-autoscaler/<cluster-name>` tag ensures the autoscaler in the `dev` cluster cannot accidentally scale node groups belonging to the `prod` cluster, even if both clusters exist in the same AWS account.

---

## Cloudflare API Token Security Model

The Cloudflare API token is not an AWS IAM credential, but its lifecycle is managed alongside the IAM model for consistency.

### Token scope

| Dimension | Value |
|-----------|-------|
| Permission | `Zone → DNS → Edit` |
| Zone resources | Specific zone(s) used by this cluster only |
| Account-level access | None |
| IP restrictions | Optional — can be scoped to NAT Gateway EIP CIDRs |

### Storage and injection path

```
Cloudflare portal
    │
    │  create scoped token
    ▼
AWS Secrets Manager
    /eks/<env>/cloudflare-api-token
    │
    │  bootstrap step (one-time, imperative)
    ▼
Kubernetes Secret: cloudflare-api-token
    ├── Namespace: kube-system      (consumed by external-dns)
    └── Namespace: cert-manager     (consumed by cert-manager ClusterIssuer)
```

The token is never written to the git repository, never stored in a ConfigMap, and never passed as an environment variable at the node level.

### Rotation procedure

See `docs/runbooks/cloudflare-token-rotation.md`. The token can be rotated without downtime:
1. Create new token in Cloudflare.
2. Update Secrets Manager.
3. Re-run the bootstrap injection to update both Kubernetes Secrets.
4. Verify external-dns and cert-manager are functioning.
5. Revoke the old token in Cloudflare.

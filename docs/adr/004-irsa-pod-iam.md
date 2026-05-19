# ADR-004: IRSA for All Pod-Level AWS Access

**Status:** Accepted  
**Date:** 2026-05-19

## Context

Pods running on EKS that need to call AWS APIs (e.g., creating load balancers, reading Secrets Manager, writing CloudWatch metrics) require AWS credentials. There are several mechanisms available:

1. **EC2 instance profile** — the node's IAM role is inherited by all pods on that node via the instance metadata service (IMDS).
2. **Static IAM user credentials** — access key / secret key stored as a Kubernetes Secret.
3. **IRSA (IAM Roles for Service Accounts)** — a Kubernetes service account is annotated with an IAM role ARN; pods using that service account receive short-lived credentials via a projected service account token validated by the EKS OIDC provider.

The platform will run multiple components (ALB controller, cluster autoscaler, external-dns, EBS CSI driver) and multiple tenant workloads, each with distinct AWS permission requirements.

## Decision

All pod-level AWS API access uses IRSA exclusively. No pod may inherit credentials from the EC2 node instance profile. No static IAM user credentials are stored in Kubernetes Secrets or repository files.

The node IAM role is scoped to the minimum permissions required for the EC2 instance itself (ECR image pull, CloudWatch agent reporting, EBS CSI bootstrap). It does not carry permissions intended for pods.

## Rationale

### Least-privilege per workload

Instance profile IAM applies the same permissions to every pod on a node, regardless of which component the pod belongs to. If the node role has `s3:GetObject` (needed by one add-on), every compromised pod on that node can read from S3.

IRSA binds a role to a specific Kubernetes service account in a specific namespace. The trust policy uses `StringEquals` conditions on the OIDC subject claim:

```json
"StringEquals": {
  "<OIDC_ISSUER>:sub": "system:serviceaccount:<NAMESPACE>:<SA_NAME>",
  "<OIDC_ISSUER>:aud": "sts.amazonaws.com"
}
```

A credential obtained via this mechanism is only valid for the service account it was issued to, in the namespace it was issued for.

### Short-lived credentials

IRSA delivers credentials with a TTL of 1 hour (default) via the AWS SDK credential chain. There are no long-lived access keys to rotate, leak, or audit.

### Auditability

CloudTrail records the IAM role ARN and the Kubernetes service account name in every API call made via IRSA. This makes it possible to attribute any AWS API call to a specific pod identity without log correlation gymnastics.

### No IMDS block required

Because pods do not rely on the instance profile, there is no need to block IMDS access from pods (via `--restrict-metadata-server-access` or network policies targeting `169.254.169.254`). IRSA simply does not use IMDS.

## Trust Policy Pattern

Every IRSA role created by this platform follows this trust policy structure:

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

`OIDC_ISSUER`, `NAMESPACE`, and `SERVICE_ACCOUNT_NAME` are CFN parameters. The same template (`iam/irsa-role.yaml`) is reused for every component IRSA role.

## Node IAM Role Minimum Permissions

The node role carries only what the EC2 instance needs to function as an EKS worker node:

| Permission set | Why required |
|----------------|--------------|
| `AmazonEKSWorkerNodePolicy` | Allows the node to register with the EKS control plane |
| `AmazonEC2ContainerRegistryReadOnly` | Allows the node to pull images from ECR |
| `AmazonEKS_CNI_Policy` | Allows the VPC CNI plugin to manage pod networking ENIs |
| CloudWatch agent actions (`cloudwatch:PutMetricData`, `logs:CreateLogGroup`, etc.) | Required for the CloudWatch Container Insights DaemonSet |

The node role does **not** have:
- Any `s3:*` permissions
- Any `secretsmanager:*` permissions
- Any Route 53 or other service permissions

## Alternatives Considered

### EC2 instance profile for all pods

Grant all required permissions to the node IAM role and let pods inherit them via IMDS.

**Rejected because:**
- A single compromised pod gains all permissions granted to the node.
- Multiple components (ALB controller, autoscaler, external-dns) have conflicting permission scopes — unioning them onto one role creates an over-privileged node.
- Cannot scope permissions per team namespace; all tenant pods would share the same AWS permissions.

### Static IAM user credentials in Kubernetes Secrets

Create IAM users per component, store access keys as Kubernetes Secrets.

**Rejected because:**
- Long-lived credentials require rotation and create a persistent exfiltration risk.
- Kubernetes Secrets are base64-encoded, not encrypted at rest by default (without KMS envelope encryption enabled on the cluster).
- No automatic expiry; a leaked key remains valid until manually rotated.

## Consequences

- The OIDC provider must be associated with the cluster immediately after creation (before any IRSA-dependent add-on can be deployed).
- The OIDC issuer URL must be stored (in Parameter Store at `/eks/<env>/oidc-issuer-url`) so downstream CFN stacks can reference it without a manual lookup.
- Every Kubernetes service account that needs AWS access must be annotated: `eks.amazonaws.com/role-arn: <ROLE_ARN>`.
- Tenant teams that need AWS access (e.g., to read Secrets Manager) must be onboarded with a dedicated IRSA role scoped to their namespace and service account.

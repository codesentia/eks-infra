## Context

The EKS node IAM role is a hard prerequisite for cluster creation. When eksctl creates a managed node group, it attaches this role to the EC2 launch template — the nodes assume it at boot to pull container images, emit logs, and mount EBS volumes. Without the role ARN, the eksctl ClusterConfig cannot be authored.

The role is a pure AWS IAM construct: no cluster-level resources, no Kubernetes objects. It belongs in `iam/` as a standalone CFN stack, consistent with the VPC pattern in `vpc/`. The stack exports the role ARN so the future eksctl ClusterConfig can reference it by name without a lookup.

The `github-actions-dev` IAM role (in `bootstrap/`) currently lacks `iam:PassRole` — needed because CloudFormation passes the node role to EC2 when creating the launch template. This is a one-time bootstrap stack update.

## Goals / Non-Goals

**Goals:**
- Deliver a least-privilege node role CFN stack that eksctl can reference by ARN
- Wire the stack into the Makefile, CI linting, and deploy workflow (consistent with vpc pattern)
- Update bootstrap IAM role with `iam:PassRole` scoped to the node role ARN pattern
- Update architecture docs and the docs index to reflect the new stack

**Non-Goals:**
- IRSA roles — separate change, depends on cluster OIDC provider which doesn't exist yet
- `prod` node role — follows identically after dev cluster is validated
- Permission boundaries on the node role — AWS managed policies + EKS node trust policy is sufficient for this stage
- Node role for Fargate profiles — not used (managed node groups only per ADR-003)

## Decisions

### D1 — AWS managed policies only, no inline policy

**Decision:** Attach the four AWS-managed policies for EKS managed nodes rather than authoring an inline policy:
- `AmazonEKSWorkerNodePolicy`
- `AmazonEC2ContainerRegistryReadOnly`
- `AmazonEKS_CNI_Policy`
- `AmazonSSMManagedInstanceCore`

**Rationale:** AWS managed policies are maintained by AWS — when EKS adds a new required permission (as it has in past releases), the managed policy is updated automatically without any stack change. Inline policies would require manual updates each time EKS or a node component changes its permission requirements. `AmazonSSMManagedInstanceCore` is included to enable SSM Session Manager access to nodes without opening SSH ports — a security improvement over key-based access.

**EBS CSI note:** The EBS CSI driver uses IRSA (a future IRSA role), so `AmazonEBSCSIDriverPolicy` is intentionally absent from the node role. Attaching it here would give all pods on the node implicit EBS access via the node identity — violating least-privilege. The node role has no EBS permissions.

**CNI note:** `AmazonEKS_CNI_Policy` on the node role is the default; it will be migrated to an IRSA role for the VPC CNI when the cluster OIDC provider is available. The managed policy on the node role is a safe interim.

---

### D2 — Trust policy scoped to `ec2.amazonaws.com` only

**Decision:** The role trust policy allows only `ec2.amazonaws.com` to assume the role. No other principals.

**Rationale:** The node role is assumed by EC2 instances (the nodes themselves). It must not be assumable by Lambda, ECS, or any other service. Scoping the trust policy to `ec2.amazonaws.com` prevents lateral movement if an attacker obtains access to another AWS service in the same account.

---

### D3 — Stack name `iam-node-role-dev`, export name `iam-node-role-dev-NodeRoleArn`

**Decision:** Follow the established pattern: stack name `<template>-<env>`, export name `${AWS::StackName}-<Resource>`.

**Rationale:** Consistent with `vpc-dev` and the export pattern used by vpc outputs (`vpc-dev-VpcId` etc.). The eksctl ClusterConfig can reference the ARN via `Fn::ImportValue: iam-node-role-dev-NodeRoleArn` or as a literal value fetched once and placed in the parameter file.

---

### D4 — `iam:PassRole` added to bootstrap `github-actions-dev` role

**Decision:** Update `bootstrap/github-actions-role.yaml` to add `iam:PassRole` scoped to `arn:aws:iam::*:role/eks-*-node-role`.

**Rationale:** CloudFormation requires the calling principal to have `iam:PassRole` on any IAM role that will be attached to an EC2 resource. Without it, the `deploy-node-role-dev` workflow will fail at change set creation. Scoping to `eks-*-node-role` is narrow enough — it cannot be used to pass arbitrary roles.

---

### D5 — Deploy workflow mirrors `deploy-vpc-dev.yaml` pattern

**Decision:** `.github/workflows/deploy-node-role-dev.yaml` triggers on `push` to `main` with `paths: iam/**` and `workflow_dispatch`. Uses `make deploy-node-role-dev`.

**Rationale:** Identical pattern to the VPC deploy workflow — thin YAML, all logic in Make. The `iam/**` path filter means changes to any future IRSA template also trigger this workflow, which is intentional: any `iam/` change creates a change set for review.

**Trade-off:** This means adding a new IRSA template in a future change will re-trigger the node role deploy workflow (because `paths: iam/**` is broad). That is safe — creating a new change set for an unchanged stack is idempotent. A future refactor could split per-template, but that is premature now.

## Risks / Trade-offs

| Risk | Mitigation |
|---|---|
| `AmazonEKS_CNI_Policy` on node role gives all pods implicit ENI access until CNI IRSA is configured | Accepted for now — CNI IRSA migration is planned as part of the cluster addons change |
| `iam:PassRole` on `github-actions-dev` scoped to `eks-*-node-role` could pass any role matching that pattern | Pattern is specific enough; the role can only be passed to CFN, not assumed directly |
| eksctl requires the node role ARN at cluster creation time — if the stack isn't deployed first, cluster creation fails | Documented as a prerequisite in the cluster bootstrap runbook |

## Migration Plan

1. Update `bootstrap/github-actions-role.yaml` — add `iam:PassRole` statement
2. Deploy updated bootstrap stack via change set (manual operator step)
3. Author `iam/node-role.yaml` CFN template and parameter file
4. Add `deploy-node-role-dev` Makefile target
5. Author `.github/workflows/deploy-node-role-dev.yaml`
6. Run `make ci` locally — confirms lint passes
7. Update `docs/architecture/iam-security-model.md` and `docs/README.md`
8. Push branch → CI lints, merge → deploy workflow creates `iam-node-role-dev` change set
9. Review and execute the change set — verify role ARN output

## Open Questions

_(none)_

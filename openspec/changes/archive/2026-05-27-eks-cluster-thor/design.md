## Context

`vpc-dev` is the intended VPC for the `thor` cluster — it will be deployed from `vpc/vpc.yaml` (three-tier layout: public / private / intra). It is not deployed yet; cluster creation is blocked on it. `berry-vpc` was a temporary external VPC and is not used here.

The `vpc-dev` stack exports the following values the ClusterConfig needs:

| Export | Description |
|---|---|
| `vpc-dev-VpcId` | VPC ID |
| `vpc-dev-PrivateSubnetA/B` | Worker node subnets (us-east-1a/b) |
| `vpc-dev-IntraSubnetA/B` | Control-plane ENI subnets (us-east-1a/b) |
| `vpc-dev-NodeSecurityGroupId` | Additional SG for node groups |
| `vpc-dev-ControlPlaneSecurityGroupId` | Additional SG for control plane |

The node role export is also CFN-managed: `iam-node-role-dev-NodeRoleArn`.

eksctl does not natively interpolate CloudFormation exports — it requires literal IDs. The Makefile is the resolution layer: it reads CFN exports at runtime, substitutes them into a template, and feeds the rendered config to eksctl. No IDs are hardcoded in any committed file.

eksctl manages its own internal CFN stacks (`eksctl-thor-cluster`, `eksctl-thor-nodegroup-*`). These are separate from the hand-authored stacks in `vpc/` and `iam/`.

## Goals / Non-Goals

**Goals:**
- `clusters/thor.yaml.tpl` — eksctl ClusterConfig template with `${VAR}` placeholders for all VPC-derived and IAM values
- Makefile resolution layer: reads `vpc-dev` and `iam-node-role-dev` CFN exports, renders the template, calls eksctl
- Three-tier subnet layout: worker nodes in private subnets, control-plane ENIs in intra subnets
- Two managed node groups: `system` (tainted) and `application`
- Kubernetes 1.35, control-plane logging, public API endpoint (dev)
- OIDC provider association as a documented post-create step

**Non-Goals:**
- Fargate profiles — managed node groups only (ADR-003)
- Prod cluster config
- Cluster add-ons or IRSA roles — separate changes
- Hardcoded VPC IDs anywhere in committed files

## Decisions

### D1 — Worker nodes in private subnets; control-plane ENIs in intra subnets

**Decision:** Managed node groups use `vpc-dev` private subnets. EKS control-plane ENIs use `vpc-dev` intra subnets. This is the three-tier design as specified in ADR-002.

**Rationale:** Intra subnets have no internet route and no NAT — they exist solely for the EKS control-plane cross-account ENIs. Isolating control-plane traffic from pod-to-pod traffic in private subnets is the intended architecture. `vpc/vpc.yaml` was designed with this layout; `vpc-dev` will provide all three tiers.

---

### D2 — Node instance types: system=m7i-flex.large, application=m7i-flex.xlarge

**Decision:** Both `system` and `application` node groups use `m7i-flex.large` (2 vCPU, 8 GiB).

**Rationale:** `m7i-flex` is the 7th-gen Intel flexible family — broader availability than `m6i` across account types and regions. Using `large` for both groups keeps dev costs minimal while still providing enough capacity for add-ons and light tenant workloads. Upgrade to `xlarge` for application nodes when workload demands it.

---

### D3 — Node group sizing: min=1, desired=1, max=3 for dev

**Decision:** Both node groups start at 1 node, scale to max 3 for dev.

**Rationale:** Dev minimises cost while the cluster is being configured. The cluster autoscaler (future change) handles scaling within the 1–3 range.

---

### D4 — Public API endpoint enabled for dev, no CIDR restriction

**Decision:** `publicAccess: true`, `privateAccess: true`, no `publicAccessCIDRs` restriction.

**Rationale:** Dev operators need `kubectl` access without VPN. The control plane is protected by Kubernetes RBAC. For prod, the endpoint will be private-only.

---

### D5 — eksctl creates cluster directly; no CFN change-set wrapper

**Decision:** `eksctl create cluster -f <rendered>` is the creation command. No CFN change-set wraps the eksctl call.

**Rationale:** The change-set convention applies to the CFN templates we author directly (`vpc/`, `iam/`). eksctl-managed stacks are internal implementation details. The ClusterConfig template committed to git is the reviewable artifact.

---

### D6 — OIDC provider associated via `eksctl utils`, not in ClusterConfig

**Decision:** OIDC association runs post-create: `eksctl utils associate-iam-oidc-provider --cluster thor --approve`. The issuer URL is stored in Parameter Store at `/eks/thor/oidc-issuer-url`.

**Rationale:** Keeping OIDC association explicit makes the dependency visible. It cannot be silently skipped, and the Parameter Store entry is the handoff point for all future IRSA role stacks.

---

### D7 — ClusterConfig is a template; Makefile resolves CFN exports at runtime

**Decision:** `clusters/thor.yaml.tpl` is committed to git with `${VAR}` placeholders for all values derived from CFN exports:

```
${VPC_ID}                  ← vpc-dev-VpcId
${PRIVATE_SUBNET_A}        ← vpc-dev-PrivateSubnetA
${PRIVATE_SUBNET_B}        ← vpc-dev-PrivateSubnetB
${INTRA_SUBNET_A}          ← vpc-dev-IntraSubnetA
${INTRA_SUBNET_B}          ← vpc-dev-IntraSubnetB
${NODE_SG_ID}              ← vpc-dev-NodeSecurityGroupId
${CONTROL_PLANE_SG_ID}     ← vpc-dev-ControlPlaneSecurityGroupId
${NODE_ROLE_ARN}           ← iam-node-role-dev-NodeRoleArn
```

The Makefile `resolve-cluster-thor` target fetches these exports via `aws cloudformation describe-stacks`, exports them as environment variables, and runs `envsubst < clusters/thor.yaml.tpl > /tmp/thor-resolved.yaml`. Both `dry-run-cluster-thor` and `create-cluster-thor` depend on `resolve-cluster-thor`.

**Rationale:** No infrastructure IDs are hardcoded in committed files. The template is environment-agnostic — swapping `vpc-dev` for a different VPC stack requires only a change to the Makefile export resolution, not to the ClusterConfig template itself. `envsubst` is available on all Linux distros without extra dependencies.

**`clusters/thor.yaml.tpl` is not linted by `make lint-all`** — it contains `${VAR}` placeholders that are not valid YAML values and would fail cfn-lint (it is an eksctl config, not a CFN template anyway). The lint-all target already scopes to `vpc/` and `iam/` only.

## Risks / Trade-offs

| Risk | Mitigation |
|---|---|
| `vpc-dev` must be deployed before cluster creation | Makefile `resolve-cluster-thor` will fail with a clear error if the stack does not exist or exports are missing |
| `eksctl create cluster` takes ~15 min and is not idempotent if interrupted | Run `make dry-run-cluster-thor` first; if interrupted, check `eksctl-thor-*` CFN stacks before retrying |
| `envsubst` substitutes ALL `${VAR}` patterns — any unset variable becomes an empty string silently | Resolution script validates that all required exports are non-empty before calling envsubst; fails fast if any is missing |
| OIDC provider registration skipped post-create — all IRSA roles will fail | `post-create-thor` Makefile target makes this a single explicit step; cluster-bootstrap runbook documents the order |

## Migration Plan

1. Deploy `vpc-dev` stack (separate change — prerequisite)
2. Validate template: `make dry-run-cluster-thor` — resolves exports and calls eksctl --dry-run
3. Create cluster: `make create-cluster-thor` (~15 minutes)
4. Verify nodes: `kubectl get nodes`
5. Post-create: `make post-create-thor` — OIDC association + Parameter Store
6. Verify API access and kubeconfig

Rollback: `eksctl delete cluster --name thor` (deletes all eksctl-managed CFN stacks; VPC and IAM stacks are unaffected)

## Open Questions

_(none)_

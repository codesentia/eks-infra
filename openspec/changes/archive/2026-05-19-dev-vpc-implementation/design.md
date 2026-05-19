## Context

The `vpc-networking` spec is fully defined and the architecture decisions are recorded in ADR-001 and ADR-002. The `vpc/` directory is empty. This design covers the CFN template structure, parameter strategy, and output naming conventions needed to implement `vpc/vpc.yaml` for the dev environment.

The template must be reusable for prod (different CIDR, 3 AZs) with only parameter changes — no structural differences between dev and prod templates.

## Goals / Non-Goals

**Goals:**
- Produce a single `vpc/vpc.yaml` CFN template parameterised for any environment
- Cover all resources specified in `vpc-networking`: VPC, subnets, IGW, NAT Gateways, route tables, VPC endpoints, security groups
- Export all outputs with stable, predictable names consumable by downstream stacks (IAM, eksctl)
- Validate the template lints cleanly (`cfn-lint`) before any deployment

**Non-Goals:**
- Prod deployment (separate change)
- VPC Flow Logs
- IPv6
- Transit Gateway / VPC peering
- Custom DHCP options

## Decisions

### D1 — Single parameterised template (not separate dev/prod templates)

**Decision:** One `vpc/vpc.yaml` template with parameters for `Environment`, `VpcCidr`, and `AZCount` (2 or 3). A `Parameters/` section in the same directory holds environment-specific values files.

**Rationale:** Structural duplication between dev and prod templates is a maintenance hazard. A parameter diff is reviewable; a structural diff is not. CFN supports `--parameter-overrides` and parameter files natively.

**Alternative considered:** Separate `vpc/vpc-dev.yaml` and `vpc/vpc-prod.yaml` — rejected because any structural fix must be applied to both files.

---

### D2 — AZ count via `Fn::If` conditions, not separate resource blocks

**Decision:** Use CFN `Conditions` (`IsThreeAZ: !Equals [!Ref AZCount, "3"]`) to conditionally create the third AZ's subnets, NAT Gateway, and route table. Dev uses 2 AZs; prod uses 3.

**Rationale:** Keeps the template a single file while supporting both topologies. The third AZ resources are simply `!If [IsThreeAZ, <resource>, !Ref AWS::NoValue]`.

**Alternative considered:** Separate Mappings with AZ lists — rejected because Mappings cannot drive dynamic resource creation counts.

---

### D3 — Output naming convention: `<StackName>-<ResourceType>-<Qualifier>`

**Decision:** All CFN Outputs follow the pattern `<StackName>-<ResourceType>-<Qualifier>` and are exported with `Export: Name: !Sub "${AWS::StackName}-<ResourceType>-<Qualifier>"`.

Examples:
```
vpc-dev-VpcId
vpc-dev-PublicSubnetA
vpc-dev-PublicSubnetB
vpc-dev-PrivateSubnetA
vpc-dev-PrivateSubnetB
vpc-dev-IntraSubnetA
vpc-dev-IntraSubnetB
vpc-dev-NodeSecurityGroupId
vpc-dev-ControlPlaneSecurityGroupId
```

**Rationale:** Stack name is the natural namespace for cross-stack references (`Fn::ImportValue`). Predictable naming allows downstream templates to reference outputs without an explicit lookup — they can reconstruct the export name from the known stack name.

---

### D4 — VPC endpoints in intra subnets (interface) and all private/intra route tables (gateway)

**Decision:**
- S3 Gateway endpoint: associated with all private and intra route tables
- Interface endpoints (ECR API, ECR DKR, Secrets Manager, SSM, SSMMessages): deployed in intra subnets, with a dedicated endpoint security group allowing HTTPS from the node security group

**Rationale:** Interface endpoints consume IPs from the subnet they are placed in. Intra subnets have no internet route, making them the correct placement for endpoints that should not be reachable from the public internet. The S3 Gateway endpoint is free and has no subnet placement — it attaches to route tables.

---

### D5 — Security groups: node SG and control-plane additional SG only

**Decision:** Two security groups are created:
1. `NodeSecurityGroup` — attached to all worker nodes; allows all intra-SG traffic, inbound port 10250 from the EKS cluster SG, unrestricted outbound
2. `ControlPlaneAdditionalSG` — referenced by the eksctl `ClusterConfig` as an additional security group on the control plane; allows the control plane to reach node webhooks (port 443) and kubelet (port 10250)

The EKS-managed cluster security group (created automatically by EKS) handles control-plane-to-node communication for managed node groups; these two SGs supplement it.

**Rationale:** Minimal SG surface — only what EKS and the ALB controller require. The ALB controller creates its own SGs dynamically; those are not pre-created here.

## Risks / Trade-offs

| Risk | Mitigation |
|------|-----------|
| CFN `Fn::If` with `AWS::NoValue` for third AZ resources can produce confusing diffs | Document the condition pattern in a template comment; test both 2-AZ and 3-AZ deployments before prod |
| Cross-stack `Fn::ImportValue` creates a hard dependency — downstream stacks cannot be deleted before this one | Documented in bootstrap runbook; prod VPC is the last to be deleted in a teardown |
| NAT Gateway EIP allocation fails if account EIP quota is exhausted | Check EIP quota before deployment (`aws service-quotas get-service-quota`) |
| Interface endpoint security group too permissive | Scope HTTPS inbound to the node SG CIDR block only, not `0.0.0.0/0` |

## Migration Plan

This is a greenfield deployment — no existing VPC to migrate.

**Deployment steps:**
1. Run `cfn-lint vpc/vpc.yaml` — resolve all warnings
2. Create change set: `aws cloudformation deploy --no-execute-changeset ...`
3. Review change set in AWS console or CLI
4. Execute change set
5. Verify all outputs are present: `aws cloudformation describe-stacks --stack-name vpc-dev`

**Rollback:** Delete the stack (`aws cloudformation delete-stack --stack-name vpc-dev`). Safe to delete as no downstream stacks exist yet.

## Open Questions

_(none — all parameters resolved in ADR-002: dev CIDR `10.10.0.0/16`, 2 AZs, no additional constraints)_

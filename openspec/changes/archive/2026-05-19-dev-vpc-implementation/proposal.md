## Why

The `vpc-networking` capability was designed and specified but never implemented — no CloudFormation templates exist under `vpc/`. The dev environment VPC is the foundational dependency for every subsequent layer (IAM, cluster, add-ons), so it must be the first concrete deliverable.

## What Changes

- New CFN template `vpc/vpc.yaml` implementing the three-tier subnet layout (public / private / intra) for the dev environment: 2 AZs, CIDRs `10.10.0.0/16`, one NAT Gateway per AZ, Internet Gateway, and all route tables
- New VPC endpoints in the template: S3 Gateway endpoint and Interface endpoints for ECR API, ECR DKR, Secrets Manager, SSM, SSMMessages
- Node security group and control-plane additional security group with least-privilege inbound/outbound rules
- CFN Outputs block exporting VPC ID, all subnet IDs (by tier and AZ), and security group IDs for consumption by downstream IAM and eksctl stacks
- Deployment script / Makefile target for creating and executing the change set against the dev environment

## Capabilities

### New Capabilities

_(none — this change implements the existing `vpc-networking` spec; no new capability is introduced)_

### Modified Capabilities

_(none — the `vpc-networking` spec requirements are unchanged; this is a pure implementation of the already-accepted spec)_

## Non-goals

- Production VPC (`vpc-prod`) — that is a separate change after dev is validated
- VPC peering or Transit Gateway attachments
- IPv6 addressing
- Custom DNS resolvers or Route 53 Resolver rules
- Flow log configuration (deferred to an observability hardening change)

## Impact

- Populates `vpc/` directory (currently empty)
- All downstream stacks (IAM node role, eksctl cluster config) depend on the Outputs of this stack — nothing else in `vpc/` or `clusters/` can be deployed until this stack exists
- IAM permissions required to deploy: `cloudformation:*`, `ec2:*` (VPC, subnet, IGW, NAT GW, route table, security group, VPC endpoint operations) scoped to the dev account

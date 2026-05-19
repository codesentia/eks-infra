# ADR-001: Dedicated VPC per Cluster

**Status:** Accepted  
**Date:** 2026-05-19

## Context

The platform must support two environments (`dev` and `prod`). A decision is needed on whether each EKS cluster lives in its own VPC or whether clusters share a common VPC with subnet-level isolation.

The platform hosts multiple application teams. A misconfigured security group, network ACL, or routing rule could affect any workload reachable within the same VPC. The degree of network isolation between environments is a security and operational requirement.

## Decision

Each EKS cluster gets its own dedicated VPC. The `dev` cluster lives in `10.10.0.0/16`; the `prod` cluster lives in `10.20.0.0/16`. No VPC peering exists between them by default.

## Rationale

- **Blast radius isolation.** A misconfigured security group or overly permissive network ACL in one environment cannot reach workloads in the other. Environment boundaries are enforced at the network layer, not just at the IAM or Kubernetes RBAC layer.
- **Clean credential separation.** IRSA roles, service accounts, and Kubernetes RBAC are scoped per cluster. A VPC boundary reinforces that there is no ambient network path between environments even if an IRSA role were misconfigured.
- **Operational simplicity.** Subnet CIDR planning, route tables, and security groups are independently owned per environment. There is no cross-environment coordination needed when expanding subnets or modifying routing.
- **Future flexibility.** VPC peering or Transit Gateway can be added later if cross-environment communication is genuinely required. It is easier to add connectivity than to remove it.

## Alternatives Considered

### Shared VPC with subnet-per-cluster

A single VPC with dedicated subnet ranges for each cluster environment.

**Rejected because:**
- Blast radius is not eliminated — a misconfigured security group referencing `10.0.0.0/8` would span both clusters.
- Subnet IP range coordination becomes a shared concern — expanding one cluster's node group cannot be done independently.
- A shared VPC is typically governed by a central networking team, introducing a dependency not suited to a platform team owning the full stack.

### Shared VPC with namespace-level isolation only

Rely entirely on Kubernetes NetworkPolicy for inter-environment isolation, no VPC-level separation.

**Rejected because:**
- NetworkPolicy enforces L4 isolation within a cluster; it cannot prevent a pod in one environment from making a TCP connection to a pod in another if they share the same VPC and security groups.
- Defense in depth requires at least two independent isolation layers.

## Consequences

- Two separate VPC CFN stacks must be maintained (`vpc-dev`, `vpc-prod`).
- NAT Gateway costs are incurred independently per environment (not shared).
- If cross-environment communication is ever needed (e.g., dev calling a shared service in prod), explicit VPC peering or Transit Gateway attachment must be designed and approved separately.

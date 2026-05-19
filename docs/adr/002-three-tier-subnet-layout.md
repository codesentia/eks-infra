# ADR-002: Three-Tier Subnet Layout (public / private / intra)

**Status:** Accepted  
**Date:** 2026-05-19

## Context

EKS clusters require subnets for three distinct network actors:
1. **Internet-facing load balancers** (ALBs created by the AWS Load Balancer Controller)
2. **Worker nodes** (EC2 instances running workload pods)
3. **Control plane cross-account ENIs** (the network interfaces EKS injects into the VPC so the managed control plane can communicate with worker nodes)

Each actor has different security and routing requirements. A design decision is needed on how many subnet tiers to create and how to assign actors to tiers.

## Decision

Three subnet tiers are created per Availability Zone:

| Tier | Purpose | Route | CIDR (dev, per AZ) | CIDR (prod, per AZ) |
|------|---------|-------|--------------------|---------------------|
| `public` | ALB nodes, NAT Gateway EIPs | Internet Gateway → internet | `10.10.0.0/20`, `10.10.48.0/20` | `10.20.0.0/20`, `10.20.48.0/20`, `10.20.96.0/20` |
| `private` | EKS worker nodes | NAT Gateway (same AZ) → internet | `10.10.16.0/20`, `10.10.64.0/20` | `10.20.16.0/20`, `10.20.64.0/20`, `10.20.112.0/20` |
| `intra` | EKS control plane ENIs | No internet route | `10.10.32.0/20`, `10.10.80.0/20` | `10.20.32.0/20`, `10.20.80.0/20`, `10.20.128.0/20` |

The range `10.x.144.0/20` and above is reserved in each VPC for future use (peering, additional node groups, or expansion).

### AZ coverage

- **dev:** 2 AZs (cost optimisation; dev does not require the same HA posture as prod)
- **prod:** 3 AZs (full HA; EKS control plane requires ≥ 2 AZs, 3 provides single-AZ failure tolerance)

### Subnet tagging

Subnets are tagged so the AWS Load Balancer Controller and cluster autoscaler can discover them automatically:

| Tag | Value | Applied to |
|-----|-------|------------|
| `kubernetes.io/cluster/<cluster-name>` | `shared` | All subnets |
| `kubernetes.io/role/elb` | `1` | Public subnets |
| `kubernetes.io/role/internal-elb` | `1` | Private subnets |

## Rationale

### Why intra subnets for control plane ENIs?

AWS injects ENIs into the VPC so the EKS control plane can reach worker nodes (for kubelet, kube-proxy, and webhook calls). By routing these ENIs into subnets with no internet route (`intra`), control-plane traffic is isolated from pod-to-internet egress. This follows the AWS EKS best practice for large or security-sensitive clusters:

- A compromised pod cannot reach the control plane ENIs via the internet route.
- Security group rules on the intra subnets can be tightly scoped to only allow EKS control plane communication.

### Why NAT Gateways per AZ?

A single shared NAT Gateway is a single point of failure and introduces cross-AZ data transfer costs. One NAT Gateway per AZ ensures:

- Worker nodes in AZ-a exit via AZ-a's NAT Gateway — no cross-AZ NAT traffic charges.
- An AZ failure does not take down egress for the remaining AZs.

### Why /20 per subnet?

`/20` provides 4,096 IP addresses per subnet tier per AZ. For a shared platform with potentially many pods (EKS assigns one VPC IP per pod with the default VPC CNI), this headroom is necessary. The node instance type determines the ENI/IP limit per node, but `/20` accommodates growth without VPC resizing.

## Alternatives Considered

### Two-tier (public / private only, no intra)

Use private subnets for both worker nodes and control plane ENIs.

**Rejected because:**
- Mixes worker node traffic with control plane ENI traffic in the same subnet, making security group scoping less precise.
- Does not follow AWS recommended EKS subnet architecture for production clusters.

### Single public subnet (simplified networking)

Put everything in public subnets, rely on security groups for isolation.

**Rejected because:**
- Worker nodes would have public IPs, dramatically expanding the attack surface.
- Violates the least-privilege principle at the network layer.

## Consequences

- The VPC CFN template is more complex (3 subnet tiers × N AZs = 6–9 subnets per VPC).
- NAT Gateway costs are proportional to AZ count (2 for dev, 3 for prod).
- The intra subnet tier has no route to the internet, which means any VPC endpoints for AWS services (ECR, Secrets Manager, SSM) must be deployed in the intra subnets or private subnets and accessible from both.

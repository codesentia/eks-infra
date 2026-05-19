## 1. Architecture Decisions

- [x] 1.1 Document ADR-001: Dedicated VPC per cluster — rationale, alternatives considered, trade-offs
- [x] 1.2 Document ADR-002: Three-tier subnet layout (public / private / intra) — CIDR assignments, per-AZ breakdown, reserved ranges
- [x] 1.3 Document ADR-003: System vs application node group split — taint strategy, instance family choices, sizing rationale
- [x] 1.4 Document ADR-004: IRSA for all pod-level AWS access — trust policy pattern, node role minimum permissions, why no instance-profile IAM
- [x] 1.5 Document ADR-005: ArgoCD App of Apps — directory structure, per-layer sync policy (automated vs manual), why ArgoCD over Flux
- [x] 1.6 Document ADR-006: Cloudflare for DNS and certificate issuance — why no Route 53, credential injection pattern, token scope recommendation
- [x] 1.7 Document ADR-007: Dual observability stack (CloudWatch Container Insights + kube-prometheus-stack) — rationale, audience per layer

## 2. Network Topology Diagrams

- [x] 2.1 Draw VPC topology diagram: AZs, subnet tiers, NAT Gateways, VPC endpoints, internet gateway
- [x] 2.2 Draw cluster traffic flow diagram: ingress path (Cloudflare → ALB → pod), intra-cluster path, egress path (pod → NAT GW / VPC endpoint)
- [x] 2.3 Draw multi-team namespace isolation diagram: NetworkPolicy boundaries, allowed vs denied traffic flows between namespaces

## 3. IAM and Security Model Documentation

- [x] 3.1 Document node IAM role: exact permissions, why each one is present, what is explicitly excluded
- [x] 3.2 Document IRSA role template: trust policy structure, naming convention, how OIDCIssuerUrl is threaded through CFN parameters
- [x] 3.3 Document per-component IRSA roles table: component, namespace, service account, permission scope, why that scope
- [x] 3.4 Document Cloudflare API token security model: scope (DNS edit, zone-only), storage location (Secrets Manager), injection path, rotation procedure

## 4. GitOps and Deployment Model Documentation

- [x] 4.1 Document repository structure and ownership boundaries: what CFN owns, what eksctl owns, what ArgoCD owns, what is bootstrapped imperatively
- [x] 4.2 Document ArgoCD App of Apps structure: `apps/` directory layout, root Application, addons Application (manual sync), namespaces Application (automated sync)
- [x] 4.3 Document bootstrap sequence as an ordered runbook outline: VPC → IAM → cluster → IRSA → CF token injection → add-ons → ArgoCD bootstrap → handoff to GitOps
- [x] 4.4 Document change management policy: how add-on upgrades flow (PR → review → manual ArgoCD sync), why addons/ is manual-only

## 5. Team Onboarding Model Documentation

- [x] 5.1 Document namespace isolation model: what every team gets (quota, LimitRange, NetworkPolicy, RBAC), default values, how to request changes
- [x] 5.2 Document RBAC model: admin vs developer role permissions, what each can and cannot do, how groups map to bindings
- [x] 5.3 Document team onboarding steps at a conceptual level: what inputs are required, what resources are created, what the operator does vs what is automated

## 6. Review and Publication

- [x] 6.1 Peer review all ADRs for completeness — each ADR must state the decision, context, alternatives considered, and consequences
- [x] 6.2 Peer review all diagrams for accuracy against the design decisions
- [x] 6.3 Consolidate docs into `docs/` directory structure: `docs/adr/`, `docs/architecture/`, `docs/runbooks/` (outline only, not content)
- [x] 6.4 Confirm design is sufficient for an engineer to begin implementation without ambiguity — identify and resolve any gaps

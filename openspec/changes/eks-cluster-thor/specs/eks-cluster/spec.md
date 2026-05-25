## MODIFIED Requirements

### Requirement: eksctl ClusterConfig per environment
An eksctl `ClusterConfig` template SHALL exist at `clusters/<cluster-name>.yaml.tpl` for each environment. The template SHALL use `${VAR}` placeholders for all VPC-derived and IAM values — no subnet IDs, VPC IDs, or role ARNs SHALL be hardcoded in committed files. A Makefile target SHALL resolve the required CFN exports at runtime and render the template before calling eksctl. The dev cluster template SHALL be `clusters/thor.yaml.tpl`, targeting Kubernetes `1.35` in region `us-east-1`, and SHALL reference exports from the `vpc-dev` and `iam-node-role-dev` CFN stacks.

#### Scenario: Dev cluster config passes dry-run validation
- **WHEN** `make dry-run-cluster-thor` is run with `vpc-dev` and `iam-node-role-dev` stacks deployed
- **THEN** eksctl reports no validation errors using the resolved values

#### Scenario: Resolution fails if vpc-dev is not deployed
- **WHEN** `make dry-run-cluster-thor` or `make create-cluster-thor` is run without `vpc-dev` deployed
- **THEN** the Makefile target fails with a clear error before calling eksctl

#### Scenario: No infrastructure IDs are hardcoded in committed files
- **WHEN** `clusters/thor.yaml.tpl` is inspected in git
- **THEN** all subnet IDs, VPC ID, security group IDs, and role ARNs appear as `${VAR}` placeholders, not literal AWS resource IDs

---

### Requirement: OIDC provider enabled
The cluster SHALL have the IAM OIDC provider enabled so that IRSA trust policies can reference it. OIDC association SHALL be performed as a mandatory post-create step using `make post-create-thor`. The issuer URL SHALL be stored in Parameter Store at `/eks/thor/oidc-issuer-url` as the handoff point for all future IRSA role stacks.

#### Scenario: OIDC issuer is available after post-create step
- **WHEN** `make post-create-thor` is run after cluster creation
- **THEN** the OIDC provider ARN is present in IAM and the issuer URL is stored at `/eks/thor/oidc-issuer-url` in Parameter Store

---

### Requirement: Two managed node groups
The cluster SHALL define two managed node groups: `system` (tainted `CriticalAddonsOnly=true:NoSchedule`, instance type `m6i.large`, min 1 / desired 1 / max 3) and `application` (untainted, instance type `m6i.xlarge`, min 1 / desired 1 / max 3). Both node groups SHALL use the private subnets from `vpc-dev`. Control-plane ENIs SHALL use the intra subnets from `vpc-dev`.

#### Scenario: System node group taint prevents tenant scheduling
- **WHEN** a tenant pod without the matching toleration is scheduled
- **THEN** the pod is not placed on `system` nodes

#### Scenario: Application node group is the default target
- **WHEN** a pod without node selector or toleration is scheduled
- **THEN** it lands on an `application` node

#### Scenario: Node groups use private subnets; control plane uses intra subnets
- **WHEN** the rendered ClusterConfig is inspected
- **THEN** node groups reference `vpc-dev` private subnet IDs and control-plane ENIs reference `vpc-dev` intra subnet IDs

---

### Requirement: Kubernetes API endpoint is private-only for prod
The prod cluster API endpoint SHALL be set to private-only. The dev cluster (`thor`) SHALL expose both public and private endpoints for operator convenience, with no CIDR restriction on the public endpoint.

#### Scenario: Dev API endpoint is accessible from operator network
- **WHEN** `kubectl get nodes` is run from the operator's network
- **THEN** the command succeeds without VPN

---

### Requirement: EKS control-plane logging enabled
CloudWatch logging SHALL be enabled for `api`, `audit`, `authenticator`, `controllerManager`, and `scheduler` log types on the `thor` cluster.

#### Scenario: Control plane logs present in CloudWatch
- **WHEN** the cluster is running and API calls are made
- **THEN** log events appear in the `/aws/eks/thor/cluster` CloudWatch log group

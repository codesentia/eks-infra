## ADDED Requirements

### Requirement: eksctl ClusterConfig per environment
An eksctl `ClusterConfig` YAML SHALL exist at `clusters/<env>.yaml` for each environment. The config SHALL reference the VPC and subnets exported by the corresponding VPC CFN stack.

#### Scenario: Dev cluster config is valid
- **WHEN** `eksctl create cluster --dry-run -f clusters/dev.yaml` is run
- **THEN** eksctl reports no validation errors

#### Scenario: Prod cluster config is valid
- **WHEN** `eksctl create cluster --dry-run -f clusters/prod.yaml` is run
- **THEN** eksctl reports no validation errors

---

### Requirement: OIDC provider enabled
The cluster SHALL have the IAM OIDC provider enabled so that IRSA trust policies can reference it.

#### Scenario: OIDC issuer is available after cluster creation
- **WHEN** `eksctl utils associate-iam-oidc-provider` is run post-create
- **THEN** the OIDC provider ARN is present in IAM and the issuer URL is stored in Parameter Store at `/eks/<env>/oidc-issuer-url`

---

### Requirement: Two managed node groups
The cluster SHALL define two managed node groups: `system` (tainted for add-on pods) and `application` (untainted, for tenant workloads).

#### Scenario: System node group taint prevents tenant scheduling
- **WHEN** a tenant pod without the matching toleration is scheduled
- **THEN** the pod is not placed on `system` nodes

#### Scenario: Application node group is the default target
- **WHEN** a pod without node selector or toleration is scheduled
- **THEN** it lands on an `application` node

#### Scenario: Node groups span all AZs
- **WHEN** node group subnets are inspected
- **THEN** each node group references private subnets in all environment AZs

---

### Requirement: Kubernetes API endpoint is private-only for prod
The prod cluster API endpoint SHALL be set to private-only. The dev cluster MAY expose the public endpoint for operator convenience.

#### Scenario: Prod API endpoint is not publicly reachable
- **WHEN** the prod cluster endpoint is queried from outside the VPC
- **THEN** the connection is refused or times out

#### Scenario: Dev API endpoint is accessible from operator CIDR
- **WHEN** `kubectl get nodes` is run from the operator's network
- **THEN** the command succeeds without VPN

---

### Requirement: EKS control-plane logging enabled
CloudWatch logging SHALL be enabled for `api`, `audit`, `authenticator`, `controllerManager`, and `scheduler` log types.

#### Scenario: Control plane logs present in CloudWatch
- **WHEN** the cluster is running and API calls are made
- **THEN** log events appear in the `/aws/eks/<cluster-name>/cluster` CloudWatch log group

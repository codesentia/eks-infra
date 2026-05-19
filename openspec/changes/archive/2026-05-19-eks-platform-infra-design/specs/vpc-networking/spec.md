## ADDED Requirements

### Requirement: VPC per environment
A dedicated VPC SHALL be created for each environment (`dev`, `prod`) via a CFN stack named `vpc-<env>`.

#### Scenario: VPC deployed for dev
- **WHEN** the `vpc-dev` CFN change set is executed
- **THEN** a VPC exists with a `/16` CIDR, DNS hostnames enabled, and DNS resolution enabled

#### Scenario: VPC deployed for prod
- **WHEN** the `vpc-prod` CFN change set is executed
- **THEN** a VPC exists with a separate `/16` CIDR, no CIDR overlap with dev

---

### Requirement: Three subnet tiers per AZ
The VPC SHALL contain three subnet tiers in each AZ: `public`, `private`, and `intra`. Dev SHALL span 2 AZs; prod SHALL span 3 AZs.

#### Scenario: Subnet tiers present per AZ
- **WHEN** the VPC CFN stack is deployed
- **THEN** each AZ contains exactly one public subnet (`/20`), one private subnet (`/20`), and one intra subnet (`/20`)

#### Scenario: Subnets tagged for EKS
- **WHEN** subnets are inspected after stack deployment
- **THEN** private subnets carry `kubernetes.io/role/internal-elb=1` and public subnets carry `kubernetes.io/role/elb=1`

---

### Requirement: NAT Gateway per AZ
One NAT Gateway SHALL be deployed in each public subnet (one per AZ) to avoid cross-AZ egress.

#### Scenario: NAT Gateway present for each AZ
- **WHEN** the VPC stack is deployed
- **THEN** each public subnet has one associated NAT Gateway with an EIP

#### Scenario: Private subnet routes via local NAT Gateway
- **WHEN** a private subnet route table is inspected
- **THEN** the default route (`0.0.0.0/0`) targets the NAT Gateway in the same AZ

---

### Requirement: VPC endpoints for AWS services
The VPC SHALL include Interface and Gateway VPC endpoints for S3, ECR (API + DKR), Secrets Manager, and Parameter Store to reduce NAT traffic.

#### Scenario: S3 gateway endpoint present
- **WHEN** the VPC stack is deployed
- **THEN** a Gateway endpoint for `com.amazonaws.<region>.s3` is associated with all private and intra route tables

#### Scenario: Interface endpoints present for ECR, Secrets Manager, SSM
- **WHEN** the VPC stack is deployed
- **THEN** interface endpoints exist for `ecr.api`, `ecr.dkr`, `secretsmanager`, `ssm`, and `ssmmessages`, all in the intra subnets

---

### Requirement: Security groups for cluster communication
CFN SHALL create a node security group and a control-plane additional security group that allow kubelet, kube-proxy, and webhook traffic.

#### Scenario: Node security group allows control plane to kubelet
- **WHEN** the node security group is inspected
- **THEN** inbound port `10250` is allowed from the EKS cluster security group

#### Scenario: Outbound internet egress is unrestricted for nodes
- **WHEN** the node security group is inspected
- **THEN** outbound `0.0.0.0/0` is permitted (nodes pull images via NAT / ECR endpoint)

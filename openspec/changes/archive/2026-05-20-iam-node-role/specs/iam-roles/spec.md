## MODIFIED Requirements

### Requirement: Node IAM role with least-privilege policy
A CFN stack `iam-node-role-dev` SHALL create a node IAM role named `eks-thor-node-role` with only the AWS managed policies required for EKS managed nodes. The stack SHALL export the role ARN as `iam-node-role-dev-NodeRoleArn` for consumption by the eksctl ClusterConfig. The role trust policy SHALL be scoped to `ec2.amazonaws.com` only.

Attached AWS managed policies:
- `AmazonEKSWorkerNodePolicy`
- `AmazonEC2ContainerRegistryReadOnly`
- `AmazonEKS_CNI_Policy`
- `AmazonSSMManagedInstanceCore`

The role SHALL NOT have `AmazonEBSCSIDriverPolicy` — EBS CSI access is granted via a dedicated IRSA role in a future change.

#### Scenario: Node role allows ECR pull
- **WHEN** the node role's policies are inspected
- **THEN** `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:GetDownloadUrlForLayer`, and `ecr:BatchGetImage` are present via `AmazonEC2ContainerRegistryReadOnly`

#### Scenario: Node role does not allow S3 GetObject on arbitrary buckets
- **WHEN** an IAM policy simulation is run against the node role
- **THEN** `s3:GetObject` on `arn:aws:s3:::*` is denied

#### Scenario: Node role trust policy is scoped to EC2 only
- **WHEN** the role trust policy is retrieved
- **THEN** the only principal is `ec2.amazonaws.com` — no other service can assume this role

#### Scenario: Node role ARN is exported for downstream consumption
- **WHEN** the `iam-node-role-dev` stack is deployed
- **THEN** the CloudFormation export `iam-node-role-dev-NodeRoleArn` is available for the eksctl ClusterConfig

#### Scenario: Node role is deployed via change set
- **WHEN** `iam/node-role.yaml` is deployed
- **THEN** it is created via a CloudFormation change set, consistent with platform convention

#### Scenario: Node role stack is linted by CI
- **WHEN** a PR modifies any file under `iam/`
- **THEN** `make lint-all` includes `iam/node-role.yaml` in the cfn-lint run automatically

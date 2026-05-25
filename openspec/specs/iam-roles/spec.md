## ADDED Requirements

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

---

### Requirement: IRSA CFN template parameterised by component
A reusable CFN template (`iam/irsa-role.yaml`) SHALL accept parameters `ClusterName`, `OIDCIssuerUrl`, `Namespace`, `ServiceAccountName`, and `PolicyDocument` and produce an IRSA role following the naming convention `eks-<cluster>-<component>-role`.

#### Scenario: IRSA role trust policy is correctly scoped
- **WHEN** the role trust policy is retrieved
- **THEN** the `StringEquals` condition binds to the specific namespace and service account passed as parameters

#### Scenario: Two IRSA roles with the same component name cannot coexist
- **WHEN** a CFN stack with a duplicate role name is submitted
- **THEN** the stack fails with a naming collision error before any IAM resource is created

---

### Requirement: ALB controller IRSA role
A CFN stack SHALL deploy an IRSA role for the AWS Load Balancer Controller with the AWS-managed `AWSLoadBalancerControllerIAMPolicy` or equivalent inline policy, bound to `kube-system/aws-load-balancer-controller`.

#### Scenario: ALB controller can create load balancers
- **WHEN** an Ingress resource is applied with the ALB ingress class
- **THEN** the ALB controller creates an Application Load Balancer without permission errors in its logs

---

### Requirement: Cluster-autoscaler IRSA role
A CFN stack SHALL deploy an IRSA role for the cluster autoscaler bound to `kube-system/cluster-autoscaler`, with permissions limited to describing and modifying the specific node group Auto Scaling Groups.

#### Scenario: Cluster autoscaler cannot modify ASGs in other clusters
- **WHEN** an IAM policy simulation is run targeting an ASG not tagged with this cluster's name
- **THEN** `autoscaling:SetDesiredCapacity` is denied

---

### Requirement: EBS CSI driver IRSA role
A CFN stack SHALL deploy an IRSA role for the EBS CSI driver bound to `kube-system/ebs-csi-controller-sa`, with the AWS-managed `AmazonEBSCSIDriverPolicy`.

#### Scenario: EBS CSI driver can provision volumes
- **WHEN** a PersistentVolumeClaim with `storageClassName: ebs-gp3` is created
- **THEN** the volume is provisioned without permission errors in the CSI driver logs

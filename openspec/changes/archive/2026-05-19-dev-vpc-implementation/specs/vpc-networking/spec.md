## ADDED Requirements

### Requirement: Single parameterised CFN template for all environments
A single CFN template `vpc/vpc.yaml` SHALL be the authoritative source for VPC infrastructure across all environments. It SHALL accept parameters `Environment` (e.g., `dev`), `VpcCidr`, and `AZCount` (2 or 3). Environment-specific parameter values SHALL be stored in `vpc/parameters/<env>.json`.

#### Scenario: Template deploys a 2-AZ VPC for dev
- **WHEN** the template is deployed with `AZCount=2` and `VpcCidr=10.10.0.0/16`
- **THEN** exactly 6 subnets are created (2 public, 2 private, 2 intra) and no third-AZ resources exist

#### Scenario: Template deploys a 3-AZ VPC for prod
- **WHEN** the same template is deployed with `AZCount=3` and `VpcCidr=10.20.0.0/16`
- **THEN** exactly 9 subnets are created (3 public, 3 private, 3 intra)

---

### Requirement: Template passes cfn-lint with no errors or warnings
The `vpc/vpc.yaml` template SHALL produce zero errors and zero warnings when validated with `cfn-lint` before any deployment.

#### Scenario: cfn-lint gate passes
- **WHEN** `cfn-lint vpc/vpc.yaml` is run
- **THEN** the command exits with code 0 and no diagnostic output

---

### Requirement: CFN stack named `vpc-<env>`
The CloudFormation stack SHALL be named `vpc-<env>` (e.g., `vpc-dev`, `vpc-prod`). This name is the namespace for all cross-stack export references.

#### Scenario: Stack name follows convention
- **WHEN** the stack is created
- **THEN** `aws cloudformation describe-stacks --stack-name vpc-dev` returns the stack without error

---

### Requirement: All outputs exported with predictable names
The template SHALL export the following outputs using the pattern `!Sub "${AWS::StackName}-<ResourceType>-<Qualifier>"`:

| Export name | Value |
|-------------|-------|
| `vpc-dev-VpcId` | VPC resource ID |
| `vpc-dev-PublicSubnetA` | Public subnet ID, AZ-a |
| `vpc-dev-PublicSubnetB` | Public subnet ID, AZ-b |
| `vpc-dev-PrivateSubnetA` | Private subnet ID, AZ-a |
| `vpc-dev-PrivateSubnetB` | Private subnet ID, AZ-b |
| `vpc-dev-IntraSubnetA` | Intra subnet ID, AZ-a |
| `vpc-dev-IntraSubnetB` | Intra subnet ID, AZ-b |
| `vpc-dev-NodeSecurityGroupId` | Node security group ID |
| `vpc-dev-ControlPlaneSecurityGroupId` | Control plane additional SG ID |

#### Scenario: All required outputs are present after deployment
- **WHEN** `aws cloudformation describe-stacks --stack-name vpc-dev --query 'Stacks[0].Outputs'` is run
- **THEN** all 9 exports listed above are present with non-empty values

#### Scenario: Downstream stack can import VPC ID without manual lookup
- **WHEN** a downstream CFN template uses `Fn::ImportValue: vpc-dev-VpcId`
- **THEN** the value resolves to the correct VPC ID without any operator intervention

---

### Requirement: Deployment executed via change set (never direct deploy)
The `vpc-<env>` stack SHALL always be created or updated via a CFN change set. The change set SHALL be reviewed before execution. Direct stack creation with `--no-execute-changeset` SHALL NOT be used.

#### Scenario: Change set is created and reviewed before apply
- **WHEN** deploying or updating the vpc stack
- **THEN** `aws cloudformation deploy --no-execute-changeset` creates the change set and the operator reviews it before running `aws cloudformation execute-change-set`

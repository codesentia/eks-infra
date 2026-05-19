## 1. Tooling Setup

- [x] 1.1 Add `.venv/` and `__pycache__/` to `.gitignore` at repo root
- [x] 1.2 Author `requirements.in` at repo root with top-level unpinned deps: `cfn-lint`, `boto3`, `pyyaml`
- [x] 1.3 Run `pip install pip-tools` in a bootstrap venv, then `pip-compile requirements.in` to generate pinned `requirements.txt`
- [x] 1.4 Author `Makefile` at repo root with targets: `bootstrap` (create `.venv` and `pip install -r requirements.txt`), `lint-vpc` (`.venv/bin/cfn-lint vpc/vpc.yaml`), `help` (list targets)
- [x] 1.5 Verify `make bootstrap && make lint-vpc` runs clean from a fresh clone (no pre-existing venv)

## 2. Template Scaffold

- [x] 2.1 Create `vpc/` directory and `vpc/parameters/` subdirectory
- [x] 2.2 Author `vpc/parameters/dev.json` with `Environment=dev`, `VpcCidr=10.10.0.0/16`, `AZCount=2`
- [x] 2.3 Author the CFN template skeleton in `vpc/vpc.yaml`: `AWSTemplateFormatVersion`, `Description`, `Parameters` block (`Environment`, `VpcCidr`, `AZCount`), `Conditions` block (`IsThreeAZ`), `Mappings` block with per-environment CIDR layout

## 3. Core VPC Resources

- [x] 3.1 Add `AWS::EC2::VPC` resource: CIDR from `!Ref VpcCidr`, `EnableDnsHostnames: true`, `EnableDnsSupport: true`, Name tag `eks-${Environment}`
- [x] 3.2 Add `AWS::EC2::InternetGateway` and `AWS::EC2::VPCGatewayAttachment`
- [x] 3.3 Add 6 `AWS::EC2::Subnet` resources for 2-AZ layout (public-a, public-b, private-a, private-b, intra-a, intra-b) with correct CIDRs per ADR-002 and EKS discovery tags
- [x] 3.4 Add conditional 3rd-AZ subnet resources (public-c, private-c, intra-c) gated on `IsThreeAZ` condition

## 4. Routing

- [x] 4.1 Add public route table with `0.0.0.0/0 → IGW` route; associate with all public subnets
- [x] 4.2 Add 2 `AWS::EC2::EIP` and 2 `AWS::EC2::NatGateway` resources (one per AZ, in public subnets)
- [x] 4.3 Add conditional 3rd EIP and NAT Gateway gated on `IsThreeAZ`
- [x] 4.4 Add 2 private route tables (one per AZ) each with `0.0.0.0/0 → local NAT GW`; associate with private subnets
- [x] 4.5 Add conditional 3rd private route table for AZ-c gated on `IsThreeAZ`
- [x] 4.6 Add 2 intra route tables (local only, no default route); associate with intra subnets
- [x] 4.7 Add conditional 3rd intra route table for AZ-c gated on `IsThreeAZ`

## 5. VPC Endpoints

- [x] 5.1 Add `AWS::EC2::VPCEndpoint` (Gateway type) for S3; associate with all private and intra route tables
- [x] 5.2 Add `AWS::EC2::SecurityGroup` for VPC interface endpoints: inbound HTTPS (443) from node SG only
- [x] 5.3 Add `AWS::EC2::VPCEndpoint` (Interface type) for `ecr.api` in intra subnets
- [x] 5.4 Add `AWS::EC2::VPCEndpoint` (Interface type) for `ecr.dkr` in intra subnets
- [x] 5.5 Add `AWS::EC2::VPCEndpoint` (Interface type) for `secretsmanager` in intra subnets
- [x] 5.6 Add `AWS::EC2::VPCEndpoint` (Interface type) for `ssm` in intra subnets
- [x] 5.7 Add `AWS::EC2::VPCEndpoint` (Interface type) for `ssmmessages` in intra subnets

## 6. Security Groups

- [x] 6.1 Add `NodeSecurityGroup`: self-referencing intra-SG rule, inbound port 10250 from control plane SG, unrestricted outbound
- [x] 6.2 Add `ControlPlaneAdditionalSecurityGroup`: allow inbound 443 and 10250 from `NodeSecurityGroup`

## 7. Outputs

- [x] 7.1 Add `Outputs` block exporting `VpcId`, `PublicSubnetA/B`, `PrivateSubnetA/B`, `IntraSubnetA/B` with `!Sub "${AWS::StackName}-<name>"` export names
- [x] 7.2 Add conditional outputs `PublicSubnetC`, `PrivateSubnetC`, `IntraSubnetC` gated on `IsThreeAZ`
- [x] 7.3 Add outputs `NodeSecurityGroupId` and `ControlPlaneSecurityGroupId`

## 8. Validation and Deployment

- [x] 8.1 Run `make lint-vpc` and resolve all cfn-lint errors and warnings
- [x] 8.2 [change-set required] Run `make deploy-vpc-dev` (or equivalent) to create the change set: `aws cloudformation deploy --no-execute-changeset --stack-name vpc-dev --template-file vpc/vpc.yaml --parameter-overrides file://vpc/parameters/dev.json`
- [x] 8.3 Review change set in AWS console or CLI; verify resource count matches expected (VPC, 6 subnets, IGW, 2 NAT GWs, route tables, endpoints, SGs)
- [x] 8.4 Execute change set: `aws cloudformation execute-change-set --change-set-name <name> --stack-name vpc-dev`
- [x] 8.5 Verify all required outputs are present: `aws cloudformation describe-stacks --stack-name vpc-dev --query 'Stacks[0].Outputs'`
- [x] 8.6 Verify subnet tagging: confirm `kubernetes.io/role/elb=1` on public subnets and `kubernetes.io/role/internal-elb=1` on private subnets

## Why

The dev VPC stack is deployed and the CI/CD pipeline is wired. The next prerequisite for standing up an EKS cluster is the EC2 node IAM role — without it, eksctl cannot create the cluster. This change delivers the node role CFN stack in `iam/`, wires it into the Makefile and CI, and updates documentation to reflect the new stack.

## What Changes

- New `iam/node-role.yaml` — CFN template provisioning `eks-<cluster>-node-role` with least-privilege managed policies for EKS managed nodes (ECR pull, CloudWatch agent, EBS CSI bootstrap, SSM agent for node access)
- New `iam/parameters/node-role-dev.json` — parameter values for the dev cluster node role
- `Makefile` — add `lint-all` already covers `iam/` automatically; add `deploy-node-role-dev` deploy target
- `.github/workflows/deploy-node-role-dev.yaml` — deploy workflow triggered on `iam/**` changes or `workflow_dispatch`; creates change set only, never executes
- `docs/architecture/iam-security-model.md` — update node role section with actual stack name, attached policies, and ARN export pattern
- `docs/README.md` — add `runbooks/github-actions-add-stack.md` entry (already exists, just missing from index)
- `bootstrap/README.md` — add note on `iam:PassRole` for CFN execution role (node role stack requires it)

## Capabilities

### New Capabilities

_(none — node role is an implementation of an existing spec requirement)_

### Modified Capabilities

- `iam-roles`: the node role requirement moves from specified to implemented; update the spec to reflect the concrete stack name (`iam-node-role-dev`), attached AWS managed policies, and Makefile/CI integration

## Impact

- New `iam/` directory created
- `github-actions-dev` IAM role in bootstrap needs `iam:PassRole` added for the CFN execution role that will create the node role — one-time bootstrap stack update required
- No changes to running infrastructure (VPC stack untouched)
- Node role ARN exported as `iam-node-role-dev-NodeRoleArn` for consumption by the eksctl ClusterConfig in a future change

## Non-goals

- IRSA roles (cluster-autoscaler, ALB controller, EBS CSI) — separate change after cluster creation
- `prod` environment node role — follows the same pattern, deferred until dev cluster is validated
- Node role permission boundary — not required at this stage; least-privilege managed policies are sufficient

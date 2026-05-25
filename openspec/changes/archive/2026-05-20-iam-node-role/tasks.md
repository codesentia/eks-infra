## 1. Bootstrap Update — Add iam:PassRole

> One-time operator step: update the `github-actions-dev` IAM role to allow CFN to pass the node role to EC2. Required before the deploy workflow can create the node role change set.

- [x] 1.1 Add `iam:PassRole` statement to `bootstrap/github-actions-role.yaml` inline policy, scoped to `arn:aws:iam::*:role/eks-*-node-role`
- [x] 1.2 [change-set required] Deploy updated `github-actions-dev` bootstrap stack via change set; verify new policy statement is present — manual operator step

## 2. Node Role CFN Template

- [x] 2.1 Create `iam/` directory
- [x] 2.2 Author `iam/node-role.yaml` CFN template: parameters `ClusterName` and `Environment`; role named `eks-${ClusterName}-node-role`; trust policy for `ec2.amazonaws.com`; attach four AWS managed policies; export `${AWS::StackName}-NodeRoleArn`
- [x] 2.3 Create `iam/parameters/` directory and author `iam/parameters/node-role-dev.json` with `ClusterName=dev`, `Environment=dev`
- [x] 2.4 Run `make lint-all` to confirm `iam/node-role.yaml` passes cfn-lint with zero errors

## 3. Makefile and CI Wiring

- [x] 3.1 Add `deploy-node-role-dev` target to Makefile: `--no-execute-changeset`, `--stack-name iam-node-role-dev`, `--template-file iam/node-role.yaml`, `--parameter-overrides file://iam/parameters/node-role-dev.json`, `--capabilities CAPABILITY_NAMED_IAM`
- [x] 3.2 Author `.github/workflows/deploy-node-role-dev.yaml`: triggers on `workflow_dispatch` and push to `main` with `paths: iam/**`; OIDC credentials; `make deploy-node-role-dev`

## 4. Stack Deployment

- [x] 4.1 [change-set required] Run `make deploy-node-role-dev` to create the `iam-node-role-dev` change set; review in AWS Console and execute; verify `iam-node-role-dev-NodeRoleArn` export is present — manual operator step

## 5. Documentation Updates

- [x] 5.1 Update `docs/architecture/iam-security-model.md`: replace the placeholder node role section with the concrete stack name (`iam-node-role-dev`), attached policies, ARN export name, and CFN stack reference
- [x] 5.2 Update `docs/README.md`: add `runbooks/github-actions-add-stack.md` to the Runbooks table

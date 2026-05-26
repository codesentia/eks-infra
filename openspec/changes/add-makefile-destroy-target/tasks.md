## 1. Add Destroy Targets to Makefile

- [x] 1.1 Add `destroy-cluster-thor` target: confirmation prompt (interactive or `CONFIRM=yes`), run `eksctl delete cluster --name thor --region us-east-1 --wait`, exit with error if not confirmed
- [x] 1.2 Add `destroy-node-role-dev` target: confirmation prompt, run `aws cloudformation delete-stack --stack-name iam-node-role-dev`, wait for `stack-delete-complete`, exit with error if not confirmed
- [x] 1.3 Add `destroy-vpc-dev` target: confirmation prompt, run `aws cloudformation delete-stack --stack-name vpc-dev`, wait for `stack-delete-complete`, exit with error if not confirmed
- [x] 1.4 Add `destroy-all-dev` target: call `destroy-cluster-thor`, then `destroy-node-role-dev`, then `destroy-vpc-dev` in sequence with echo messages between stages; each component target handles its own confirmation

## 2. Documentation

- [x] 2.1 Update `docs/runbooks/cluster-bootstrap.md`: add "Teardown" section at the end with the three-stage destroy sequence, safety notes (confirmation required, dependency order), note that `/eks/thor/oidc-issuer-url` Parameter Store entry is not auto-deleted, and troubleshooting guidance for VPC delete failures (check for ENIs, load balancers)
- [x] 2.2 Update Makefile help text: ensure all four destroy targets have `## [DESTRUCTIVE]` prefix in their help comment so `make help` output flags them clearly

## 3. Validation

> Prerequisites: `vpc-dev`, `iam-node-role-dev`, and `thor` cluster deployed in a test AWS account

- [ ] 3.1 Test `make destroy-cluster-thor` interactively: type `no` at prompt — confirm target exits with error; run again, type `yes` — confirm cluster deletes successfully (~10 min), eksctl-managed stacks removed
- [ ] 3.2 Redeploy cluster; test `CONFIRM=yes make destroy-cluster-thor` non-interactively — confirm cluster deletes without prompt
- [ ] 3.3 Redeploy cluster; test `make destroy-all-dev` — confirm three separate prompts appear (cluster, node role, VPC), type `yes` for cluster and node role, type `no` for VPC — confirm VPC is not deleted; verify node role is deleted but VPC remains
- [ ] 3.4 Redeploy node role and re-run `make destroy-all-dev` with `yes` to all prompts — confirm full teardown completes successfully in order, all CloudFormation stacks removed
- [ ] 3.5 Verify `/eks/thor/oidc-issuer-url` Parameter Store entry still exists after cluster deletion (not auto-deleted)

## 4. Final Review

- [x] 4.1 Run `make help` — confirm all four destroy targets appear with `[DESTRUCTIVE]` tag and clear descriptions
- [x] 4.2 Review Makefile indentation and variable consistency (use tabs, match existing `EKSCTL` and `AWS` variable style)

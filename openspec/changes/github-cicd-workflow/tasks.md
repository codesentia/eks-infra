## 1. Makefile Extensions

- [x] 1.1 Add `lint-all` target: runs cfn-lint on all `*.yaml` files found via `find vpc/ iam/ -name "*.yaml"` using `.venv/bin/cfn-lint` — `bootstrap/` is intentionally excluded
- [x] 1.2 Add `ci` target: depends on `bootstrap` and `lint-all`; the exact sequence GitHub Actions will run
- [x] 1.3 Verify `make ci` runs end-to-end cleanly from a fresh `.venv`

## 2. Bootstrap — GitHub Actions IAM Role (manual, one-time operator step)

> These resources are prerequisites for CI/CD. They live in `bootstrap/`, isolated from the Makefile and CI workflows. A human operator deploys them once before the first CI run.

- [x] 2.1 Author `bootstrap/github-actions-role.yaml` CFN template: OIDC trust policy parameterised by `GitHubOrg`, `GitHubRepo`, `Environment`; trust condition scoped to `main` branch; inline policy with `cloudformation:CreateChangeSet`, `DescribeChangeSet`, `DescribeStacks`, `ListChangeSets`, `ec2:Describe*` — explicitly no `ExecuteChangeSet`
- [x] 2.2 Add `bootstrap/parameters/github-actions-role-dev.json` with `GitHubOrg`, `GitHubRepo`, `Environment=dev` parameter values
- [x] 2.3 Author `bootstrap/README.md`: one-time setup procedure — register OIDC provider, deploy IAM role stack via change set, add GitHub Actions variables
- [x] 2.4 Verify `bootstrap/github-actions-role.yaml` passes cfn-lint manually: `.venv/bin/cfn-lint bootstrap/github-actions-role.yaml`

## 3. CI Workflow

- [x] 3.1 Create `.github/workflows/` directory
- [x] 3.2 Author `.github/workflows/ci.yaml`: triggers on `pull_request` and `push` to `main`; steps: checkout, setup-python, restore venv cache (key: `venv-${{ runner.os }}-${{ hashFiles('requirements.txt') }}`), `make ci`, save cache
- [ ] 3.3 Push to a feature branch and verify the CI workflow runs and passes in GitHub Actions — manual verification after push

## 4. Deploy Workflow

- [x] 4.1 Author `.github/workflows/deploy-vpc-dev.yaml`: triggers on `workflow_dispatch` and `push` to `main` with `paths: ['vpc/**']`; steps: checkout, configure-aws-credentials (OIDC, role ARN from output), `make deploy-vpc-dev`
- [ ] 4.2 Add `AWS_REGION` and `ROLE_ARN` as GitHub Actions variables (not secrets — they are not sensitive) — manual operator step in GitHub Settings
- [ ] 4.3 Push a trivial change to `vpc/` on a branch, merge to `main`, verify deploy workflow triggers and creates the change set in AWS — manual verification after push

## 5. Documentation

- [x] 5.1 _(covered by task 2.3 — `bootstrap/README.md` is the authoritative one-time setup guide)_
- [x] 5.2 Author `docs/runbooks/github-actions-add-stack.md`: how to add a new deploy workflow for a future CFN stack (the repeatable part, once bootstrap is done)

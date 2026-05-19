## Why

The infrastructure repository has no automated checks — linting, validation, and deployment steps are run manually, which means errors can reach the main branch and there is no consistent gate before a CloudFormation change set is created. Adding GitHub Actions workflows now establishes the CI/CD foundation that every subsequent infrastructure change (IAM, cluster, add-ons) will benefit from.

## What Changes

- New `.github/workflows/ci.yaml` — runs on every PR and push to `main`; executes `make bootstrap` and `make lint` to validate all CloudFormation templates with cfn-lint
- New `.github/workflows/deploy-vpc-dev.yaml` — triggered manually (workflow_dispatch) or on merge to `main` when `vpc/` files change; creates the CFN change set via `make deploy-vpc-dev` and posts the change set diff as a PR comment for review before execution
- New Makefile targets to support CI: `lint-all` (runs cfn-lint on all templates in `vpc/`, `iam/`), `ci` (bootstrap + lint-all in sequence)
- AWS credentials in GitHub Actions injected via OIDC (no long-lived access keys stored as secrets) — requires a one-time IAM OIDC provider and GitHub Actions IAM role setup

## Capabilities

### New Capabilities

- `github-actions-ci`: PR/push lint gate — runs cfn-lint on all templates via Makefile, fails the check if any errors or warnings are present
- `github-actions-deploy`: Manual + auto-triggered deploy workflow for CFN stacks — creates change sets only, never executes them automatically; posts diff for human review

### Modified Capabilities

_(none — Makefile targets are being extended, not changing existing behaviour)_

## Non-goals

- Automatic change set execution (a human always clicks "execute" — this is intentional per ADR)
- Deployment of EKS cluster or add-ons via CI (those require operational judgment)
- Slack / PagerDuty notifications (out of scope for initial CI setup)
- Multi-environment promotion pipelines (dev → prod gating)

## Impact

- New `.github/` directory added to the repository
- Makefile extended with `lint-all` and `ci` targets
- One-time AWS setup required: GitHub OIDC provider in IAM and a `github-actions-role` CFN stack (`iam/github-actions-role.yaml`) with least-privilege permissions scoped to CFN change set creation
- No existing files modified; no blast radius on running infrastructure

# Adding a Deploy Workflow for a New CloudFormation Stack

This runbook covers the repeatable steps to wire a new CFN stack into the GitHub Actions deploy pipeline. It assumes the one-time bootstrap (OIDC provider + `github-actions-dev` IAM role) is already done — see `bootstrap/README.md` if not.

---

## What You Need

- A CFN template under `vpc/`, `iam/`, or a new top-level directory
- A `make deploy-<stack>-<env>` target in the Makefile
- A parameter file at `<dir>/parameters/<env>.json`

---

## Step 1 — Add a Makefile Deploy Target

In `Makefile`, add a target following the existing pattern:

```makefile
.PHONY: deploy-<stack>-dev
deploy-<stack>-dev:  ## [change-set required] Create <stack>-dev change set
	$(AWS) cloudformation deploy \
		--no-execute-changeset \
		--stack-name <stack>-dev \
		--template-file <dir>/<template>.yaml \
		--parameter-overrides file://<dir>/parameters/dev.json \
		--capabilities CAPABILITY_NAMED_IAM
```

Verify it runs locally:

```bash
make deploy-<stack>-dev
```

---

## Step 2 — Check IAM Role Permissions

The `github-actions-dev` role (`bootstrap/github-actions-role.yaml`) grants `cloudformation:CreateChangeSet` on `"*"` — sufficient for any new stack in the same account.

If the new stack creates resources that CFN needs `iam:PassRole` for (e.g. a new execution role), add the permission to the bootstrap template's inline policy and redeploy the bootstrap stack via change set.

---

## Step 3 — Author the Deploy Workflow

Create `.github/workflows/deploy-<stack>-dev.yaml`:

```yaml
name: Deploy <stack>-dev (change set)

on:
  workflow_dispatch:
  push:
    branches: [main]
    paths:
      - <dir>/**

permissions:
  id-token: write
  contents: read

jobs:
  changeset:
    name: Create <stack>-dev change set
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}

      - run: make deploy-<stack>-dev
```

Key points:
- `paths` should match the directory where the template lives so the workflow only triggers on relevant changes
- `ROLE_ARN` and `AWS_REGION` are shared GitHub Actions variables set once during bootstrap — no per-workflow secret needed
- The workflow creates a change set only; a human executes it in the AWS Console

---

## Step 4 — Verify

1. Push the new workflow file and Makefile change on a branch
2. Open a PR — the `ci` workflow lints all templates automatically (including the new one if it's under `vpc/` or `iam/`)
3. Merge to `main` — the new deploy workflow triggers and creates the change set
4. In AWS Console: CloudFormation → Stacks → `<stack>-dev` → Change sets → review and execute

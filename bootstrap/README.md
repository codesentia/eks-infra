# Bootstrap — One-Time Setup

This directory contains resources that must exist **before** GitHub Actions CI/CD workflows can authenticate to AWS. These are prerequisites for the pipeline, not managed by the pipeline itself.

**Contents:**
- `github-actions-role.yaml` — CloudFormation template: GitHub OIDC trust policy + least-privilege inline policy
- `parameters/github-actions-role-dev.json` — Parameter values for the dev environment

> Run these steps once per AWS account/environment. After this is done, the CI/CD pipeline is self-sustaining.

---

## Prerequisites

- AWS CLI configured with credentials that can create IAM roles and OIDC providers
- `.venv` set up: `make bootstrap` from the repo root

---

## Step 1 — Register the GitHub OIDC Provider

This is a one-time, account-level action. Check if it already exists first:

```bash
aws iam list-open-id-connect-providers \
  | grep token.actions.githubusercontent.com
```

If not present, create it:

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

> The thumbprint `6938fd4d98bab03faadb97b34396831e3780aea1` is the GitHub Actions OIDC thumbprint. AWS validates the OIDC token audience, not the thumbprint, so this value is stable. See [GitHub docs](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services) for any updates.

---

## Step 2 — Edit the Parameter File

Open `bootstrap/parameters/github-actions-role-dev.json` and replace `YOUR_GITHUB_ORG` with your GitHub organisation or username:

```json
[
  { "ParameterKey": "GitHubOrg",   "ParameterValue": "my-org" },
  { "ParameterKey": "GitHubRepo",  "ParameterValue": "eks-infra" },
  { "ParameterKey": "Environment", "ParameterValue": "dev" }
]
```

---

## Step 3 — Deploy the IAM Role Stack (via Change Set)

Create the change set:

```bash
aws cloudformation deploy \
  --no-execute-changeset \
  --stack-name github-actions-dev \
  --template-file bootstrap/github-actions-role.yaml \
  --parameter-overrides file://bootstrap/parameters/github-actions-role-dev.json \
  --capabilities CAPABILITY_NAMED_IAM
```

Review the change set in the AWS Console (CloudFormation → Stacks → `github-actions-dev` → Change sets), then execute it.

Retrieve the role ARN:

```bash
aws cloudformation describe-stacks \
  --stack-name github-actions-dev \
  --query "Stacks[0].Outputs[?OutputKey=='RoleArn'].OutputValue" \
  --output text
```

---

## Step 4 — Add GitHub Actions Variables

In the GitHub repository: **Settings → Secrets and variables → Actions → Variables** (not Secrets — these values are not sensitive):

| Variable      | Value                                        |
|---------------|----------------------------------------------|
| `AWS_REGION`  | Your AWS region (e.g. `eu-west-1`)           |
| `ROLE_ARN`    | The role ARN from Step 3                     |

---

## What the IAM Role Can (and Cannot) Do

The `github-actions-dev` role has a least-privilege inline policy:

| Permission | Allowed |
|---|---|
| `cloudformation:CreateChangeSet` | Yes |
| `cloudformation:DescribeChangeSet` | Yes |
| `cloudformation:DescribeStacks` | Yes |
| `cloudformation:ListChangeSets` | Yes |
| `cloudformation:GetTemplateSummary` | Yes |
| `cloudformation:ExecuteChangeSet` | **No** |
| `ec2:Describe*` | Yes (read-only, needed by CFN) |
| `s3:PutObject/GetObject` on `cf-templates-*` | Yes (template upload) |

The role trust policy is scoped to pushes on the `main` branch of this specific repository. A token from any other repo or branch will be denied by `sts:AssumeRoleWithWebIdentity`.

---

## Adding a New Deploy Workflow for a Future Stack

See `docs/runbooks/github-actions-add-stack.md`.

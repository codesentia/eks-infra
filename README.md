# eks-infra

Infrastructure-as-code for a shared EKS platform on AWS. CloudFormation for supporting resources (VPC, IAM), eksctl for cluster lifecycle.

---

## One-Time Bootstrap

> Do this once per AWS account before the CI/CD pipeline can authenticate.

- Fill in `bootstrap/parameters/github-actions-role-dev.json` with your GitHub org/repo
- Register the GitHub OIDC provider in AWS:
  ```bash
  aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
  ```
- Deploy the bootstrap IAM role stack:
  ```bash
  aws cloudformation deploy \
    --no-execute-changeset \
    --stack-name github-actions-dev \
    --template-file bootstrap/github-actions-role.yaml \
    --parameter-overrides file://bootstrap/parameters/github-actions-role-dev.json \
    --capabilities CAPABILITY_NAMED_IAM
  ```
  Review and execute the change set in the AWS Console
- Add `AWS_REGION` and `ROLE_ARN` as GitHub Actions variables in the repository settings (Settings → Secrets and variables → Actions → Variables)

See `bootstrap/README.md` for full details.

---

## Local Setup

```bash
make bootstrap   # create .venv and install all pinned dependencies
make lint-all    # cfn-lint all templates under vpc/ and iam/
make ci          # full CI sequence: bootstrap + lint-all
```

---

## Deploy VPC

```bash
make deploy-vpc-dev
```

Review the `vpc-dev` change set in the AWS Console and execute it.

---

## Deploy IAM Node Role

```bash
make deploy-node-role-dev
```

Review the `iam-node-role-dev` change set in the AWS Console and execute it.

---

## Deploy EKS Cluster (thor)

> Requires `vpc-dev` and `iam-node-role-dev` stacks deployed first.

```bash
make dry-run-cluster-thor   # validate ClusterConfig against live AWS (no resources created)
make create-cluster-thor    # create the cluster (~15 minutes)
kubectl get nodes           # verify both nodes are Ready
make post-create-thor       # associate OIDC provider + store issuer URL in Parameter Store
```

---

## CI/CD (automatic after bootstrap)

| Trigger | Workflow | Action |
|---|---|---|
| Every PR / push to `main` | `ci.yaml` | cfn-lint all templates |
| Push to `main` touching `vpc/**` | `deploy-vpc-dev.yaml` | Create `vpc-dev` change set |
| Push to `main` touching `iam/**` | `deploy-node-role-dev.yaml` | Create `iam-node-role-dev` change set |

All change sets require manual execution in the AWS Console.

---

## Repository Structure

```
bootstrap/      One-time IAM/OIDC setup (not managed by CI)
clusters/       eksctl ClusterConfig templates
docs/           Architecture docs, ADRs, runbooks
iam/            CFN templates for IAM roles
vpc/            CFN templates for VPC and subnets
.github/        GitHub Actions workflows
```

Full documentation: [docs/README.md](docs/README.md)

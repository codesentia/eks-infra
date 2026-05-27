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
make post-create-thor       # associate OIDC provider, deploy VPC CNI IRSA role, install VPC CNI add-on
```

**Note**: `post-create-thor` will pause after creating the VPC CNI role change set. Execute it in the CloudFormation Console, then press Enter to continue.

---

## Install ArgoCD (GitOps)

> Requires `thor` cluster deployed with OIDC provider enabled.

Install ArgoCD as the shared GitOps controller:

```bash
make install-argocd
```

This will:
1. Deploy ArgoCD IRSA role for ECR image pulls (creates CloudFormation change set)
2. Install ArgoCD via Helm to `argocd` namespace
3. Wait for all ArgoCD pods to be Ready
4. Print instructions for accessing the ArgoCD UI

**Note**: You'll be prompted to execute the CloudFormation change set in the Console before Helm installation continues.

**Access ArgoCD UI**:
```bash
# Get admin password
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d

# Port-forward to UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Access at https://localhost:8080 (username: admin)
```

---

## Onboard a Team

> Requires ArgoCD installed.

Onboard a new team with isolated namespace, RBAC, resource quotas, and GitOps:

```bash
make onboard-team \
  TEAM_NAME=phoenix \
  REPO_URL=https://github.com/myorg/phoenix-apps \
  CPU_QUOTA=4 \
  MEMORY_QUOTA=8Gi \
  CONTACT_EMAIL=phoenix@example.com
```

This creates:
- Namespace `team-phoenix` with labels
- ResourceQuota (CPU/memory limits)
- LimitRange (default container limits)
- NetworkPolicy (namespace isolation)
- ServiceAccount with admin RBAC
- ArgoCD AppProject (restricts source repo and destination)

**Validate onboarding**:
```bash
python scripts/validate_team_setup.py --team phoenix
```

**Team GitOps Workflow**: Teams deploy applications by committing manifests to their git repo under `apps/` directories. See [docs/runbooks/team-onboarding.md](docs/runbooks/team-onboarding.md) for complete workflow and troubleshooting.

---

## Destroy Infrastructure

To tear down dev infrastructure (cluster, IAM roles, VPC):

### Individual Component Teardown

```bash
make destroy-cluster-thor      # delete thor cluster only (~10 min)
make destroy-vpc-cni-role-dev  # delete VPC CNI IRSA role stack
make destroy-node-role-dev     # delete node IAM role stack
make destroy-vpc-dev           # delete VPC stack
```

Each target requires confirmation (type `yes` when prompted).

### Full Teardown

```bash
make destroy-all-dev           # destroy all: cluster → VPC CNI role → node role → VPC
```

This orchestrates the four-stage teardown with separate confirmation prompts. For non-interactive use:

```bash
CONFIRM=yes make destroy-all-dev
```

**Safety notes**:
- Cluster deletion removes all workloads and data
- Each destroy operation requires explicit `yes` confirmation
- VPC deletion may fail if resources (ENIs, load balancers) remain — check and remove manually
- Parameter Store entry `/eks/thor/oidc-issuer-url` is preserved (no cost; serves as historical record)

See `docs/runbooks/cluster-bootstrap.md` for detailed teardown guidance and troubleshooting.

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
addons/         Helm values for shared cluster add-ons (ArgoCD, etc.)
namespaces/     Jinja2 templates for team namespace resources
scripts/        Python automation (team onboarding, validation)
docs/           Architecture docs, ADRs, runbooks
iam/            CFN templates for IAM roles
vpc/            CFN templates for VPC and subnets
.github/        GitHub Actions workflows
```

Full documentation: [docs/README.md](docs/README.md)

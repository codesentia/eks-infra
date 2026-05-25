## Context

The repository has a `Makefile` with `bootstrap`, `lint-vpc`, and `deploy-vpc-*` targets. Python dependencies are pinned in `requirements.txt` and managed via a `.venv`. No CI exists yet. The goal is to wire GitHub Actions to these existing Makefile targets rather than duplicating logic in YAML steps.

All CloudFormation deployments must go through change sets with human review — this is a hard constraint from the architecture (ADR, CLAUDE.md convention). The CI/CD system must enforce this: it creates change sets but never executes them automatically.

AWS credentials must follow least-privilege: the GitHub Actions IAM role needs only the permissions to create CFN change sets and describe stacks — not to execute them.

## Goals / Non-Goals

**Goals:**
- Automated cfn-lint gate on every PR and push to `main`
- Manual + file-change-triggered change set creation for `vpc/` (and future stacks)
- OIDC-based AWS credential injection (no stored access keys)
- All CI logic delegated to `make` targets — workflows stay thin
- GitHub Actions IAM role provisioned via CFN with least-privilege inline policy

**Non-Goals:**
- Automatic change set execution
- EKS cluster or add-on deployment via CI
- Multi-environment promotion logic
- Notification integrations

## Decisions

### D1 — OIDC for AWS credentials, not static access keys

**Decision:** GitHub Actions authenticates to AWS via OIDC (`aws-actions/configure-aws-credentials` with `role-to-assume`). No `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` stored as GitHub secrets.

**Rationale:** Static keys are long-lived credentials — they require rotation, can be leaked in logs, and have no automatic expiry. GitHub OIDC tokens are short-lived (scoped to a single workflow run) and bound to the specific repository and branch via IAM trust policy conditions. This is the AWS-recommended approach for CI.

**Trust policy condition** (scoped to the `main` branch for deploy, all refs for lint):
```json
"StringLike": {
  "token.actions.githubusercontent.com:sub": "repo:<org>/<repo>:ref:refs/heads/main"
}
```

**IAM role CFN template:** `iam/github-actions-role.yaml` — parameterised by `GitHubOrg`, `GitHubRepo`, `Environment`. Deployed once per environment.

---

### D2 — Two workflows: `ci.yaml` (always runs) and `deploy-vpc-dev.yaml` (triggered)

**Decision:** Separate CI (lint) from deployment into two workflow files.

| Workflow | Trigger | Does |
|---|---|---|
| `ci.yaml` | PR opened/updated, push to `main` | `make bootstrap && make lint-all` |
| `deploy-vpc-dev.yaml` | `workflow_dispatch` OR push to `main` with `vpc/**` changes | `make deploy-vpc-dev` (change set only) |

**Rationale:** Mixing lint and deploy in one workflow means a lint failure blocks the deploy step rather than reporting them independently. Separate workflows also allow different IAM roles — lint needs no AWS credentials at all; deploy needs CFN change set permissions.

---

### D3 — Workflows call `make` targets, not raw commands

**Decision:** Every meaningful step in a workflow calls `make <target>`, not inline `aws` or `cfn-lint` commands.

**Rationale:** This keeps the workflow YAML thin and testable locally. If the lint command changes (new flags, additional templates), the Makefile changes — the workflow YAML does not. CI and local developer experience stay in sync.

**New Makefile targets needed:**
- `lint-all` — runs cfn-lint on all templates under `vpc/` and `iam/` (glob)
- `ci` — `bootstrap` + `lint-all` in sequence (the exact step CI runs)

---

### D4 — Python dependency caching via `actions/cache` keyed on `requirements.txt` hash

**Decision:** Cache `.venv` in GitHub Actions using `actions/cache`, keyed on `hashFiles('requirements.txt')`.

**Rationale:** `make bootstrap` installs ~77 packages. Without caching, every CI run takes 30–60 seconds just on pip installs. Caching on `requirements.txt` hash means the cache is invalidated automatically when dependencies change.

```yaml
- uses: actions/cache@v4
  with:
    path: .venv
    key: venv-${{ runner.os }}-${{ hashFiles('requirements.txt') }}
```

---

### D5 — GitHub Actions IAM role: CFN change set permissions only

**Decision:** The `github-actions-role` has a least-privilege inline policy allowing only:
- `cloudformation:CreateChangeSet`, `DescribeChangeSet`, `DescribeStacks`, `ListChangeSets`
- `ec2:Describe*` (read-only, needed by CFN to validate VPC resources)
- `iam:PassRole` scoped to the CFN execution role

It explicitly does NOT have `cloudformation:ExecuteChangeSet` — ensuring the workflow cannot deploy without human intervention.

## Risks / Trade-offs

| Risk | Mitigation |
|---|---|
| OIDC provider must be configured in AWS account before first run | Document one-time setup in `docs/runbooks/github-actions-setup.md`; `iam/github-actions-role.yaml` CFN template is self-contained |
| `lint-all` glob must be kept in sync as new CFN templates are added | Makefile glob (`find vpc/ iam/ -name "*.yaml"`) auto-discovers new templates — no manual update needed |
| `deploy-vpc-dev` workflow runs on every push to `main` touching `vpc/` — creates a new change set each time | Change sets are idempotent (new one replaces old if stack is not in progress); operator simply executes the latest one |
| GitHub Actions runner has no AWS credentials for lint job | Intentional — lint is pure static analysis, no AWS calls needed |

## Migration Plan

1. Author `iam/github-actions-role.yaml` CFN template
2. Deploy `iam-github-actions-dev` stack (one-time, manual change set)
3. Add GitHub OIDC provider to AWS account (one-time, `aws iam create-open-id-connect-provider`)
4. Add `lint-all` and `ci` Makefile targets
5. Author `.github/workflows/ci.yaml` and `.github/workflows/deploy-vpc-dev.yaml`
6. Push to a branch — verify CI workflow passes
7. Merge to `main` — verify deploy workflow creates change set

---

### D6 — Bootstrap prerequisites live in `bootstrap/`, deployed once by a human operator

**Decision:** The GitHub OIDC provider registration and `github-actions-role` IAM role are one-time prerequisites that the pipeline cannot create for itself (circular dependency: the pipeline needs the role to run, but the role would be created by the pipeline). These resources live in `bootstrap/` — a self-contained subdirectory within this repo, intentionally isolated from the Makefile and CI workflows.

```
bootstrap/
├── github-actions-role.yaml    # CFN template — OIDC trust + least-privilege inline policy
├── parameters/
│   └── github-actions-role-dev.json
└── README.md                   # One-time setup instructions for a human operator
```

**Rationale:** Keeping the CFN template in this repo maintains a single source of truth and makes the trust policy auditable alongside the workflows it enables. The `bootstrap/` subdirectory name makes the intent explicit: nothing in here is touched by CI. The README is the authoritative procedure for "what an operator does before the first CI run."

**Constraints:**
- The Makefile has no targets that reference `bootstrap/` — it is not part of `make lint-all`, `make ci`, or any deploy target
- CI workflows have no steps that operate on `bootstrap/` contents
- Deployment of `bootstrap/` resources is always a manual operator action via the AWS CLI or console, documented in `bootstrap/README.md`

## Open Questions

_(none — GitHub org/repo name and AWS account ID are needed at template authoring time but are parameterised in the CFN template)_

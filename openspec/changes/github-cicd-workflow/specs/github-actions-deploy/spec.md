## ADDED Requirements

### Requirement: Deploy workflow creates CFN change sets, never executes them
A GitHub Actions workflow `.github/workflows/deploy-vpc-dev.yaml` SHALL create a CloudFormation change set for `vpc-dev` via `make deploy-vpc-dev`. It SHALL NOT execute the change set. Execution remains a manual operator action.

#### Scenario: Workflow creates change set on vpc/ file change
- **WHEN** a push to `main` modifies any file under `vpc/`
- **THEN** the deploy workflow triggers and creates a new `vpc-dev` change set

#### Scenario: Workflow can be triggered manually
- **WHEN** an operator triggers the workflow via `workflow_dispatch` in the GitHub UI
- **THEN** the deploy workflow runs and creates a change set regardless of which files changed

#### Scenario: Workflow never executes a change set
- **WHEN** the deploy workflow completes successfully
- **THEN** the `vpc-dev` stack status is `REVIEW_IN_PROGRESS` (change set exists but not applied)

---

### Requirement: AWS credentials injected via OIDC, no stored secrets
The deploy workflow SHALL authenticate to AWS using `aws-actions/configure-aws-credentials` with `role-to-assume` pointing to the `github-actions-role` IAM role. No `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` SHALL be stored as GitHub repository secrets.

#### Scenario: Workflow assumes role via OIDC token
- **WHEN** the deploy workflow runs
- **THEN** AWS credentials are obtained via `sts:AssumeRoleWithWebIdentity` using the GitHub OIDC token — no static keys are present in the environment

#### Scenario: OIDC trust is scoped to main branch
- **WHEN** the deploy workflow is triggered from a branch other than `main`
- **THEN** the `sts:AssumeRoleWithWebIdentity` call is denied by the IAM trust policy condition

---

### Requirement: GitHub Actions IAM role provisioned via CFN with least-privilege policy
A CFN template `iam/github-actions-role.yaml` SHALL provision an IAM role with an OIDC trust policy scoped to the specific GitHub repository and `main` branch. Its inline policy SHALL allow only CFN change set creation and read operations — explicitly excluding `cloudformation:ExecuteChangeSet`.

#### Scenario: Role cannot execute a change set
- **WHEN** an IAM policy simulation is run for `cloudformation:ExecuteChangeSet`
- **THEN** the action is denied

#### Scenario: Role trust policy is scoped to the correct repository
- **WHEN** a token from a different GitHub repository attempts to assume the role
- **THEN** `sts:AssumeRoleWithWebIdentity` is denied by the trust policy condition

#### Scenario: Role is deployed via change set
- **WHEN** `iam/github-actions-role.yaml` is deployed
- **THEN** it is created via a CloudFormation change set, consistent with platform convention

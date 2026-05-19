## ADDED Requirements

### Requirement: Onboarding script provisions namespace and IRSA role
A script `scripts/onboard-team.py` SHALL accept `--team`, `--env`, `--admin-group`, and `--developer-group` arguments and, in a single invocation, create the namespace manifest directory, deploy the namespace bundle, and deploy a CFN IRSA role stack for the team.

#### Scenario: New team is fully onboarded in one command
- **WHEN** `scripts/onboard-team.py --team payments --env dev --admin-group payments-admins --developer-group payments-devs` is run
- **THEN** the `payments` namespace exists in the cluster, resource quota, LimitRange, NetworkPolicy, and RBAC are applied, and a `eks-<cluster>-payments-role` IRSA role exists in IAM

#### Scenario: Script is idempotent
- **WHEN** the same onboard command is run a second time
- **THEN** no error is returned and no duplicate resources are created

---

### Requirement: Onboarding script validates prerequisites
The script SHALL verify that the target cluster exists and is reachable, the VPC CFN stack outputs are available, and the required IAM permissions for the operator are present before making any changes.

#### Scenario: Script fails fast if cluster is unreachable
- **WHEN** `KUBECONFIG` points to a non-existent cluster
- **THEN** the script exits with a non-zero code and a human-readable error before applying any manifests

---

### Requirement: Validation script checks namespace posture
A script `scripts/validate-namespace.py` SHALL accept `--team` and `--env` and verify that the namespace has a default-deny NetworkPolicy, a ResourceQuota, a LimitRange, and that RBAC bindings are correct.

#### Scenario: Validation passes for a correctly configured namespace
- **WHEN** all five manifests are applied and the IRSA role is in place
- **THEN** `scripts/validate-namespace.py --team payments --env dev` exits 0 and prints a pass summary

#### Scenario: Validation fails and reports missing NetworkPolicy
- **WHEN** the NetworkPolicy manifest is absent
- **THEN** `scripts/validate-namespace.py` exits non-zero and identifies the missing NetworkPolicy in its output

---

### Requirement: Onboarding documented in runbook
A runbook `docs/team-onboarding.md` SHALL describe the end-to-end onboarding procedure including prerequisites, the onboard-team.py invocation, validation steps, and how to offboard a team.

#### Scenario: Runbook covers all required sections
- **WHEN** `docs/team-onboarding.md` is reviewed
- **THEN** it contains sections for Prerequisites, Onboarding Steps, Validation, and Offboarding

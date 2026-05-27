## ADDED Requirements

### Requirement: Automated namespace creation with baseline resources
A Python script SHALL exist at `scripts/onboard_team.py` that accepts team parameters (name, git repo URL, resource quotas, contact email) and creates a Kubernetes namespace with RBAC roles, ResourceQuota, LimitRange, and NetworkPolicy resources. The script SHALL render Jinja2 templates from `namespaces/templates/` and apply them to the cluster using `kubectl apply`. The script SHALL be idempotent — re-running with the same parameters SHALL NOT fail or create duplicate resources.

#### Scenario: Successful team onboarding
- **WHEN** `python scripts/onboard_team.py --team phoenix --repo https://github.com/myorg/phoenix-apps --cpu 4 --memory 8Gi --contact phoenix@example.com` is run with valid cluster credentials
- **THEN** namespace `team-phoenix` is created, RBAC roles exist, ResourceQuota shows `cpu: 4` and `memory: 8Gi` limits, NetworkPolicy default-deny is active, and script exits 0

#### Scenario: Onboarding with invalid team name
- **WHEN** onboarding script is run with team name containing uppercase or special characters (e.g., `Team_One`)
- **THEN** script fails validation before applying any resources and prints error message requiring lowercase alphanumeric names

#### Scenario: Idempotent re-run updates quotas
- **WHEN** onboarding script is run twice for the same team with different CPU quota (first `--cpu 4`, then `--cpu 8`)
- **THEN** second run updates the ResourceQuota in-place, no duplicate namespace is created, and script exits 0

---

### Requirement: Namespace templates with security baselines
Jinja2 templates SHALL exist under `namespaces/templates/` for Namespace, ResourceQuota, LimitRange, and NetworkPolicy resources. Templates SHALL parameterize `{{ team_name }}`, `{{ cpu_quota }}`, `{{ memory_quota }}`, `{{ contact_email }}`, and `{{ repo_url }}`. The NetworkPolicy template SHALL default to deny all ingress and allow egress to kube-dns (UDP 53), same namespace, and Kubernetes API (TCP 443). ResourceQuota SHALL limit `requests.cpu`, `requests.memory`, `limits.cpu`, `limits.memory`, and `count/pods`. LimitRange SHALL set default container request/limit values to prevent unbounded resource consumption.

#### Scenario: Rendered namespace has contact label
- **WHEN** template is rendered with `contact_email=phoenix@example.com`
- **THEN** Namespace manifest contains label `platform.io/contact: phoenix@example.com`

#### Scenario: Default network policy blocks cross-namespace ingress
- **WHEN** NetworkPolicy is applied to `team-phoenix` namespace
- **THEN** pods in `team-alpha` namespace cannot initiate TCP connections to pods in `team-phoenix` namespace (verified by validation script)

#### Scenario: LimitRange provides default requests/limits
- **WHEN** a pod without resource requests/limits is created in the namespace
- **THEN** Kubernetes mutates the pod to have default `requests.cpu: 100m`, `requests.memory: 128Mi`, `limits.cpu: 500m`, `limits.memory: 512Mi` from LimitRange

---

### Requirement: RBAC for team namespace admin
Each onboarded namespace SHALL have a RoleBinding that grants a team-specific ServiceAccount full admin permissions within the namespace. The ServiceAccount SHALL be named `team-<name>-admin` and bound to ClusterRole `admin` (Kubernetes built-in) scoped to the namespace. Teams MAY create additional ServiceAccounts and Roles for CI/CD pipelines with narrower permissions.

#### Scenario: Team admin can create deployments
- **WHEN** kubectl command is run with ServiceAccount `team-phoenix-admin` in namespace `team-phoenix`
- **THEN** creating, updating, and deleting Deployments, Services, ConfigMaps, and Secrets succeeds

#### Scenario: Team admin cannot access other namespaces
- **WHEN** kubectl command is run with ServiceAccount `team-phoenix-admin` targeting namespace `team-alpha`
- **THEN** all operations fail with permission denied (RBAC blocks cross-namespace access)

#### Scenario: Team admin cannot create cluster-scoped resources
- **WHEN** ServiceAccount `team-phoenix-admin` attempts to create a ClusterRole or Namespace
- **THEN** operation fails with permission denied (ClusterRole `admin` does not grant cluster-scoped permissions)

---

### Requirement: Makefile target for onboarding
A Makefile target `onboard-team` SHALL wrap the Python onboarding script with required parameters passed as environment variables or Make arguments. The target SHALL validate that required parameters (`TEAM_NAME`, `REPO_URL`, `CPU_QUOTA`, `MEMORY_QUOTA`, `CONTACT_EMAIL`) are set before invoking the script. The target SHALL echo the onboarding command for operator review before execution.

#### Scenario: Make target with all parameters succeeds
- **WHEN** `make onboard-team TEAM_NAME=phoenix REPO_URL=https://github.com/myorg/phoenix-apps CPU_QUOTA=4 MEMORY_QUOTA=8Gi CONTACT_EMAIL=phoenix@example.com` is run
- **THEN** onboarding script is invoked with correct parameters and namespace is created

#### Scenario: Make target fails if required parameter missing
- **WHEN** `make onboard-team TEAM_NAME=phoenix` is run without `REPO_URL`
- **THEN** Make target exits with error before calling Python script and prints message listing missing parameters

---

### Requirement: Validation script for onboarding completeness
A Python script SHALL exist at `scripts/validate_team_setup.py` that accepts a team name and verifies namespace resources are correctly configured. The script SHALL check: namespace exists, ResourceQuota is set, LimitRange is present, NetworkPolicy is active, team-admin ServiceAccount exists, RoleBinding exists, and ArgoCD AppProject exists (in `argocd` namespace). The script SHALL test NetworkPolicy enforcement by creating ephemeral test pods in two namespaces and verifying cross-namespace traffic is blocked. The script SHALL exit 0 if all checks pass, exit 1 with detailed error output if any check fails.

#### Scenario: Validation passes for correctly onboarded team
- **WHEN** `python scripts/validate_team_setup.py --team phoenix` is run after successful onboarding
- **THEN** all checks pass (green checkmarks printed for each resource), NetworkPolicy test confirms isolation, script exits 0

#### Scenario: Validation detects missing ResourceQuota
- **WHEN** validation script is run for a namespace where ResourceQuota was manually deleted
- **THEN** script prints error "ResourceQuota not found in team-phoenix", lists expected quota values, and exits 1

#### Scenario: Validation detects NetworkPolicy misconfiguration
- **WHEN** validation script runs test pods and detects cross-namespace traffic is NOT blocked
- **THEN** script prints warning "NetworkPolicy enforcement failed: pod in team-alpha reached pod in team-phoenix on port 8080", provides troubleshooting steps, and exits 1

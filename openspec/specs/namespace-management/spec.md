## ADDED Requirements

### Requirement: Namespace manifest bundle per team
A directory `namespaces/<team-name>/` SHALL exist for each team and SHALL contain: `namespace.yaml`, `resource-quota.yaml`, `limit-range.yaml`, `network-policy.yaml`, and `rbac.yaml`.

#### Scenario: All required manifest files are present
- **WHEN** `ls namespaces/<team-name>/` is run
- **THEN** all five manifest files are present

---

### Requirement: ResourceQuota limits CPU and memory
The `ResourceQuota` SHALL set hard limits on `requests.cpu`, `requests.memory`, `limits.cpu`, and `limits.memory` appropriate to the team's tier, preventing one team from consuming the entire cluster.

#### Scenario: Pod creation fails when quota is exceeded
- **WHEN** a team deploys a pod that would push the namespace over its `limits.cpu` quota
- **THEN** the pod creation is rejected with a quota exceeded error

---

### Requirement: LimitRange sets default resource requests
The `LimitRange` SHALL set default CPU request/limit and memory request/limit on containers that do not specify their own, ensuring pods are always accounted for in scheduling.

#### Scenario: Container without resource spec gets defaults
- **WHEN** a pod is created without resource requests or limits
- **THEN** the pod's container has the LimitRange defaults applied

---

### Requirement: Default-deny NetworkPolicy
Each namespace SHALL have a `NetworkPolicy` that denies all ingress and egress by default, with explicit allow rules for intra-namespace traffic and ingress from the `ingress-nginx` or ALB controller namespace.

#### Scenario: Cross-namespace traffic is blocked by default
- **WHEN** a pod in team-a attempts to connect to a pod in team-b on any port
- **THEN** the connection is rejected

#### Scenario: Intra-namespace traffic is permitted
- **WHEN** a pod in team-a connects to another pod in team-a
- **THEN** the connection succeeds

#### Scenario: ALB ingress traffic reaches team pods
- **WHEN** an external request arrives via the ALB and is routed to a team-a service
- **THEN** the request reaches the backing pod

---

### Requirement: RBAC — admin and developer roles
The `rbac.yaml` SHALL bind an `admin` group to the `admin` ClusterRole within the namespace, and a `developer` group to a custom `developer` Role that allows read/write on Deployments, Services, ConfigMaps, and Secrets but not RBAC resources.

#### Scenario: Developer cannot modify RBAC
- **WHEN** a developer-group user attempts `kubectl create rolebinding` in their namespace
- **THEN** the request is denied with a 403

#### Scenario: Admin can manage all resources in namespace
- **WHEN** an admin-group user applies any manifest in their namespace
- **THEN** the apply succeeds

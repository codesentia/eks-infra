## Context

The `thor` EKS cluster is deployed with VPC, IAM node roles, and VPC CNI configured. Node groups are running and the cluster is operational. However, no mechanism exists for teams to deploy applications. The platform needs a repeatable, secure process to onboard teams and enable GitOps-driven deployments.

**Current state:**
- Cluster: `thor` (Kubernetes 1.35, us-east-1)
- Node groups: `system` (tainted for cluster add-ons) and `application` (for tenant workloads)
- OIDC provider: enabled, issuer stored at `/eks/thor/oidc-issuer-url`
- No namespaces created beyond `kube-system`, `kube-public`, `kube-node-lease`, `default`
- No GitOps tooling installed

**Constraints:**
- Least-privilege IAM: IRSA roles for any component needing AWS API access
- Namespace isolation: network policies must prevent cross-tenant traffic
- GitOps-first: teams should not `kubectl apply` directly; manifests live in git
- Template-driven: onboarding must be automated and consistent across teams

## Goals / Non-Goals

**Goals:**
- Install ArgoCD as the platform GitOps controller (single installation shared by all teams)
- Provide a Python script that creates a new team namespace with RBAC, quotas, and network policies
- Enable teams to deploy applications via ArgoCD ApplicationSets that discover apps from team-owned git repos
- Validate namespace setup post-onboarding to catch misconfiguration early

**Non-Goals:**
- Multi-cluster ArgoCD (single cluster only)
- Tenant-scoped ArgoCD instances (shared ArgoCD, namespace-scoped ApplicationSets)
- Automated namespace deletion or offboarding
- Integration with external IdP for RBAC (cluster-local ServiceAccounts only)
- Cost allocation or chargeback per namespace

## Decisions

### Decision 1: Install ArgoCD before onboarding first team

**Why:** ArgoCD is the shared service that all teams depend on for application deployment. Installing it as part of the first team onboarding would conflate cluster-level setup with team-specific setup and make the second team's onboarding inconsistent.

**Alternatives considered:**
- Flux CD: ArgoCD chosen for richer UI, ApplicationSet support, and stronger multi-tenancy primitives (AppProject per team)
- No GitOps tool (direct kubectl): violates GitOps-ready architecture principle

**Implementation:** New `Makefile` target `install-argocd` deploys ArgoCD via official Helm chart to `argocd` namespace. IRSA role for ArgoCD controller grants `ecr:GetAuthorizationToken` and `ecr:BatchGetImage` to pull images from ECR.

---

### Decision 2: Namespace templates with Jinja2 rendering

**Why:** Teams have common requirements (RBAC roles, quotas, network policies) but team-specific values (namespace name, resource limits, contact labels). Jinja2 templates allow a single source of truth with parameterization.

**Alternatives considered:**
- Helm chart for namespaces: overkill for simple YAML rendering; Helm adds dependency complexity
- Kustomize: lacks native templating for team-specific substitutions; would require wrapper script anyway

**Implementation:** Python script `scripts/onboard_team.py` reads templates from `namespaces/templates/`, substitutes team-specific values, and `kubectl apply`s the rendered manifests. Template variables: `{{ team_name }}`, `{{ cpu_quota }}`, `{{ memory_quota }}`, `{{ contact_email }}`.

---

### Decision 3: Network policies default-deny ingress, allow egress to cluster DNS and API

**Why:** Least-privilege network posture. Teams should not receive cross-namespace traffic unless explicitly allowed. Egress to kube-dns and Kubernetes API is required for basic pod operation.

**Alternatives considered:**
- No network policies (default Kubernetes behavior): violates namespace isolation principle
- Default-deny egress: breaks DNS resolution and API server communication; too restrictive for initial onboarding

**Implementation:** Each namespace gets a `NetworkPolicy` manifest with:
```yaml
policyTypes: [Ingress, Egress]
ingress: []  # default-deny
egress:
  - to: [{namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: kube-system}}}]
    ports: [{protocol: UDP, port: 53}]  # kube-dns
  - to: [{podSelector: {}}]  # same namespace
  - to: [{namespaceSelector: {}}]
    ports: [{protocol: TCP, port: 443}]  # Kubernetes API
```

Teams can add ingress rules later (e.g., from ingress controller namespace) via their own NetworkPolicy resources.

---

### Decision 4: Per-team AppProject in ArgoCD with source repo restriction

**Why:** Prevents team A from deploying applications defined in team B's repo. AppProjects provide RBAC boundary within ArgoCD.

**Alternatives considered:**
- Single default AppProject: no isolation; any Application can deploy to any namespace
- Namespace-scoped ArgoCD installations: operational overhead (multiple ArgoCD instances to upgrade)

**Implementation:** Onboarding script creates an `AppProject` resource in `argocd` namespace with:
```yaml
metadata:
  name: team-<name>
spec:
  sourceRepos: ['https://github.com/<org>/<team>-apps']
  destinations:
    - namespace: team-<name>
      server: 'https://kubernetes.default.svc'
  clusterResourceWhitelist: []  # no cluster-scoped resources
```

Team provides their git repo URL as an onboarding parameter.

---

### Decision 5: Optional per-team IRSA roles, not mandatory

**Why:** Not all workloads need AWS API access. Creating unused IRSA roles adds IAM sprawl. Offer as an opt-in onboarding parameter.

**Alternatives considered:**
- Always create per-team IRSA role: wasteful for stateless apps that don't touch AWS APIs
- Never create IRSA roles: teams must request manually later, slowing onboarding for AWS-dependent workloads

**Implementation:** Onboarding script accepts `--irsa-policies` flag (comma-separated managed policy ARNs). If provided, deploys a CFN stack `iam-<team>-role-dev` with trust policy for `system:serviceaccount:team-<name>:*` and attached policies. Teams annotate their ServiceAccount with the role ARN.

## Risks / Trade-offs

**[Risk]** ArgoCD IRSA role has broad ECR read access across all repos in the AWS account  
**Mitigation:** Future enhancement: per-team ECR repos with IAM boundary; for now, assume all images in shared ECR are trusted (dev environment acceptable risk)

**[Risk]** Onboarding script runs `kubectl apply` directly, could fail mid-onboarding and leave partial state  
**Mitigation:** Script validates all manifests with `kubectl apply --dry-run=client` before applying; validation script at end detects incomplete onboarding

**[Risk]** Network policy enforcement depends on CNI plugin support; VPC CNI supports it, but misconfiguration could silently fail  
**Mitigation:** Validation script creates test pods in two namespaces and verifies cross-namespace traffic is blocked (NetworkPolicy check)

**[Risk]** Team git repo URL typo in onboarding parameters breaks ApplicationSet discovery  
**Mitigation:** Onboarding script validates repo URL is reachable (HTTP 200 or git ls-remote succeeds) before creating AppProject

**[Trade-off]** Shared ArgoCD means cluster-admin must upgrade ArgoCD, affecting all teams simultaneously  
**Accepted:** Simplifies operations vs. tenant-scoped ArgoCD instances; maintenance windows can be scheduled

**[Trade-off]** Namespace quotas are hard limits; teams hitting quota must file ticket for increase  
**Accepted:** Prevents resource sprawl; quotas can be adjusted post-onboarding by updating Namespace manifest via onboarding script re-run (idempotent)

## Migration Plan

**Prerequisites:**
- `thor` cluster deployed with OIDC provider enabled
- `kubectl` context set to `thor`
- AWS credentials with IAM permissions to create IRSA roles (CloudFormation)

**Steps:**

1. **Install ArgoCD** (one-time, cluster-wide):
   ```bash
   make install-argocd
   ```
   - Deploys ArgoCD to `argocd` namespace via Helm
   - Creates IRSA role `eks-thor-argocd-role` with ECR pull permissions
   - Waits for ArgoCD pods to reach Ready state
   - Outputs ArgoCD admin password from Secret

2. **Onboard first team** (example: team-phoenix):
   ```bash
   make onboard-team \
     TEAM_NAME=phoenix \
     REPO_URL=https://github.com/myorg/phoenix-apps \
     CPU_QUOTA=4 \
     MEMORY_QUOTA=8Gi \
     CONTACT_EMAIL=phoenix@example.com
   ```
   - Calls `scripts/onboard_team.py` with parameters
   - Creates namespace `team-phoenix`, RBAC, quotas, network policies
   - Creates ArgoCD AppProject `team-phoenix` with repo restriction

3. **Validate onboarding**:
   ```bash
   python scripts/validate_team_setup.py --team phoenix
   ```
   - Checks namespace exists, quotas set, RBAC bindings present
   - Verifies NetworkPolicy blocks cross-namespace traffic
   - Confirms AppProject exists in ArgoCD

4. **Team deploys first application** (in team's repo `phoenix-apps`):
   - Team commits Application manifest:
     ```yaml
     apiVersion: argoproj.io/v1alpha1
     kind: Application
     metadata:
       name: phoenix-webapp
       namespace: argocd
     spec:
       project: team-phoenix
       source:
         repoURL: https://github.com/myorg/phoenix-apps
         path: apps/webapp
       destination:
         server: https://kubernetes.default.svc
         namespace: team-phoenix
     ```
   - ArgoCD syncs application to `team-phoenix` namespace

**Rollback strategy:**
- ArgoCD uninstall: `helm uninstall argocd -n argocd`, delete IRSA role stack
- Team namespace removal: `kubectl delete namespace team-<name>`, delete AppProject, delete IRSA role stack (if created)
- Changes are isolated; rollback does not affect other teams or cluster operation

## Open Questions

1. **Should ArgoCD UI be exposed via Ingress or port-forward only?**  
   Proposal: Port-forward for now (dev cluster); Ingress + OAuth2 proxy in future for prod

2. **What is the default CPU/memory quota per namespace?**  
   Proposal: `cpu: 4`, `memory: 8Gi` as starting point; adjust based on workload patterns

3. **How do teams request IRSA role policy changes post-onboarding?**  
   Proposal: Teams file PR to update `iam/<team>-role.yaml`, platform team reviews and deploys via CFN change set

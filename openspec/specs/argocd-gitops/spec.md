## ADDED Requirements

### Requirement: ArgoCD installation via Helm chart
ArgoCD SHALL be installed to the `argocd` namespace using the official Helm chart from `https://argoproj.github.io/argo-helm`. The installation SHALL use Helm values that configure the ArgoCD controller ServiceAccount with an IRSA annotation pointing to the `eks-thor-argocd-role` IAM role. A Makefile target `install-argocd` SHALL automate the installation, create the IRSA role via CloudFormation, retrieve the role ARN, render Helm values with the ARN substituted, and wait for all ArgoCD pods to reach Ready state before exiting. The target SHALL be idempotent — re-running SHALL upgrade the Helm release in-place.

#### Scenario: Fresh ArgoCD installation succeeds
- **WHEN** `make install-argocd` is run on a cluster without ArgoCD
- **THEN** `argocd` namespace is created, IRSA role stack `iam-argocd-ecr-role-dev` is deployed, Helm release `argocd` is installed, all pods in `argocd` namespace reach Running state, and Make target prints ArgoCD admin password retrieval command

#### Scenario: Re-running install-argocd upgrades Helm release
- **WHEN** `make install-argocd` is run on a cluster where ArgoCD is already installed with an older Helm chart version
- **THEN** Helm performs an upgrade (not a fresh install), IRSA role stack shows no changes, ArgoCD pods are restarted with new chart version, and Make target exits 0

#### Scenario: IRSA role grants ECR pull permissions
- **WHEN** ArgoCD controller reconciles an Application referencing an ECR image
- **THEN** controller pod successfully pulls the image using IAM role credentials (no imagePullSecrets required), image pull succeeds, and Application syncs

---

### Requirement: IRSA role for ArgoCD with ECR access
A CloudFormation template SHALL exist at `iam/argocd-ecr-role.yaml` defining an IAM role with trust policy for ServiceAccount `system:serviceaccount:argocd:argocd-application-controller` and `system:serviceaccount:argocd:argocd-server`. The role SHALL have a managed policy attached granting `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, and `ecr:GetDownloadUrlForLayer` actions on all ECR repositories in the AWS account. The role name SHALL be `eks-thor-argocd-role`. Parameters SHALL include `OIDCIssuerHost`, `ClusterName`, and `Environment`.

#### Scenario: ArgoCD controller can assume the role
- **WHEN** ArgoCD controller pod starts with ServiceAccount annotated `eks.amazonaws.com/role-arn: <role-arn>`
- **THEN** pod's environment contains `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE`, STS AssumeRoleWithWebIdentity succeeds, and controller has temporary credentials

#### Scenario: Role ARN is exported from CloudFormation stack
- **WHEN** IRSA role stack is deployed
- **THEN** stack exports output `ArgoCDRoleArn` with value matching the created role ARN, and Makefile target can reference it via `aws cloudformation describe-stacks`

---

### Requirement: Per-team AppProject with source repo and namespace restrictions
Each onboarded team SHALL have an ArgoCD AppProject resource created in the `argocd` namespace with name `team-<name>`. The AppProject SHALL restrict `spec.sourceRepos` to the single git repository URL provided during onboarding. The AppProject SHALL restrict `spec.destinations` to server `https://kubernetes.default.svc` and namespace `team-<name>` only. The AppProject SHALL set `spec.clusterResourceWhitelist: []` to prevent creation of cluster-scoped resources. The AppProject SHALL allow all namespaced resource types via `spec.namespaceResourceWhitelist: [{group: '*', kind: '*'}]`.

#### Scenario: AppProject creation during onboarding
- **WHEN** onboarding script is run with `--repo https://github.com/myorg/phoenix-apps`
- **THEN** AppProject `team-phoenix` is created in `argocd` namespace with `sourceRepos: ['https://github.com/myorg/phoenix-apps']` and `destinations: [{server: 'https://kubernetes.default.svc', namespace: 'team-phoenix'}]`

#### Scenario: Application restricted to team's source repo
- **WHEN** team creates an Application in project `team-phoenix` referencing a different repo `https://github.com/otherorg/other-apps`
- **THEN** ArgoCD rejects the Application with error "source repository not permitted by project"

#### Scenario: Application restricted to team's namespace
- **WHEN** team creates an Application in project `team-phoenix` with destination namespace `team-alpha`
- **THEN** ArgoCD rejects the Application with error "destination namespace not permitted by project"

#### Scenario: Application cannot create cluster-scoped resources
- **WHEN** team's application manifests include a ClusterRole resource
- **THEN** ArgoCD sync fails with error "cluster-scoped resources not permitted by project", Application health is Degraded

---

### Requirement: ArgoCD ApplicationSet pattern for team repos
Documentation SHALL provide an example ApplicationSet manifest that teams can use to auto-discover applications in their git repository. The ApplicationSet SHALL use the `git` generator with `directories` mode to discover subdirectories under `apps/` in the team's repo. Each discovered directory SHALL generate an Application resource with project `team-<name>`, source path `apps/<directory>`, and destination namespace `team-<name>`. Teams SHALL commit the ApplicationSet manifest to their own repo and apply it to the `argocd` namespace using their team-admin ServiceAccount.

#### Scenario: ApplicationSet discovers new app directory
- **WHEN** team commits a new directory `apps/webapp` to their repo with Kubernetes manifests
- **THEN** ApplicationSet controller creates Application `team-phoenix-webapp`, Application syncs manifests to `team-phoenix` namespace, and pods are created

#### Scenario: ApplicationSet deletes Application when directory removed
- **WHEN** team deletes directory `apps/webapp` from their repo
- **THEN** ApplicationSet controller deletes Application `team-phoenix-webapp`, ArgoCD prunes resources in `team-phoenix` namespace, and pods are terminated

#### Scenario: ApplicationSet generator respects AppProject restrictions
- **WHEN** ApplicationSet generates an Application from directory `apps/webapp`
- **THEN** generated Application references project `team-phoenix`, source repo matches team's allowed repo, destination namespace is `team-phoenix`, and ArgoCD accepts the Application

---

### Requirement: ArgoCD UI access via kubectl port-forward
The `install-argocd` Makefile target SHALL print instructions for accessing the ArgoCD UI via `kubectl port-forward` and retrieving the admin password from the `argocd-initial-admin-secret` Secret. Ingress exposure of the ArgoCD UI is NOT in scope for this change (future enhancement). Operators and teams SHALL use port-forward for dev cluster access.

#### Scenario: Operator retrieves admin password
- **WHEN** operator runs `kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d`
- **THEN** command prints the ArgoCD admin password in plaintext

#### Scenario: Operator accesses ArgoCD UI
- **WHEN** operator runs `kubectl port-forward svc/argocd-server -n argocd 8080:443` and navigates to `https://localhost:8080` in browser
- **THEN** ArgoCD login page is displayed, operator can log in with username `admin` and retrieved password

---

### Requirement: Documentation for team GitOps workflow
A runbook SHALL exist at `docs/runbooks/team-onboarding.md` documenting the end-to-end team onboarding process and GitOps workflow. The runbook SHALL include: prerequisites checklist (cluster deployed, ArgoCD installed), onboarding command with example parameters, validation script usage, instructions for teams to structure their git repo (required directory layout `apps/<app-name>/`), example Application and ApplicationSet manifests, troubleshooting section for common ArgoCD sync errors (image pull failures, RBAC denials, NetworkPolicy blocks), and contact information for platform team support.

#### Scenario: New team follows runbook successfully
- **WHEN** a new team reads the runbook and executes onboarding command, sets up their git repo with `apps/` directory, and commits an ApplicationSet manifest
- **THEN** team's namespace is created, ApplicationSet discovers their app, Application syncs to the cluster, and team's workload is running

#### Scenario: Troubleshooting section addresses image pull failure
- **WHEN** team's Application sync fails with error "ImagePullBackOff: failed to pull ECR image"
- **THEN** runbook troubleshooting section provides steps to verify ECR repo exists, check image tag, confirm ArgoCD IRSA role permissions, and inspect ArgoCD controller logs

## 1. ArgoCD IRSA Role

- [x] 1.1 Create `iam/argocd-ecr-role.yaml`: IAM role with trust policy for ServiceAccounts `system:serviceaccount:argocd:argocd-application-controller` and `system:serviceaccount:argocd:argocd-server`, ManagedPolicyArn granting `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:GetDownloadUrlForLayer` on `*`, parameters `OIDCIssuerHost`, `ClusterName`, `Environment`, role name `eks-thor-argocd-role`, output export `ArgoCDRoleArn` [change-set required]
- [x] 1.2 Create `iam/parameters/argocd-ecr-role-dev.json`: parameters file with `ClusterName=thor`, `Environment=dev`, placeholder for `OIDCIssuerHost` (resolved by Makefile)

## 2. ArgoCD Installation

- [x] 2.1 Add `install-argocd` Makefile target: fetch OIDC issuer URL from Parameter Store at `/eks/thor/oidc-issuer-url`, strip `https://` prefix, deploy IRSA role CFN stack `iam-argocd-ecr-role-dev` with change set (pause for manual execution), fetch role ARN from stack outputs, render Helm values file with ArgoCD controller ServiceAccount annotation `eks.amazonaws.com/role-arn: <ARN>`, add Helm repo `https://argoproj.github.io/argo-helm`, install Helm release `argocd` to `argocd` namespace with rendered values, wait for pods Ready, print admin password retrieval command [shared service — coordinate with teams]
- [x] 2.2 Create `addons/argocd-values.yaml.tpl`: Helm values template for ArgoCD with placeholders `${ARGOCD_ROLE_ARN}`, configure `server.serviceAccount.annotations`, `controller.serviceAccount.annotations`, disable ingress (use port-forward for dev cluster), set `server.extraArgs: ['--insecure']` for non-TLS access via port-forward

## 3. Namespace Templates

- [x] 3.1 Create `namespaces/templates/` directory
- [x] 3.2 Create `namespaces/templates/namespace.yaml.j2`: Namespace manifest template with `metadata.name: team-{{ team_name }}`, labels `platform.io/team: {{ team_name }}`, `platform.io/contact: {{ contact_email }}`, `platform.io/repo: {{ repo_url }}`
- [x] 3.3 Create `namespaces/templates/resource-quota.yaml.j2`: ResourceQuota manifest template with `spec.hard` limiting `requests.cpu: {{ cpu_quota }}`, `requests.memory: {{ memory_quota }}`, `limits.cpu: {{ cpu_quota }}`, `limits.memory: {{ memory_quota }}`, `count/pods: 50`, name `team-{{ team_name }}-quota`
- [x] 3.4 Create `namespaces/templates/limit-range.yaml.j2`: LimitRange manifest template with `spec.limits[0].type: Container`, `default.cpu: 500m`, `default.memory: 512Mi`, `defaultRequest.cpu: 100m`, `defaultRequest.memory: 128Mi`, `max.cpu: 2`, `max.memory: 4Gi`, name `team-{{ team_name }}-limits`
- [x] 3.5 Create `namespaces/templates/network-policy.yaml.j2`: NetworkPolicy manifest template with `spec.podSelector: {}`, `policyTypes: [Ingress, Egress]`, `ingress: []` (default-deny), `egress` allowing: [{to: [{namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: kube-system}}}], ports: [{protocol: UDP, port: 53}]}] (kube-dns), [{to: [{podSelector: {}}]}] (same namespace), [{to: [{namespaceSelector: {}}], ports: [{protocol: TCP, port: 443}]}] (Kubernetes API), name `team-{{ team_name }}-isolation`
- [x] 3.6 Create `namespaces/templates/rbac.yaml.j2`: ServiceAccount `team-{{ team_name }}-admin`, RoleBinding binding ServiceAccount to ClusterRole `admin` scoped to namespace `team-{{ team_name }}`
- [x] 3.7 Create `namespaces/templates/appproject.yaml.j2`: ArgoCD AppProject manifest with `metadata.name: team-{{ team_name }}`, `metadata.namespace: argocd`, `spec.sourceRepos: ['{{ repo_url }}']`, `spec.destinations: [{namespace: 'team-{{ team_name }}', server: 'https://kubernetes.default.svc'}]`, `spec.clusterResourceWhitelist: []`, `spec.namespaceResourceWhitelist: [{group: '*', kind: '*'}]`

## 4. Onboarding Script

- [x] 4.1 Create `scripts/onboard_team.py`: Python 3.10+ script with argparse accepting `--team`, `--repo`, `--cpu`, `--memory`, `--contact`, optional `--irsa-policies`; validate team name is lowercase alphanumeric; load Jinja2 templates from `namespaces/templates/`; render templates with provided parameters; run `kubectl apply --dry-run=client` on all rendered manifests to validate; if validation passes, run `kubectl apply -f -` piping rendered manifests; if `--irsa-policies` provided, deploy CFN stack `iam-team-<name>-role-dev` with trust policy for `system:serviceaccount:team-<name>:*` and attached policy ARNs; print success message with namespace name and AppProject name; exit 0 on success, exit 1 on validation error
- [x] 4.2 Add Python dependencies to `requirements.in`: `jinja2`, `pyyaml`; run `pip-compile requirements.in` to update `requirements.txt`
- [ ] 4.3 Test onboarding script locally: run `python scripts/onboard_team.py --team test-alpha --repo https://github.com/test/test-apps --cpu 2 --memory 4Gi --contact test@example.com` against `thor` cluster; verify namespace created, all resources present; run script again with same parameters (idempotency test); delete namespace and re-run (fresh creation test) [MANUAL - requires live cluster]

## 5. Validation Script

- [x] 5.1 Create `scripts/validate_team_setup.py`: Python 3.10+ script with argparse accepting `--team`; check namespace `team-<name>` exists; check ResourceQuota, LimitRange, NetworkPolicy, ServiceAccount, RoleBinding exist; check ArgoCD AppProject `team-<name>` exists in `argocd` namespace; create ephemeral test pods in two namespaces (using `kubectl run --rm -i --image=busybox` with `wget -T 2` to test connectivity), verify cross-namespace traffic is blocked; print green checkmark for each passing check, red X with error details for each failing check; exit 0 if all pass, exit 1 if any fail
- [ ] 5.2 Test validation script: run `python scripts/validate_team_setup.py --team test-alpha` after onboarding; verify all checks pass; manually delete ResourceQuota, re-run validation, verify error is detected; restore ResourceQuota [MANUAL - requires live cluster]

## 6. Makefile Integration

- [x] 6.1 Add `onboard-team` Makefile target: validate required variables `TEAM_NAME`, `REPO_URL`, `CPU_QUOTA`, `MEMORY_QUOTA`, `CONTACT_EMAIL` are set (exit with error if missing); echo onboarding command for operator review; call `python scripts/onboard_team.py` with variables passed as arguments; add help text: `## Onboard a new team (requires TEAM_NAME, REPO_URL, CPU_QUOTA, MEMORY_QUOTA, CONTACT_EMAIL)`
- [x] 6.2 Update Makefile help text for `install-argocd` target: `## [shared service] Install ArgoCD to argocd namespace with IRSA role for ECR`

## 7. Documentation

- [x] 7.1 Create `docs/runbooks/team-onboarding.md`: Prerequisites section (cluster deployed, OIDC provider enabled, ArgoCD installed via `make install-argocd`), Onboarding section with example command `make onboard-team TEAM_NAME=phoenix REPO_URL=https://github.com/myorg/phoenix-apps CPU_QUOTA=4 MEMORY_QUOTA=8Gi CONTACT_EMAIL=phoenix@example.com`, Validation section with command `python scripts/validate_team_setup.py --team phoenix`, Team GitOps Workflow section with required git repo structure (`apps/<app-name>/` directories), example Application manifest, example ApplicationSet manifest using `git` generator with `directories` mode, Accessing ArgoCD UI section with port-forward command and admin password retrieval, Troubleshooting section covering: image pull failures (ECR permissions, IRSA role check), RBAC denials (AppProject restrictions, namespace bindings), NetworkPolicy blocks (egress rules for external services), ArgoCD sync errors (manifest validation, resource quotas exceeded), contact information for platform team support
- [x] 7.2 Update `docs/README.md`: add link to `runbooks/team-onboarding.md` under "Runbooks" section

## 8. Validation with Real Team Onboarding

> Prerequisites: `thor` cluster deployed, ArgoCD installed via `make install-argocd`

- [ ] 8.1 Deploy ArgoCD IRSA role: run `make install-argocd` (includes IRSA role deployment), execute CFN change set for `iam-argocd-ecr-role-dev` in AWS Console, wait for ArgoCD pods Ready [MANUAL - requires live cluster]
- [ ] 8.2 Verify ArgoCD installation: run `kubectl get pods -n argocd`, confirm all pods Running; retrieve admin password with `kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d`; port-forward `kubectl port-forward svc/argocd-server -n argocd 8080:443`; access `https://localhost:8080`, log in with admin credentials [MANUAL - requires live cluster]
- [ ] 8.3 Onboard first test team: run `make onboard-team TEAM_NAME=phoenix REPO_URL=https://github.com/myorg/phoenix-apps CPU_QUOTA=4 MEMORY_QUOTA=8Gi CONTACT_EMAIL=phoenix@example.com`; verify namespace `team-phoenix` created [MANUAL - requires live cluster]
- [ ] 8.4 Run validation: `python scripts/validate_team_setup.py --team phoenix`; confirm all checks pass including NetworkPolicy isolation test [MANUAL - requires live cluster]
- [ ] 8.5 Test ArgoCD AppProject: in ArgoCD UI, verify AppProject `team-phoenix` exists with correct source repo and destination namespace restrictions; attempt to create Application with wrong repo URL, verify ArgoCD rejects it [MANUAL - requires live cluster]
- [ ] 8.6 Test team GitOps workflow: in team's git repo `phoenix-apps`, create directory `apps/nginx-test/` with Deployment and Service manifests; commit ApplicationSet manifest (using example from runbook) to repo; apply ApplicationSet to cluster with `kubectl apply -f applicationset.yaml -n argocd`; verify ArgoCD discovers application, creates Application `team-phoenix-nginx-test`, syncs manifests, pods start in `team-phoenix` namespace [MANUAL - requires live cluster]
- [ ] 8.7 Test resource limits: in `team-phoenix` namespace, create a pod without resource requests/limits; verify LimitRange mutates pod with default values; create ResourceQuota-exceeding deployment (e.g., 10 replicas with 1 CPU each when quota is 4); verify deployment is rejected or pods remain Pending with quota exceeded message [MANUAL - requires live cluster]
- [ ] 8.8 Test cross-namespace isolation: create second test namespace `team-alpha` with onboarding script; run validation script for both teams; manually test cross-namespace connectivity (curl from phoenix pod to alpha service), verify connection is blocked by NetworkPolicy [MANUAL - requires live cluster]

## 9. Optional: Per-Team IRSA Role Template

- [x] 9.1 Create `iam/team-role-template.yaml`: CFN template with parameters `TeamName`, `OIDCIssuerHost`, `ClusterName`, `Environment`, `PolicyArns` (CommaDelimitedList); IAM role with trust policy for `system:serviceaccount:team-${TeamName}:*`; loop over `PolicyArns` parameter to attach each as ManagedPolicyArn; output `TeamRoleArn`; note in comments that this is optional and created on demand via `--irsa-policies` flag [change-set required]
- [ ] 9.2 Update `scripts/onboard_team.py`: if `--irsa-policies` provided, deploy CFN stack `iam-team-<name>-role-dev` using `team-role-template.yaml`, resolve OIDC issuer from Parameter Store, create change set, print message instructing operator to execute change set, wait for stack completion, fetch role ARN, print instructions for team to annotate ServiceAccount with `eks.amazonaws.com/role-arn: <ARN>` [OPTIONAL - enhancement for future]

## 10. Final Review and Cleanup

- [x] 10.1 Run `make help`: confirm `install-argocd` and `onboard-team` targets appear with clear descriptions and tags
- [x] 10.2 Lint all Python scripts: run `black scripts/onboard_team.py scripts/validate_team_setup.py`, ensure PEP 8 compliance
- [x] 10.3 Review all CFN templates: run `make lint-all`, confirm no cfn-lint errors for `iam/argocd-ecr-role.yaml` and optional `iam/team-role-template.yaml`
- [ ] 10.4 Test cleanup: delete test namespaces `team-phoenix` and `team-alpha` with `kubectl delete namespace <name>`; delete AppProjects in ArgoCD UI; confirm no orphaned resources [MANUAL - requires live cluster]

# Team Onboarding Runbook

This runbook guides you through onboarding a new team to the EKS platform, enabling them to deploy applications via GitOps using ArgoCD.

---

## Prerequisites

Before onboarding a team, ensure:

- [x] EKS cluster `thor` is deployed and healthy
- [x] OIDC provider is enabled (run `make post-create-thor` after cluster creation)
- [x] ArgoCD is installed (run `make install-argocd`)
- [x] Team has a git repository for application manifests
- [x] Team provides: team name, git repo URL, contact email, resource quota requirements

---

## Onboarding a Team

### Example Command

```bash
make onboard-team \
  TEAM_NAME=phoenix \
  REPO_URL=https://github.com/myorg/phoenix-apps \
  CPU_QUOTA=4 \
  MEMORY_QUOTA=8Gi \
  CONTACT_EMAIL=phoenix@example.com
```

### Parameters

- **TEAM_NAME**: Lowercase alphanumeric team identifier (e.g., `phoenix`, `data-eng`)
- **REPO_URL**: Git repository URL where team stores application manifests
- **CPU_QUOTA**: Total CPU cores available to the team (e.g., `4`)
- **MEMORY_QUOTA**: Total memory available to the team (e.g., `8Gi`, `16Gi`)
- **CONTACT_EMAIL**: Team contact email for alerts and notifications

### What Gets Created

The onboarding script creates:

1. **Namespace** `team-<name>` with labels identifying the team
2. **ResourceQuota** limiting CPU, memory, and pod count
3. **LimitRange** setting default resource requests/limits for containers
4. **NetworkPolicy** enforcing namespace isolation (default-deny ingress)
5. **ServiceAccount** `team-<name>-admin` with full admin permissions in the namespace
6. **RoleBinding** granting the ServiceAccount admin access
7. **ArgoCD AppProject** `team-<name>` restricting source repo and destination namespace

---

## Validation

After onboarding, validate the setup:

```bash
python scripts/validate_team_setup.py --team phoenix
```

Expected output:

```
Validating onboarding for team: phoenix
Namespace: team-phoenix

✓ Namespace team-phoenix exists with correct labels
✓ ResourceQuota team-phoenix-quota exists
✓ LimitRange team-phoenix-limits exists
✓ NetworkPolicy team-phoenix-isolation exists
✓ ServiceAccount and RoleBinding exist
✓ AppProject team-phoenix exists in argocd namespace
✓ NetworkPolicy configured with Ingress and Egress rules

✓ All validation checks passed!
```

---

## Team GitOps Workflow

### Git Repository Structure

Teams must structure their git repository as follows:

```
phoenix-apps/
├── apps/
│   ├── webapp/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── ingress.yaml
│   └── api/
│       ├── deployment.yaml
│       └── service.yaml
└── applicationset.yaml
```

- **`apps/` directory**: Each subdirectory represents one application
- **Application manifests**: Standard Kubernetes YAML files
- **`applicationset.yaml`**: ArgoCD ApplicationSet to auto-discover apps

### Example Application Manifest

`apps/webapp/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp
  namespace: team-phoenix
spec:
  replicas: 2
  selector:
    matchLabels:
      app: webapp
  template:
    metadata:
      labels:
        app: webapp
    spec:
      containers:
        - name: webapp
          image: <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/phoenix-webapp:v1.0.0
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
```

### Example ApplicationSet Manifest

`applicationset.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: phoenix-apps
  namespace: argocd
spec:
  generators:
    - git:
        repoURL: https://github.com/myorg/phoenix-apps
        revision: main
        directories:
          - path: apps/*
  template:
    metadata:
      name: 'phoenix-{{path.basename}}'
    spec:
      project: team-phoenix
      source:
        repoURL: https://github.com/myorg/phoenix-apps
        targetRevision: main
        path: '{{path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: team-phoenix
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

### Deploying the ApplicationSet

Team applies the ApplicationSet to the cluster:

```bash
kubectl apply -f applicationset.yaml -n argocd
```

ArgoCD will:
1. Discover all directories under `apps/`
2. Create an Application resource for each directory
3. Sync application manifests to the `team-phoenix` namespace

---

## Accessing ArgoCD UI

### Retrieve Admin Password

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d
```

### Port-Forward to ArgoCD Server

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### Access UI

1. Open browser to `https://localhost:8080`
2. Username: `admin`
3. Password: (from command above)

---

## Troubleshooting

### Image Pull Failures

**Symptom**: Pods stuck in `ImagePullBackOff` or `ErrImagePull`

**Causes**:
- ECR repository does not exist
- Image tag is incorrect
- ArgoCD IRSA role lacks ECR pull permissions

**Resolution**:
1. Verify ECR repository exists: `aws ecr describe-repositories --repository-names <repo-name>`
2. Check image tag exists: `aws ecr list-images --repository-name <repo-name>`
3. Verify ArgoCD IRSA role has ECR permissions:
   ```bash
   aws iam get-role --role-name eks-thor-argocd-role
   ```
4. Check ArgoCD controller logs:
   ```bash
   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
   ```

### RBAC Denials

**Symptom**: ArgoCD Application sync fails with "forbidden" errors

**Causes**:
- Application references wrong AppProject
- Application attempts to deploy to different namespace
- Application attempts to create cluster-scoped resources

**Resolution**:
1. Verify Application specifies correct project:
   ```yaml
   spec:
     project: team-phoenix  # must match team name
   ```
2. Verify destination namespace matches team namespace:
   ```yaml
   spec:
     destination:
       namespace: team-phoenix
   ```
3. Check AppProject restrictions:
   ```bash
   kubectl get appproject team-phoenix -n argocd -o yaml
   ```

### NetworkPolicy Blocks

**Symptom**: Pods cannot reach external services or APIs

**Causes**:
- Default NetworkPolicy only allows traffic to kube-dns, same namespace, and Kubernetes API
- Team needs egress to external services (AWS APIs, third-party APIs, databases)

**Resolution**:
Add additional NetworkPolicy to allow egress:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-external-egress
  namespace: team-phoenix
spec:
  podSelector:
    matchLabels:
      app: webapp
  policyTypes:
    - Egress
  egress:
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 169.254.169.254/32  # Block EC2 metadata service
      ports:
        - protocol: TCP
          port: 443
```

### ArgoCD Sync Errors

**Symptom**: Application health is "Degraded" or "Unknown"

**Common Errors**:
1. **Resource quota exceeded**: Team has hit CPU/memory limits
   - Check quota usage: `kubectl describe resourcequota -n team-phoenix`
   - Request quota increase via onboarding script re-run with higher values

2. **Invalid manifest syntax**: YAML validation failures
   - Check Application details in ArgoCD UI for error messages
   - Validate manifests locally: `kubectl apply --dry-run=client -f <manifest>`

3. **Missing CRDs**: Application references CustomResourceDefinitions not installed
   - Install required CRDs in the cluster before syncing the Application

---

## Resource Quota Adjustments

To increase a team's resource quota after onboarding:

```bash
make onboard-team \
  TEAM_NAME=phoenix \
  REPO_URL=https://github.com/myorg/phoenix-apps \
  CPU_QUOTA=8 \
  MEMORY_QUOTA=16Gi \
  CONTACT_EMAIL=phoenix@example.com
```

The onboarding script is idempotent and will update the ResourceQuota in-place.

---

## Platform Team Support

For assistance with onboarding or troubleshooting, contact the platform team:

- **Email**: platform-team@example.com
- **Slack**: #eks-platform
- **Documentation**: https://docs.example.com/eks-platform

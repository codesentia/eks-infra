# Team Onboarding & Application Deployment Guide

Quick reference for onboarding teams and deploying applications to the EKS platform.

---

## Prerequisites

- EKS cluster `thor` deployed and running
- ArgoCD installed (`make install-argocd`)
- kubectl configured for the cluster
- Team's application repository on GitHub

---

## Step 1: Install ArgoCD (One-Time Setup)

```bash
cd ~/Documents/my-repos/eks-infra
make install-argocd
```

This installs ArgoCD to the `argocd` namespace with ECR access.

**Access ArgoCD UI:**
```bash
# Get admin password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d

# Port-forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open: https://localhost:8080
# Login: admin / <password from above>
```

---

## Step 2: Onboard a Team

```bash
make onboard-team \
  TEAM_NAME=phoenix \
  REPO_URL=https://github.com/codesentia/phoenix-app \
  CPU_QUOTA=2 \
  MEMORY_QUOTA=4Gi \
  CONTACT_EMAIL=rhabed@gmail.com
```

**What This Creates:**
- Namespace: `team-phoenix`
- ResourceQuota: 2 CPU cores, 4Gi memory
- NetworkPolicy: Default-deny with kube-dns access
- ServiceAccount: `team-phoenix-admin` with namespace admin rights
- ArgoCD AppProject: `team-phoenix` (restricts repo and namespace)

**Verify Onboarding:**
```bash
python scripts/validate_team_setup.py --team phoenix
```

---

## Step 3: Configure Repository Access (Private Repos Only)

If your application repository is private, ArgoCD needs credentials:

**Option A: GitHub Personal Access Token**
1. Create token: https://github.com/settings/tokens/new
   - Scope: `repo` (Full control of private repositories)
2. Add to ArgoCD:
   ```bash
   kubectl create secret generic phoenix-app-repo \
     -n argocd \
     --from-literal=type=git \
     --from-literal=url=https://github.com/codesentia/phoenix-app \
     --from-literal=password=YOUR_GITHUB_TOKEN \
     --from-literal=username=not-used \
     --dry-run=client -o yaml | \
     kubectl label -f- argocd.argoproj.io/secret-type=repository --local --dry-run=client -o yaml | \
     kubectl apply -f -
   ```

**Option B: Make Repository Public**
- Go to repo settings → Change visibility → Public
- No credentials needed

---

## Step 4: Deploy Application via ArgoCD

Your application repository must have this structure:

```
phoenix-app/
├── apps/
│   ├── webapp/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── configmap.yaml
│   └── api/
│       ├── deployment.yaml
│       └── service.yaml
└── applicationset.yaml
```

**Deploy the ApplicationSet:**
```bash
# From your app repo
cd /tmp/phoenix-app

# Make sure applicationset.yaml has correct repo URL
git add applicationset.yaml
git commit -m "Configure ApplicationSet"
git push origin main

# Apply to cluster
kubectl apply -f applicationset.yaml
```

**Wait for ArgoCD to Sync:**
```bash
# Watch Applications appear (~30-60 seconds)
kubectl get applications -n argocd -w

# Watch pods start
kubectl get pods -n team-phoenix -w
```

---

## Step 5: Access Your Applications

### Check Deployment Status

```bash
# Check Applications in ArgoCD
kubectl get applications -n argocd

# Expected output:
# NAME             SYNC STATUS   HEALTH STATUS
# phoenix-api      Synced        Healthy
# phoenix-webapp   Synced        Healthy

# Check running pods
kubectl get pods -n team-phoenix

# Expected output:
# NAME                      READY   STATUS    RESTARTS   AGE
# api-xxxxxxxxxx-xxxxx      1/1     Running   0          2m
# webapp-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
# webapp-xxxxxxxxxx-yyyyy   1/1     Running   0          2m
```

### Access Webapp

```bash
# Port-forward to webapp
kubectl port-forward -n team-phoenix svc/webapp 8080:80

# Open in browser: http://localhost:8080
# You should see a purple gradient page with platform info
```

### Access API

```bash
# Port-forward to API
kubectl port-forward -n team-phoenix svc/api 8081:80

# Test in another terminal:
curl http://localhost:8081/get
curl http://localhost:8081/headers
```

---

## Troubleshooting

### No Applications Created

**Check ApplicationSet status:**
```bash
kubectl describe applicationset phoenix-app -n argocd
```

**Common issues:**
- Repository not found → Check repo URL and credentials
- No directories found → Ensure `apps/*/` directories exist in repo

**Fix:**
```bash
# Force refresh by restarting ApplicationSet controller
kubectl delete pod -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller
```

### Pods Not Starting

**Check pod status:**
```bash
kubectl describe pod -n team-phoenix <pod-name>
kubectl logs -n team-phoenix <pod-name>
```

**Common issues:**
- ImagePullBackOff → Check image name and registry access
- CrashLoopBackOff → Check application logs
- Pending → Check resource quotas

### ArgoCD Sync Failures

**Check Application details:**
```bash
kubectl describe application phoenix-webapp -n argocd
```

**View in ArgoCD UI:**
- Navigate to Applications → Select app → View sync errors

---

## Making Changes (GitOps Workflow)

1. **Edit application manifests** in your repo
   ```bash
   cd /tmp/phoenix-app
   # Example: Scale webapp to 3 replicas
   sed -i 's/replicas: 2/replicas: 3/' apps/webapp/deployment.yaml
   ```

2. **Commit and push**
   ```bash
   git add apps/webapp/deployment.yaml
   git commit -m "Scale webapp to 3 replicas"
   git push
   ```

3. **Watch ArgoCD auto-sync** (~3 minutes)
   ```bash
   kubectl get pods -n team-phoenix -w
   ```

---

## Quick Reference Commands

```bash
# Check onboarding status
python scripts/validate_team_setup.py --team phoenix

# List all teams
kubectl get namespaces -l platform.io/team

# Check team quotas
kubectl describe resourcequota -n team-phoenix

# View ArgoCD Applications
kubectl get applications -n argocd

# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Watch pods
kubectl get pods -n team-phoenix -w

# Port-forward to service
kubectl port-forward -n team-phoenix svc/webapp 8080:80
```

---

## What We Built

**Infrastructure:**
- EKS cluster `thor` with VPC, IAM roles, VPC CNI
- ArgoCD GitOps controller with IRSA for ECR
- Automated team onboarding with namespace isolation

**Team Phoenix:**
- Isolated namespace: `team-phoenix`
- Resource quotas: 2 CPU, 4Gi memory
- Network policies: Default-deny with DNS/API access
- RBAC: Team admin ServiceAccount

**Applications Deployed:**
- **webapp**: Nginx with custom HTML (2 replicas)
- **api**: HTTPBin testing API (1 replica)

Both deployed and managed via ArgoCD GitOps.

---

## Next Steps

1. **Add Ingress**: Expose services via AWS Load Balancer Controller
2. **Configure Monitoring**: Set up Prometheus/Grafana
3. **Add CI/CD**: GitHub Actions to build/push custom images to ECR
4. **Onboard More Teams**: Repeat process for additional teams
5. **Add Secrets Management**: Integrate AWS Secrets Manager

---

## Support

- **Documentation**: `docs/runbooks/team-onboarding.md`
- **Troubleshooting**: Full guide in application README
- **Platform Team**: Contact for quota increases or issues

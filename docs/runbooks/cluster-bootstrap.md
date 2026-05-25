# Cluster Bootstrap — thor (dev)

This runbook covers the ordered steps to bring the `thor` EKS cluster from zero to running. It assumes a fresh state — no cluster exists yet.

---

## Prerequisites

Both of the following CloudFormation stacks must be deployed and in `CREATE_COMPLETE` or `UPDATE_COMPLETE` state before proceeding:

```bash
aws cloudformation describe-stacks --stack-name vpc-dev \
  --query "Stacks[0].StackStatus" --output text

aws cloudformation describe-stacks --stack-name iam-node-role-dev \
  --query "Stacks[0].StackStatus" --output text
```

If `vpc-dev` is not deployed, run `make deploy-vpc-dev` and execute the change set first (see `docs/runbooks/github-actions-add-stack.md` for the pattern).

---

## Step 1 — Validate the ClusterConfig

Resolve CFN exports and run eksctl in dry-run mode — no AWS resources are created:

```bash
make dry-run-cluster-thor
```

This resolves all `vpc-dev` and `iam-node-role-dev` exports, renders `clusters/thor.yaml.tpl` to `/tmp/thor-resolved.yaml`, and runs `eksctl create cluster --dry-run`. Fix any validation errors before proceeding.

---

## Step 2 — Create the Cluster

```bash
make create-cluster-thor
```

This takes approximately **15 minutes**. eksctl creates two CloudFormation stacks internally:
- `eksctl-thor-cluster` — EKS control plane
- `eksctl-thor-nodegroup-system` and `eksctl-thor-nodegroup-application` — managed node groups

If the command is interrupted, check the status of these stacks in the AWS Console before retrying. Do not re-run `make create-cluster-thor` if the stacks are still in progress.

---

## Step 3 — Verify Nodes

```bash
aws eks update-kubeconfig --name thor --region us-east-1
kubectl get nodes -o wide
```

Both node groups should show nodes in `Ready` state — one `system` node and one `application` node.

---

## Step 4 — Associate the OIDC Provider

```bash
make post-create-thor
```

This runs `eksctl utils associate-iam-oidc-provider`, then fetches the OIDC issuer URL from the cluster and stores it in Parameter Store at `/eks/thor/oidc-issuer-url`.

Verify:

```bash
aws ssm get-parameter --name /eks/thor/oidc-issuer-url --query "Parameter.Value" --output text
```

The stored URL is the handoff point for all future IRSA role stacks. **Do not skip this step** — without it, every IRSA role trust policy will be unresolvable.

---

## Step 5 — Verify Control Plane Logs

In the AWS Console: CloudWatch → Log groups → `/aws/eks/thor/cluster`

All five log streams should be present: `api`, `audit`, `authenticator`, `controllerManager`, `scheduler`.

---

## Next Steps

With the cluster running and the OIDC provider registered, the next changes are:

1. **IRSA roles** — cluster-autoscaler, VPC CNI, EBS CSI, ALB controller (each a separate CFN stack in `iam/`)
2. **Cluster add-ons** — Helm values under `addons/` (cert-manager, external-dns, ingress controller, observability)
3. **ArgoCD bootstrap** — App of Apps pattern, per `docs/architecture/gitops-deployment-model.md`

---

## Rollback

To delete the cluster and all eksctl-managed resources:

```bash
eksctl delete cluster --name thor --region us-east-1
```

This deletes the `eksctl-thor-*` CloudFormation stacks. The `vpc-dev` and `iam-node-role-dev` stacks are **not** affected.

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

## Step 4 — Post-Create Setup: OIDC, VPC CNI IRSA Role, and VPC CNI Add-on

```bash
make post-create-thor
```

This target orchestrates three critical post-creation steps to migrate VPC CNI from node-role-based permissions to IRSA:

1. **OIDC Provider Association**: Runs `eksctl utils associate-iam-oidc-provider` and stores the OIDC issuer URL in Parameter Store at `/eks/thor/oidc-issuer-url`
2. **VPC CNI IRSA Role Deployment**: Creates a CloudFormation change set for `iam-vpc-cni-role-dev` stack (dedicated IAM role for VPC CNI pods)
3. **VPC CNI Add-on Installation**: Installs the IRSA-enabled VPC CNI add-on version, replacing the default CNI that uses node role permissions

**Note**: During cluster creation (Step 2), the default VPC CNI uses the node IAM role which includes `AmazonEKS_CNI_Policy`. After this post-create step, the VPC CNI switches to using IRSA for least-privilege IAM. The node role policy can optionally be removed later (see "Optional: Node Role Cleanup" below).

**Important**: The Makefile will pause after creating the VPC CNI role change set. You must:
- Open the AWS CloudFormation Console
- Navigate to the `iam-vpc-cni-role-dev` stack
- Review and execute the change set
- Return to the terminal and press Enter to continue

After completion, verify the VPC CNI add-on is running:

```bash
kubectl get daemonset -n kube-system aws-node
```

All pods should reach `Ready` state within 2-3 minutes. Also verify:

```bash
aws ssm get-parameter --name /eks/thor/oidc-issuer-url --query "Parameter.Value" --output text
```

The stored URL is the handoff point for all future IRSA role stacks. **Do not skip this step** — without it, pod networking will not function and every IRSA role trust policy will be unresolvable.

---

## Step 5 — Verify Control Plane Logs

In the AWS Console: CloudWatch → Log groups → `/aws/eks/thor/cluster`

All five log streams should be present: `api`, `audit`, `authenticator`, `controllerManager`, `scheduler`.

---

## Optional: Node Role Cleanup (Least-Privilege)

**Only after confirming the VPC CNI IRSA setup is working**, you can optionally remove `AmazonEKS_CNI_Policy` from the node IAM role to follow strict least-privilege principles:

```bash
# Verify VPC CNI is using IRSA (check annotations)
kubectl get serviceaccount aws-node -n kube-system -o yaml | grep eks.amazonaws.com/role-arn

# If IRSA role ARN is present, safe to proceed
# Update node-role.yaml to remove AmazonEKS_CNI_Policy
# Then update the stack
aws cloudformation deploy \
  --stack-name iam-node-role-dev \
  --template-file iam/node-role.yaml \
  --parameter-overrides file://iam/parameters/node-role-dev.json \
  --capabilities CAPABILITY_NAMED_IAM

# Verify VPC CNI still works after node role update
kubectl get pods -n kube-system -l k8s-app=aws-node
# Test pod scheduling
kubectl run test-cleanup --image=nginx --rm -it -- echo "CNI works"
```

**Note**: This cleanup is optional. Leaving the policy on the node role does not compromise security — the VPC CNI prefers IRSA when available and will use the node role as a fallback only if IRSA fails.

---

## Troubleshooting

### NetworkPluginNotReady Error

**Symptom**: Pods stuck in `Pending` or `ContainerCreating` state. Node shows `NetworkReady=false` with message:
```
container runtime network not ready: NetworkReady=false reason:NetworkPluginNotReady
message:Network plugin returns error: cni plugin not initialized
```

**Root cause**: The VPC CNI add-on is not running or not configured correctly.

**Resolution**:

1. Check if the `aws-node` DaemonSet is present and all pods are Ready:
   ```bash
   kubectl get daemonset -n kube-system aws-node
   kubectl get pods -n kube-system -l k8s-app=aws-node
   ```

2. If DaemonSet is missing or pods are not starting, verify the VPC CNI IRSA role exists:
   ```bash
   aws cloudformation describe-stacks --stack-name iam-vpc-cni-role-dev --query "Stacks[0].StackStatus"
   ```

3. If the role is missing, deploy it:
   ```bash
   make deploy-vpc-cni-role-dev
   # Execute the change set in AWS Console
   ```

4. Install or update the VPC CNI add-on:
   ```bash
   make install-vpc-cni-addon-thor
   ```

5. Check VPC CNI pod logs for detailed errors:
   ```bash
   kubectl logs -n kube-system -l k8s-app=aws-node --tail=50
   ```

6. Verify the IRSA role trust policy matches the cluster OIDC issuer:
   ```bash
   aws iam get-role --role-name eks-thor-vpc-cni-role --query "Role.AssumeRolePolicyDocument"
   aws eks describe-cluster --name thor --query "cluster.identity.oidc.issuer"
   ```

### VPC CNI Add-on Installation Fails

If `eksctl create addon` fails with "service account not found":
- The cluster may have been created without `iam.withOIDC: true`
- Run `eksctl utils associate-iam-oidc-provider --cluster thor --region us-east-1 --approve`
- Retry `make install-vpc-cni-addon-thor`

---

## Next Steps

With the cluster running, OIDC provider registered, and VPC CNI add-on operational, the next changes are:

1. **Additional IRSA roles** — cluster-autoscaler, EBS CSI, ALB controller (each a separate CFN stack in `iam/`)
2. **Cluster add-ons** — Helm values under `addons/` (cert-manager, external-dns, ingress controller, observability)
3. **ArgoCD bootstrap** — App of Apps pattern, per `docs/architecture/gitops-deployment-model.md`

---

## Teardown

To safely tear down the `thor` cluster and supporting infrastructure, use the destroy targets in reverse dependency order.

### Individual Component Teardown

Delete components individually when you want to preserve some infrastructure:

**1. Delete the cluster only:**
```bash
make destroy-cluster-thor
```
Removes the `thor` EKS cluster and all eksctl-managed stacks (control plane, node groups). Preserves VPC and IAM resources.

**2. Delete the VPC CNI IRSA role:**
```bash
make destroy-vpc-cni-role-dev
```
Removes the `iam-vpc-cni-role-dev` CloudFormation stack. Only run this after the cluster is deleted.

**3. Delete the node IAM role:**
```bash
make destroy-node-role-dev
```
Removes the `iam-node-role-dev` CloudFormation stack. Only run this after the cluster and VPC CNI role are deleted.

**4. Delete the VPC:**
```bash
make destroy-vpc-dev
```
Removes the `vpc-dev` CloudFormation stack. Only run this after all other resources are deleted.

### Full Teardown

To destroy all dev infrastructure in one command:

```bash
make destroy-all-dev
```

This orchestrates the four-stage teardown: cluster → VPC CNI role → node role → VPC. Each stage prompts for confirmation separately. You can abort at any stage by typing anything other than `yes`.

**Non-interactive mode** (for CI or scripts):
```bash
CONFIRM=yes make destroy-all-dev
```

**Important notes:**
- Each destroy operation requires explicit confirmation (type `yes` when prompted)
- Cluster deletion takes ~10 minutes; VPC and IAM deletions are faster
- The `/eks/thor/oidc-issuer-url` Parameter Store entry is **not** auto-deleted (no cost impact; serves as historical record)
- To manually delete the Parameter Store entry: `aws ssm delete-parameter --name /eks/thor/oidc-issuer-url`

### Troubleshooting Teardown

**VPC deletion fails with dependency errors:**

Check for remaining resources:
```bash
# Check for ENIs
aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=<VPC_ID>" --query "NetworkInterfaces[*].[NetworkInterfaceId,Description]"

# Check for load balancers
aws elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='<VPC_ID>'].[LoadBalancerName,LoadBalancerArn]"
```

If ENIs or load balancers remain, delete them manually before retrying VPC deletion.

**Cluster deletion interrupted (network failure, Ctrl+C):**

Check the status of eksctl-managed stacks:
```bash
aws cloudformation describe-stacks --stack-name eksctl-thor-cluster --query "Stacks[0].StackStatus"
aws cloudformation describe-stacks --stack-name eksctl-thor-nodegroup-system --query "Stacks[0].StackStatus"
```

If stacks are stuck in `DELETE_IN_PROGRESS`, wait for completion or delete manually from the CloudFormation console.

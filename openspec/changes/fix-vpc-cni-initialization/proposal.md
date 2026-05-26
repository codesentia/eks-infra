## Why

The `thor` EKS cluster deployment fails with `NetworkPluginNotReady` errors when pods attempt to start. The container runtime reports:

```
container runtime network not ready: NetworkReady=false reason:NetworkPluginNotReady 
message:Network plugin returns error: cni plugin not initialized
```

This error indicates the AWS VPC CNI plugin (`aws-node` DaemonSet) is not successfully initializing on cluster nodes. Without a functioning CNI, pods cannot be assigned IP addresses from the VPC subnet pool, and the cluster is non-functional.

Root cause: The VPC CNI plugin is an EKS add-on that must be explicitly installed and configured. The current `thor.yaml.tpl` ClusterConfig does not declare any add-ons — eksctl creates the cluster but does not install the VPC CNI add-on, leaving nodes in a "network not ready" state.

## What Changes

- Update `clusters/thor.yaml.tpl` — add `addons` section declaring the `vpc-cni` EKS add-on with explicit version and configuration
- Specify VPC CNI version compatible with Kubernetes 1.35 (latest stable: `v1.19.x-eksbuild.y`)
- Configure VPC CNI to use IRSA for IAM permissions (references OIDC provider; requires post-create OIDC association step to already be complete)
- Add IAM role for VPC CNI pod identity: new CFN template `iam/vpc-cni-role.yaml` with trust policy for the `kube-system:aws-node` service account, attached policy `AmazonEKS_CNI_Policy`
- Update Makefile `resolve-cluster-thor` target to also resolve the VPC CNI IAM role ARN and substitute it into the ClusterConfig template
- **Keep** `AmazonEKS_CNI_Policy` on `iam/node-role.yaml` during cluster creation (allows default VPC CNI to function); optionally remove after IRSA-based VPC CNI is confirmed working
- Update `docs/runbooks/cluster-bootstrap.md` — clarify that VPC CNI IRSA role must be deployed after OIDC association, before cluster creation; add troubleshooting section for CNI initialization failures

## Capabilities

### New Capabilities

- **VPC CNI IRSA role**: Pod identity for the VPC CNI plugin, following least-privilege IAM pattern (no reliance on node role for CNI permissions)

### Modified Capabilities

- **eks-cluster**: Add-ons are now declared in the ClusterConfig template; eksctl installs VPC CNI during cluster creation
- **iam-roles**: Node role no longer carries `AmazonEKS_CNI_Policy` — CNI uses dedicated IRSA role

## Impact

- The VPC CNI add-on is explicitly declared in the ClusterConfig, ensuring it is installed at cluster creation time
- Cluster creation now requires the VPC CNI IRSA role to exist before running `create-cluster-thor` (new dependency)
- Deployment order becomes: `vpc-dev` → `iam-node-role-dev` → OIDC association → `iam-vpc-cni-role-dev` → `create-cluster-thor`
- Existing clusters (if `thor` is already deployed) require add-on installation via `eksctl create addon` or AWS Console (migration path documented)

## Non-goals

- Installing other EKS add-ons (kube-proxy, CoreDNS) — VPC CNI is the blocker; other add-ons are separate changes
- Custom CNI configuration (SNAT, prefix delegation, security groups for pods) — default configuration resolves the immediate error; advanced CNI tuning is deferred
- Self-managed CNI installation (Helm, kubectl apply) — EKS add-ons are the preferred installation method per AWS best practices

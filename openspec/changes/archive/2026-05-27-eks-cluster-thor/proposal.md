## Why

The VPC (`berry-vpc`) and node IAM role (`eks-thor-node-role`) are deployed. The eksctl ClusterConfig is the next prerequisite — without it there is no cluster and no platform to run workloads on.

## What Changes

- New `clusters/thor.yaml` — eksctl ClusterConfig for the `thor` dev cluster: Kubernetes 1.35, two managed node groups (`system` and `application`), references `berry-vpc` subnets and `eks-thor-node-role` by ID/ARN, control-plane logging enabled, public API endpoint (dev convenience)
- New `Makefile` targets: `create-cluster-thor` (eksctl create cluster), `dry-run-cluster-thor` (validation without AWS calls)
- OIDC provider association documented as a post-create operator step (enables IRSA for future add-on changes)
- `docs/architecture/iam-security-model.md` — add note that `AmazonEKS_CNI_Policy` on node role is an interim; will migrate to VPC CNI IRSA role after cluster OIDC provider is available
- `docs/README.md` — add cluster bootstrap runbook stub

## Capabilities

### New Capabilities

_(none — cluster creation implements an existing spec requirement)_

### Modified Capabilities

- `eks-cluster`: the ClusterConfig requirement moves from specified to implemented; update spec to reflect concrete cluster name (`thor`), Kubernetes version (`1.35`), region (`us-east-1`), VPC (`berry-vpc`), node instance types, and OIDC post-create step

## Impact

- New `clusters/` directory
- Creates an EKS cluster in `us-east-1` — this is a live AWS resource, not just CFN
- Cluster creation takes ~15 minutes and cannot be done via change set; it is a one-time operator action using `eksctl`
- IAM OIDC provider registration is a required post-create step before any IRSA role can be used

## Non-goals

- IRSA roles for add-ons — separate change, requires the OIDC provider to exist first
- ArgoCD installation — cluster add-ons change
- Prod cluster (`prod` environment) — deferred until dev is validated
- GitOps bootstrapping — separate change

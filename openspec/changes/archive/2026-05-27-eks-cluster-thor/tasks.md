## 1. ClusterConfig Template

- [x] 1.1 Create `clusters/` directory
- [x] 1.2 Author `clusters/thor.yaml.tpl`: eksctl ClusterConfig template for cluster `thor`, Kubernetes 1.35, region `us-east-1`; placeholders `${VPC_ID}`, `${PRIVATE_SUBNET_A}`, `${PRIVATE_SUBNET_B}`, `${INTRA_SUBNET_A}`, `${INTRA_SUBNET_B}`, `${NODE_SG_ID}`, `${CONTROL_PLANE_SG_ID}`, `${NODE_ROLE_ARN}`; public+private API endpoint; CloudWatch logging for all 5 control-plane log types; two managed node groups (`system` m6i.large tainted CriticalAddonsOnly=true:NoSchedule, `application` m6i.xlarge), both using private subnets; control-plane ENIs in intra subnets

## 2. Makefile Targets

- [x] 2.1 Add `resolve-cluster-thor` target: fetch `vpc-dev` and `iam-node-role-dev` CFN exports via `aws cloudformation describe-stacks`; validate all required exports are non-empty (fail fast if any missing); export as env vars; run `envsubst < clusters/thor.yaml.tpl > /tmp/thor-resolved.yaml`
- [x] 2.2 Add `dry-run-cluster-thor` target: depends on `resolve-cluster-thor`; runs `eksctl create cluster --dry-run -f /tmp/thor-resolved.yaml`
- [x] 2.3 Add `create-cluster-thor` target: depends on `resolve-cluster-thor`; runs `eksctl create cluster -f /tmp/thor-resolved.yaml`
- [x] 2.4 Add `post-create-thor` target: runs `eksctl utils associate-iam-oidc-provider --cluster thor --region us-east-1 --approve`; fetches OIDC issuer URL and stores it in Parameter Store at `/eks/thor/oidc-issuer-url`

## 3. Validation and Cluster Creation

> Prerequisites: `vpc-dev` stack deployed, `iam-node-role-dev` stack deployed.

- [x] 3.1 Run `make dry-run-cluster-thor` — confirm eksctl reports zero validation errors with resolved values
- [x] 3.2 Run `make create-cluster-thor` — create the `thor` cluster (~15 minutes); verify all nodes are Ready with `kubectl get nodes`
- [x] 3.3 Run `make post-create-thor` — associate OIDC provider; verify issuer URL stored at `/eks/thor/oidc-issuer-url` in Parameter Store

## 4. Documentation

- [x] 4.1 Author `docs/runbooks/cluster-bootstrap.md`: ordered steps — prerequisites (vpc-dev deployed, iam-node-role-dev deployed), dry-run, create cluster, verify nodes, post-create OIDC, next steps (add-ons)
- [x] 4.2 Update `docs/README.md`: replace the cluster-bootstrap.md stub with a live link

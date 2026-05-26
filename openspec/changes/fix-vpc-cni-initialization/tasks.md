## 1. Update ClusterConfig for OIDC

- [x] 1.1 Update `clusters/thor.yaml.tpl`: add `iam.withOIDC: true` to metadata section so eksctl creates OIDC provider during cluster creation

## 2. Create VPC CNI IRSA Role

- [x] 2.1 Create `iam/vpc-cni-role.yaml`: IAM role for VPC CNI with trust policy for `system:serviceaccount:kube-system:aws-node`, ManagedPolicyArn `arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy`, parameter `OIDCIssuerHost` (OIDC issuer URL without https:// prefix), parameter `ClusterName`, parameter `Environment`
- [x] 2.2 Create `iam/parameters/vpc-cni-role-dev.json`: parameters file with `ClusterName=thor`, `Environment=dev`, placeholder for `OIDCIssuerHost` (to be resolved by Makefile)

## 3. Update Node Role

- [x] 3.1 Update `iam/node-role.yaml`: **KEEP** `arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy` in ManagedPolicyArns list during cluster creation (node role provides CNI permissions until IRSA is configured; removal is optional and happens in Task 8)

## 4. Makefile Targets for VPC CNI Setup

- [x] 4.1 Add `deploy-vpc-cni-role-dev` target: fetch OIDC issuer URL from Parameter Store at `/eks/thor/oidc-issuer-url`, strip `https://` prefix to get host, create CFN change set for `iam-vpc-cni-role-dev` stack with `OIDCIssuerHost` parameter, template file `iam/vpc-cni-role.yaml`, other parameters from `iam/parameters/vpc-cni-role-dev.json`
- [x] 4.2 Add `install-vpc-cni-addon-thor` target: fetch VPC CNI role ARN from `iam-vpc-cni-role-dev` stack outputs, run `eksctl create addon --cluster thor --region us-east-1 --name vpc-cni --version <LATEST_1_19> --service-account-role-arn <ARN> --force`; check EKS add-on compatibility docs for latest VPC CNI version compatible with Kubernetes 1.35
- [x] 4.3 Update `post-create-thor` target: after OIDC association and Parameter Store write, call `deploy-vpc-cni-role-dev` (requires manual change set execution), then prompt operator to execute change set, then call `install-vpc-cni-addon-thor`

## 5. Documentation

- [x] 5.1 Update `docs/runbooks/cluster-bootstrap.md`: revise "Post-Create Steps" section to include VPC CNI IRSA role deployment and add-on installation; add "Troubleshooting" section with steps for `NetworkPluginNotReady` errors (check `aws-node` DaemonSet, check IRSA role trust policy, check VPC CNI logs)
- [x] 5.2 Update Makefile help text: add descriptions for `deploy-vpc-cni-role-dev` and `install-vpc-cni-addon-thor` targets

## 6. Validation (Existing Cluster Fix)

> Prerequisites: `thor` cluster exists but has CNI error; `vpc-dev` and `iam-node-role-dev` deployed

- [ ] 6.1 Verify cluster OIDC provider: run `eksctl utils associate-iam-oidc-provider --cluster thor --region us-east-1 --approve` (idempotent)
- [ ] 6.2 Fetch and store OIDC issuer URL: run updated `post-create-thor` target (OIDC association already done, focuses on Parameter Store write)
- [ ] 6.3 Deploy VPC CNI IRSA role: run `make deploy-vpc-cni-role-dev`, execute change set in CloudFormation console
- [ ] 6.4 Install VPC CNI add-on: run `make install-vpc-cni-addon-thor`
- [ ] 6.5 Verify `aws-node` DaemonSet is running: `kubectl get daemonset -n kube-system aws-node` — all pods should be Ready within 2-3 minutes
- [ ] 6.6 Verify nodes report NetworkReady: `kubectl get nodes` — all nodes should be `Ready` status
- [ ] 6.7 Test pod scheduling: create a test pod (`kubectl run test-nginx --image=nginx`), verify it reaches `Running` state

## 7. Validation (New Cluster Creation)

> Prerequisites: No cluster exists; `vpc-dev` and `iam-node-role-dev` deployed

- [ ] 7.1 Run `make create-cluster-thor` with updated ClusterConfig (includes `iam.withOIDC: true`)
- [ ] 7.2 Run `make post-create-thor` — verify OIDC issuer stored, VPC CNI role deployed, add-on installed
- [ ] 7.3 Verify nodes are Ready and pods can schedule (same checks as 6.6 and 6.7)

## 8. Node Role Cleanup (Optional)

> Only after VPC CNI add-on is confirmed working with IRSA

- [ ] 8.1 Update `iam-node-role-dev` stack: run `aws cloudformation deploy` with updated `iam/node-role.yaml` (no `AmazonEKS_CNI_Policy`)
- [ ] 8.2 Verify VPC CNI still functions after node role policy removal: check `aws-node` pods remain Running, test new pod creation

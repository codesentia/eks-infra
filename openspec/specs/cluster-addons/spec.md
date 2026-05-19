## ADDED Requirements

### Requirement: Add-on Helm values checked into repository
Each shared add-on SHALL have a `values.yaml` (and optionally `values-<env>.yaml`) under `addons/<addon-name>/`. Chart versions SHALL be pinned.

#### Scenario: Add-on values file contains pinned chart version
- **WHEN** `addons/<addon-name>/values.yaml` is read
- **THEN** a `chartVersion` field or comment specifies the exact chart version in use

#### Scenario: Environment override file overrides base values
- **WHEN** both `values.yaml` and `values-prod.yaml` exist for an add-on
- **THEN** the prod deployment uses the merged result of both files

---

### Requirement: AWS Load Balancer Controller deployed on system nodes
The AWS Load Balancer Controller SHALL be deployed in the `kube-system` namespace on `system` node group nodes, using its IRSA role.

#### Scenario: ALB controller pods are running
- **WHEN** `kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller` is run
- **THEN** at least 2 pods are in `Running` state

#### Scenario: ALB controller uses IRSA service account
- **WHEN** the `aws-load-balancer-controller` service account annotations are inspected
- **THEN** `eks.amazonaws.com/role-arn` points to the `eks-<cluster>-alb-controller-role` ARN

---

### Requirement: Cluster Autoscaler deployed and bound to node groups
The Cluster Autoscaler SHALL be deployed in `kube-system` on system nodes, configured to manage only the node groups tagged with `k8s.io/cluster-autoscaler/<cluster-name>=owned`.

#### Scenario: Autoscaler scales up on pending pods
- **WHEN** pending pods exist that cannot be scheduled due to insufficient resources
- **THEN** the autoscaler increases the desired count of the application node group within 2 minutes

#### Scenario: Autoscaler does not scale below minimum
- **WHEN** the application node group is at its minimum node count
- **THEN** the autoscaler does not attempt to scale in further

---

### Requirement: external-dns manages Cloudflare DNS records
external-dns SHALL be deployed in `kube-system` using the Cloudflare provider. It SHALL reconcile DNS records for `Ingress` and `Service` resources that carry the `external-dns.alpha.kubernetes.io/hostname` annotation. It SHALL read the Cloudflare API token from a Kubernetes `Secret` named `cloudflare-api-token` in `kube-system`.

#### Scenario: DNS record created for annotated Ingress
- **WHEN** an `Ingress` resource with the hostname annotation is applied
- **THEN** a corresponding `A` record (or CNAME) appears in Cloudflare DNS within 2 minutes

#### Scenario: external-dns does not touch records it did not create
- **WHEN** a Cloudflare DNS record exists without the external-dns ownership TXT record
- **THEN** external-dns does not modify or delete it

#### Scenario: external-dns fails closed if token Secret is absent
- **WHEN** the `cloudflare-api-token` Secret does not exist
- **THEN** external-dns pods fail to start and emit a clear error (no silent no-op)

---

### Requirement: cert-manager issues certificates via Cloudflare DNS-01
cert-manager SHALL be deployed in the `cert-manager` namespace on system nodes. A `ClusterIssuer` SHALL be configured for ACME DNS-01 challenge using the Cloudflare provider, reading the API token from a `Secret` named `cloudflare-api-token` in `cert-manager`.

#### Scenario: Certificate resource moves to Ready state
- **WHEN** a `Certificate` resource referencing the `ClusterIssuer` is created
- **THEN** it reaches `Ready: True` within 5 minutes

#### Scenario: cert-manager fails closed if token Secret is absent
- **WHEN** the `cloudflare-api-token` Secret does not exist in `cert-manager`
- **THEN** `CertificateRequest` resources remain in a `Pending` state with a descriptive error event

---

### Requirement: ArgoCD deployed with App of Apps pattern
ArgoCD SHALL be deployed in the `argocd` namespace on system nodes via Helm. After bootstrap, a root `Application` manifest (`apps/root.yaml`) SHALL be applied once manually; this `Application` SHALL manage child `Application` manifests for `addons/` and `namespaces/`. The `namespaces/` Application SHALL have automated sync enabled; the `addons/` Application SHALL require manual sync.

#### Scenario: ArgoCD self-heals a manually deleted namespace manifest
- **WHEN** a namespace manifest is deleted from the cluster out-of-band
- **THEN** ArgoCD re-applies it within one sync interval (automated sync)

#### Scenario: addons Application does not auto-sync
- **WHEN** a change is pushed to `addons/` in git
- **THEN** ArgoCD marks the addons Application as `OutOfSync` but does NOT apply the change automatically

#### Scenario: Only platform team can sync the addons Application
- **WHEN** a non-platform-team user attempts to trigger a sync on the addons Application
- **THEN** ArgoCD rejects the request with a permission denied error

---

### Requirement: Observability stack — CloudWatch Container Insights
The CloudWatch Container Insights agent (Fluent Bit DaemonSet + CloudWatch agent) SHALL be deployed cluster-wide to ship node and pod metrics and logs to CloudWatch.

#### Scenario: Container logs appear in CloudWatch
- **WHEN** a pod writes to stdout
- **THEN** log events appear in the CloudWatch log group `/aws/containerinsights/<cluster>/application` within 5 minutes

---

### Requirement: Observability stack — kube-prometheus-stack
`kube-prometheus-stack` SHALL be deployed in the `monitoring` namespace on system nodes, with Grafana exposed via an internal ALB Ingress.

#### Scenario: Prometheus scrapes node and pod metrics
- **WHEN** `kubectl get --raw /metrics` succeeds on a node
- **THEN** the same metric series are queryable in Prometheus within 1 scrape interval

#### Scenario: Grafana is accessible inside the VPC
- **WHEN** the Grafana Ingress ALB DNS name is queried from within the VPC
- **THEN** the Grafana login page loads

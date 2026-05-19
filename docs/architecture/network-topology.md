# Network Topology

## VPC Layout

Each environment has a dedicated VPC with three subnet tiers across all Availability Zones. Dev spans 2 AZs; prod spans 3.

```mermaid
graph TB
    IGW["Internet Gateway"]

    subgraph VPC["VPC — dev: 10.10.0.0/16 | prod: 10.20.0.0/16"]

        subgraph AZ_A["Availability Zone A"]
            PUB_A["Public Subnet\ndev: 10.10.0.0/20\nprod: 10.20.0.0/20\n\nNAT Gateway A\nALB nodes"]
            PRIV_A["Private Subnet\ndev: 10.10.16.0/20\nprod: 10.20.16.0/20\n\nWorker nodes"]
            INTRA_A["Intra Subnet\ndev: 10.10.32.0/20\nprod: 10.20.32.0/20\n\nControl plane ENIs only\n(no internet route)"]
        end

        subgraph AZ_B["Availability Zone B"]
            PUB_B["Public Subnet\ndev: 10.10.48.0/20\nprod: 10.20.48.0/20\n\nNAT Gateway B\nALB nodes"]
            PRIV_B["Private Subnet\ndev: 10.10.64.0/20\nprod: 10.20.64.0/20\n\nWorker nodes"]
            INTRA_B["Intra Subnet\ndev: 10.10.80.0/20\nprod: 10.20.80.0/20\n\nControl plane ENIs only"]
        end

        subgraph AZ_C["Availability Zone C — prod only"]
            PUB_C["Public Subnet\nprod: 10.20.96.0/20\n\nNAT Gateway C\nALB nodes"]
            PRIV_C["Private Subnet\nprod: 10.20.112.0/20\n\nWorker nodes"]
            INTRA_C["Intra Subnet\nprod: 10.20.128.0/20\n\nControl plane ENIs only"]
        end

        subgraph ENDPOINTS["VPC Endpoints (intra/private subnets)"]
            EP_S3["Gateway Endpoint\ncom.amazonaws.*.s3"]
            EP_ECR["Interface Endpoints\necr.api / ecr.dkr"]
            EP_SM["Interface Endpoint\nsecretsmanager"]
            EP_SSM["Interface Endpoints\nssm / ssmmessages"]
        end
    end

    IGW --> PUB_A
    IGW --> PUB_B
    IGW --> PUB_C

    PUB_A -- "default route\n0.0.0.0/0" --> IGW
    PUB_B -- "default route\n0.0.0.0/0" --> IGW
    PUB_C -- "default route\n0.0.0.0/0" --> IGW

    PRIV_A -- "default route\n0.0.0.0/0" --> PUB_A
    PRIV_B -- "default route\n0.0.0.0/0" --> PUB_B
    PRIV_C -- "default route\n0.0.0.0/0" --> PUB_C

    PRIV_A --> ENDPOINTS
    PRIV_B --> ENDPOINTS
    PRIV_C --> ENDPOINTS
    INTRA_A --> ENDPOINTS
    INTRA_B --> ENDPOINTS
    INTRA_C --> ENDPOINTS
```

### Key routing rules

| Subnet tier | Default route | Purpose |
|-------------|---------------|---------|
| `public` | Internet Gateway | ALBs need direct internet; NAT GW EIPs live here |
| `private` | NAT Gateway (same AZ) | Worker nodes can pull from internet/ECR; no inbound |
| `intra` | None (local only) | Control plane ENIs; no internet reachability |

### Reserved ranges

| CIDR | Status |
|------|--------|
| `10.x.144.0/20` and above | Reserved — future use (peering, expansion, additional node groups) |

---

## Cluster Traffic Flows

```mermaid
flowchart TB
    subgraph INTERNET["Internet"]
        USER["End User"]
        CF["Cloudflare DNS"]
        LE["Let's Encrypt ACME"]
    end

    subgraph AWS["AWS — VPC"]
        subgraph PUBLIC["Public Subnets"]
            ALB["Application Load Balancer\n(created by ALB Controller)"]
        end

        subgraph PRIVATE["Private Subnets — Worker Nodes"]
            INGRESS_POD["Ingress Controller\n(or direct ALB target group)"]
            APP_POD["Application Pod\n(team namespace)"]
            ADDON_POD["Add-on Pod\n(kube-system / monitoring)"]
        end

        subgraph INTRA["Intra Subnets"]
            CP_ENI["EKS Control Plane ENIs\n(managed by AWS)"]
        end

        ECR["ECR\n(VPC endpoint)"]
        SM["Secrets Manager\n(VPC endpoint)"]
        CW["CloudWatch\n(VPC endpoint via SSM)"]
        NATGW["NAT Gateway\n(per AZ)"]
    end

    %% Ingress path
    USER -- "HTTPS DNS lookup" --> CF
    CF -- "A record → ALB DNS" --> USER
    USER -- "HTTPS request" --> ALB
    ALB -- "target group" --> APP_POD

    %% Certificate issuance
    ADDON_POD -- "cert-manager DNS-01\nCF API token" --> CF
    LE -- "ACME DNS validation" --> CF

    %% Intra-cluster
    APP_POD -- "service call\n(same namespace)" --> APP_POD
    CP_ENI -- "kubelet / webhook" --> PRIVATE

    %% Egress paths
    APP_POD -- "AWS SDK calls\n(IRSA credentials)" --> SM
    ADDON_POD -- "image pull" --> ECR
    ADDON_POD -- "metrics / logs" --> CW
    APP_POD -- "other internet egress" --> NATGW
    NATGW --> INTERNET
```

---

## Multi-Team Namespace Isolation

```mermaid
flowchart TB
    subgraph CLUSTER["EKS Cluster"]
        subgraph SYS["kube-system / add-on namespaces\n(system node group)"]
            ALB_CTL["aws-load-balancer-controller"]
            EXTDNS["external-dns"]
            CERTMGR["cert-manager"]
            ARGO["argocd"]
            PROM["prometheus / grafana"]
        end

        subgraph TEAM_A["Namespace: team-a\n(application node group)"]
            POD_A1["pod-a1"]
            POD_A2["pod-a2"]
            SVC_A["Service A"]
        end

        subgraph TEAM_B["Namespace: team-b\n(application node group)"]
            POD_B1["pod-b1"]
            SVC_B["Service B"]
        end

        NP_A["NetworkPolicy: team-a\n• default deny all ingress/egress\n• allow intra-namespace\n• allow from ingress-controller"]
        NP_B["NetworkPolicy: team-b\n• default deny all ingress/egress\n• allow intra-namespace\n• allow from ingress-controller"]
    end

    ALB_CTL -- "routes external traffic" --> SVC_A
    ALB_CTL -- "routes external traffic" --> SVC_B

    POD_A1 <-- "✓ allowed\n(intra-namespace)" --> POD_A2
    POD_A1 -. "✗ blocked\n(cross-namespace)" .-> POD_B1
    POD_B1 -. "✗ blocked\n(cross-namespace)" .-> POD_A1

    NP_A -. "enforces" .-> TEAM_A
    NP_B -. "enforces" .-> TEAM_B
```

### What each team namespace contains

| Resource | Default value | Configurable? |
|----------|--------------|---------------|
| `ResourceQuota` | CPU: 4 cores req / 8 cores limit; Mem: 8Gi req / 16Gi limit | Yes — per team tier |
| `LimitRange` | Container default: 100m CPU req, 500m limit; 128Mi mem req, 512Mi limit | Yes |
| `NetworkPolicy` | Default deny all + intra-namespace allow + ingress-controller allow | Add-only |
| `RoleBinding` (admin) | Group → `admin` ClusterRole in namespace | Yes |
| `RoleBinding` (developer) | Group → custom `developer` Role | Yes |

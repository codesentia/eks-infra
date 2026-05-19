# ADR-006: Cloudflare for DNS and Certificate Issuance

**Status:** Accepted  
**Date:** 2026-05-19

## Context

The platform needs two DNS-related capabilities:

1. **Automatic DNS record management** — when a team creates a Kubernetes `Ingress` or `Service` with a hostname annotation, a DNS record should be created automatically in the authoritative zone. This is handled by [external-dns](https://github.com/kubernetes-sigs/external-dns).
2. **Automatic TLS certificate issuance** — cert-manager should be able to issue Let's Encrypt certificates via DNS-01 ACME challenge (required for wildcard certs and for clusters whose API endpoint is not publicly accessible).

Both capabilities require programmatic access to the DNS zone. The organisation's DNS zones are hosted on **Cloudflare**. A decision is needed on whether to keep DNS on Cloudflare or delegate to Route 53 for the cluster subdomain.

## Decision

DNS remains on Cloudflare. Both external-dns and cert-manager use their native Cloudflare providers. No Route 53 hosted zone is created. No external-dns IRSA role is needed.

### Credential model

A Cloudflare API token is created with the following scope:
- **Permissions:** `Zone → DNS → Edit`
- **Zone resources:** The specific zone(s) used by the cluster (not account-wide)
- **No other permissions**

The token is stored in AWS Secrets Manager at `/eks/<env>/cloudflare-api-token`. During cluster bootstrap, it is injected into the cluster as a Kubernetes `Secret` in two namespaces:

| Namespace | Secret name | Consumer |
|-----------|-------------|----------|
| `kube-system` | `cloudflare-api-token` | external-dns |
| `cert-manager` | `cloudflare-api-token` | cert-manager ClusterIssuer |

The token is never stored in the git repository.

### external-dns configuration (summary)

```yaml
provider: cloudflare
env:
  - name: CF_API_TOKEN
    valueFrom:
      secretKeyRef:
        name: cloudflare-api-token
        key: token
domainFilters:
  - <your-zone>
txtOwnerId: eks-<cluster-name>
```

### cert-manager ClusterIssuer (summary)

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ops@<your-domain>
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: token
```

## Rationale

### Why not delegate a subdomain to Route 53?

NS delegation (creating a `k8s.<your-domain>` subdomain in Cloudflare pointing to Route 53 name servers) would enable IRSA-native authentication for external-dns and cert-manager. However:

- It introduces a second DNS system that must be maintained (Route 53 hosted zone, zone delegation records, IRSA role, policy).
- Both external-dns and cert-manager have mature, well-tested Cloudflare providers — there is no functional advantage to Route 53.
- The API token credential model is simpler operationally than an IRSA role chained through two AWS services.
- Cloudflare's API is faster than Route 53 for DNS propagation — Let's Encrypt ACME DNS-01 validation is quicker.

### Why a scoped API token instead of a global API key?

Cloudflare offers two credential types: a global API key (account-wide access) and scoped API tokens. The global API key violates the least-privilege principle — if it leaked, an attacker could modify any DNS record in the account.

A scoped token limits the blast radius to DNS records in the specific zone(s) used by the cluster. Cloudflare's token permission model supports exact zone and permission scoping.

### Why store in Secrets Manager rather than injecting directly?

Storing the token in Secrets Manager provides:
- A single source of truth for the credential, independent of the cluster.
- Audit trail (CloudTrail records every `GetSecretValue` call).
- The ability to rotate the token without modifying the git repository.
- A well-understood access control model (IAM policy on the secret).

The cluster bootstrap script reads from Secrets Manager and creates the Kubernetes Secret imperatively. This is the only imperative step in an otherwise declarative deployment.

## Token Rotation Procedure

See `docs/runbooks/cloudflare-token-rotation.md` for the full procedure. Summary:

1. Create a new Cloudflare API token with the same zone-scoped DNS Edit permission.
2. Update the secret in Secrets Manager: `aws secretsmanager put-secret-value ...`
3. Re-run the bootstrap injection command to update the Kubernetes Secrets in both namespaces.
4. Verify external-dns and cert-manager are functioning (check logs, attempt a cert renewal).
5. Revoke the old Cloudflare API token.

## Alternatives Considered

### Route 53 with NS delegation from Cloudflare

Create a `k8s.<zone>` subdomain in Cloudflare, delegate to Route 53, use IRSA for external-dns and cert-manager.

**Rejected because:**
- Adds Route 53 as a second DNS dependency with associated cost and operational overhead.
- IRSA provides no meaningful security advantage over a scoped Cloudflare token for this use case.
- Two DNS systems to debug when DNS resolution fails.

### Cloudflare Global API Key

Use the global API key instead of a scoped token.

**Rejected because:**
- Account-wide permissions violate least-privilege; a leak could affect all DNS records.
- Cloudflare scoped API tokens have been GA since 2019 — there is no reason to use the global key.

## Consequences

- The external-dns Route 53 IRSA role (and its CFN stack) is not needed — reducing IAM complexity.
- The Cloudflare API token is the single credential that external-dns and cert-manager depend on. Token rotation requires updating two Kubernetes Secrets (one per namespace).
- cert-manager uses Let's Encrypt (ACME) rather than ACM. Certificates are stored in Kubernetes Secrets and presented directly by the ALB or ingress controller. ACM is not used.
- The cluster bootstrap sequence has one imperative step that cannot be automated via GitOps: the initial injection of the Cloudflare token as a Kubernetes Secret.

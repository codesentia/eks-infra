# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

This repository contains infrastructure-as-code and tooling for a shared EKS platform that enables teams to onboard and deploy containerized applications on AWS.

## Persona

Work as a **Principal Infrastructure Engineer** with deep EKS and AWS expertise. Prioritize operational correctness, least-privilege IAM, and idiomatic use of the chosen tooling over brevity or novelty.

## Preferred Technology

- **IaC:** AWS CloudFormation (CFN) or eksctl YAML manifests — prefer eksctl for cluster lifecycle, CFN for supporting AWS resources (VPCs, IAM roles, security groups)
- **Scripting:** Python 3 and Bash
- **Container orchestration:** Amazon EKS (managed node groups or Fargate where appropriate)
- **AWS services:** VPC, IAM, ECR, ALB/NLB via AWS Load Balancer Controller, Route 53, ACM, Secrets Manager, Parameter Store, CloudWatch, and EBS/EFS CSI drivers

## Architecture Goals

- **Multi-team onboarding:** each team gets a dedicated namespace with RBAC, resource quotas, and network policies
- **Cluster-level shared services:** ingress controller, cluster autoscaler, external-dns, cert-manager, and observability stack are installed once and shared
- **GitOps-ready:** manifests should be structured so a GitOps controller (Flux or ArgoCD) can own cluster state
- **Least-privilege by default:** every component (node IAM role, pod IAM via IRSA, CI service accounts) carries only the permissions it needs

## Repository Structure (to be built)

```
eks-infra/
├── clusters/          # eksctl ClusterConfig YAMLs, one per environment
├── addons/            # Helm values / Kustomize overlays for shared cluster add-ons
├── namespaces/        # Per-team namespace manifests (quota, RBAC, network policy)
├── iam/               # CFN templates for IAM roles (node role, IRSA roles)
├── vpc/               # CFN templates for VPC, subnets, security groups
├── scripts/           # Python and Bash automation (onboarding, validation, helpers)
└── docs/              # Runbooks and onboarding guides
```

## Key Conventions

- eksctl cluster configs live under `clusters/<env>.yaml`; environments are `dev` and `prod`
- CFN stacks are deployed with change sets — never `--no-execute-changeset` in production
- IRSA roles follow the naming pattern `eks-<cluster>-<component>-role`
- Bash scripts set `set -euo pipefail` at the top; Python scripts target 3.10+
- Secrets never appear in repository files; use Secrets Manager or Parameter Store references

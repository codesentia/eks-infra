# ArgoCD Helm values template for EKS with IRSA
# Placeholder ${ARGOCD_ROLE_ARN} will be substituted by Makefile

global:
  domain: argocd.local

configs:
  params:
    server.insecure: true

server:
  serviceAccount:
    create: true
    name: argocd-server
    annotations:
      eks.amazonaws.com/role-arn: "${ARGOCD_ROLE_ARN}"

  extraArgs:
    - --insecure

  ingress:
    enabled: false

  service:
    type: ClusterIP

controller:
  serviceAccount:
    create: true
    name: argocd-application-controller
    annotations:
      eks.amazonaws.com/role-arn: "${ARGOCD_ROLE_ARN}"

repoServer:
  serviceAccount:
    create: true
    name: argocd-repo-server
    annotations:
      eks.amazonaws.com/role-arn: "${ARGOCD_ROLE_ARN}"

applicationSet:
  enabled: true

notifications:
  enabled: false

dex:
  enabled: false

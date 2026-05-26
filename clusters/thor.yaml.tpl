apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: thor
  region: us-east-1
  version: "1.35"
  tags:
    Environment: dev
    ManagedBy: eksctl

iam:
  withOIDC: true

vpc:
  id: "${VPC_ID}"
  subnets:
    private:
      us-east-1a:
        id: "${PRIVATE_SUBNET_A}"
      us-east-1b:
        id: "${PRIVATE_SUBNET_B}"
    public:
      us-east-1a:
        id: "${PUBLIC_SUBNET_A}"
      us-east-1b:
        id: "${PUBLIC_SUBNET_B}"

  controlPlaneSubnetIDs:
    - "${INTRA_SUBNET_A}"
    - "${INTRA_SUBNET_B}"

  securityGroup: "${CONTROL_PLANE_SG_ID}"

kubernetesNetworkConfig:
  ipFamily: IPv4

cloudWatch:
  clusterLogging:
    enableTypes:
      - api
      - audit
      - authenticator
      - controllerManager
      - scheduler

managedNodeGroups:
  - name: system
    instanceType: m7i-flex.large
    minSize: 1
    desiredCapacity: 1
    maxSize: 3
    privateNetworking: true
    subnets:
      - "${PRIVATE_SUBNET_A}"
      - "${PRIVATE_SUBNET_B}"
    securityGroups:
      attachIDs:
        - "${NODE_SG_ID}"
    iam:
      instanceRoleARN: "${NODE_ROLE_ARN}"
    taints:
      - key: CriticalAddonsOnly
        value: "true"
        effect: NoSchedule
    labels:
      role: system
    tags:
      Environment: dev
      NodeGroup: system

  - name: application
    instanceType: m7i-flex.large
    minSize: 1
    desiredCapacity: 1
    maxSize: 3
    privateNetworking: true
    subnets:
      - "${PRIVATE_SUBNET_A}"
      - "${PRIVATE_SUBNET_B}"
    securityGroups:
      attachIDs:
        - "${NODE_SG_ID}"
    iam:
      instanceRoleARN: "${NODE_ROLE_ARN}"
    labels:
      role: application
    tags:
      Environment: dev
      NodeGroup: application

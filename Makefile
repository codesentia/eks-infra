VENV        := .venv
PYTHON      := $(VENV)/bin/python
PIP         := $(VENV)/bin/pip
PIP_COMPILE := $(VENV)/bin/pip-compile
CFN_LINT    := $(VENV)/bin/cfn-lint
AWS         := aws

.DEFAULT_GOAL := help

# ── Bootstrap ────────────────────────────────────────────────────────────────

.PHONY: bootstrap
bootstrap: $(VENV)/bin/cfn-lint  ## Create .venv and install all pinned dependencies

$(VENV)/bin/cfn-lint: requirements.txt
	python3 -m venv $(VENV)
	$(PIP) install --quiet --upgrade pip
	$(PIP) install --quiet -r requirements.txt
	@touch $(VENV)/bin/cfn-lint

.PHONY: deps-update
deps-update: $(VENV)/bin/pip-compile  ## Re-compile requirements.txt from requirements.in
	$(PIP_COMPILE) requirements.in

$(VENV)/bin/pip-compile: requirements.txt
	$(PIP) install --quiet pip-tools

# ── Linting ──────────────────────────────────────────────────────────────────

.PHONY: lint-vpc
lint-vpc: bootstrap  ## Lint vpc/vpc.yaml with cfn-lint
	$(CFN_LINT) vpc/vpc.yaml

.PHONY: lint-all
lint-all: bootstrap  ## Lint all CFN templates under vpc/ and iam/ (bootstrap/ excluded)
	find $(wildcard vpc/ iam/) -name "*.yaml" -print0 | xargs -0 $(CFN_LINT)

.PHONY: lint
lint: lint-vpc  ## Run all linting checks

.PHONY: ci
ci: bootstrap lint-all  ## Full CI sequence: bootstrap then lint all templates

# ── VPC Deployment ───────────────────────────────────────────────────────────

.PHONY: deploy-vpc-dev
deploy-vpc-dev:  ## [change-set required] Create vpc-dev change set (review before executing)
	$(AWS) cloudformation deploy \
		--no-execute-changeset \
		--stack-name vpc-dev \
		--template-file vpc/vpc.yaml \
		--parameter-overrides file://vpc/parameters/dev.json \
		--capabilities CAPABILITY_NAMED_IAM

.PHONY: deploy-node-role-dev
deploy-node-role-dev:  ## [change-set required] Create iam-node-role-dev change set (review before executing)
	$(AWS) cloudformation deploy \
		--no-execute-changeset \
		--stack-name iam-node-role-dev \
		--template-file iam/node-role.yaml \
		--parameter-overrides file://iam/parameters/node-role-dev.json \
		--capabilities CAPABILITY_NAMED_IAM

.PHONY: deploy-vpc-cni-role-dev
deploy-vpc-cni-role-dev:  ## [change-set required] Create iam-vpc-cni-role-dev change set (review before executing)
	@echo "Fetching OIDC issuer URL from Parameter Store..."
	$(eval OIDC_ISSUER_URL := $(shell $(AWS) ssm get-parameter --name /eks/thor/oidc-issuer-url --query "Parameter.Value" --output text 2>/dev/null))
	@test -n "$(OIDC_ISSUER_URL)" || (echo "ERROR: OIDC issuer URL not found at /eks/thor/oidc-issuer-url — run post-create-thor first" && exit 1)
	$(eval OIDC_ISSUER_HOST := $(shell echo "$(OIDC_ISSUER_URL)" | sed 's|https://||'))
	@echo "OIDC issuer host: $(OIDC_ISSUER_HOST)"
	$(eval STACK_EXISTS := $(shell $(AWS) cloudformation describe-stacks --stack-name iam-vpc-cni-role-dev --query "Stacks[0].StackName" --output text 2>/dev/null || echo ""))
	$(eval CHANGE_SET_TYPE := $(if $(STACK_EXISTS),UPDATE,CREATE))
	@echo "Creating $(CHANGE_SET_TYPE) change set for iam-vpc-cni-role-dev..."
	$(AWS) cloudformation create-change-set \
		--stack-name iam-vpc-cni-role-dev \
		--change-set-name iam-vpc-cni-role-dev-$$(date +%Y%m%d-%H%M%S) \
		--template-body file://iam/vpc-cni-role.yaml \
		--parameters ParameterKey=ClusterName,ParameterValue=thor ParameterKey=Environment,ParameterValue=dev ParameterKey=OIDCIssuerHost,ParameterValue=$(OIDC_ISSUER_HOST) \
		--capabilities CAPABILITY_NAMED_IAM \
		--change-set-type $(CHANGE_SET_TYPE)
	@echo "Change set created. Execute it in the CloudFormation Console."

.PHONY: deploy-vpc-prod
deploy-vpc-prod:  ## [change-set required] Create vpc-prod change set (review before executing)
	$(AWS) cloudformation deploy \
		--no-execute-changeset \
		--stack-name vpc-prod \
		--template-file vpc/vpc.yaml \
		--parameter-overrides file://vpc/parameters/prod.json \
		--capabilities CAPABILITY_NAMED_IAM

# ── EKS Cluster: thor ────────────────────────────────────────────────────────

EKSCTL := eksctl
THOR_RESOLVED := /tmp/thor-resolved.yaml

.PHONY: resolve-cluster-thor
resolve-cluster-thor:  ## Resolve vpc-dev and iam-node-role-dev CFN exports into /tmp/thor-resolved.yaml
	@echo "Resolving CFN exports for thor cluster..."
	$(eval VPC_ID             := $(shell $(AWS) cloudformation describe-stacks --stack-name vpc-dev --query "Stacks[0].Outputs[?OutputKey=='VpcId'].OutputValue" --output text 2>/dev/null))
	$(eval PRIVATE_SUBNET_A   := $(shell $(AWS) cloudformation describe-stacks --stack-name vpc-dev --query "Stacks[0].Outputs[?OutputKey=='PrivateSubnetA'].OutputValue" --output text 2>/dev/null))
	$(eval PRIVATE_SUBNET_B   := $(shell $(AWS) cloudformation describe-stacks --stack-name vpc-dev --query "Stacks[0].Outputs[?OutputKey=='PrivateSubnetB'].OutputValue" --output text 2>/dev/null))
	$(eval PUBLIC_SUBNET_A    := $(shell $(AWS) cloudformation describe-stacks --stack-name vpc-dev --query "Stacks[0].Outputs[?OutputKey=='PublicSubnetA'].OutputValue" --output text 2>/dev/null))
	$(eval PUBLIC_SUBNET_B    := $(shell $(AWS) cloudformation describe-stacks --stack-name vpc-dev --query "Stacks[0].Outputs[?OutputKey=='PublicSubnetB'].OutputValue" --output text 2>/dev/null))
	$(eval INTRA_SUBNET_A     := $(shell $(AWS) cloudformation describe-stacks --stack-name vpc-dev --query "Stacks[0].Outputs[?OutputKey=='IntraSubnetA'].OutputValue" --output text 2>/dev/null))
	$(eval INTRA_SUBNET_B     := $(shell $(AWS) cloudformation describe-stacks --stack-name vpc-dev --query "Stacks[0].Outputs[?OutputKey=='IntraSubnetB'].OutputValue" --output text 2>/dev/null))
	$(eval NODE_SG_ID         := $(shell $(AWS) cloudformation describe-stacks --stack-name vpc-dev --query "Stacks[0].Outputs[?OutputKey=='NodeSecurityGroupId'].OutputValue" --output text 2>/dev/null))
	$(eval CONTROL_PLANE_SG_ID := $(shell $(AWS) cloudformation describe-stacks --stack-name vpc-dev --query "Stacks[0].Outputs[?OutputKey=='ControlPlaneSecurityGroupId'].OutputValue" --output text 2>/dev/null))
	$(eval NODE_ROLE_ARN      := $(shell $(AWS) cloudformation describe-stacks --stack-name iam-node-role-dev --query "Stacks[0].Outputs[?OutputKey=='NodeRoleArn'].OutputValue" --output text 2>/dev/null))
	@test -n "$(VPC_ID)"              || (echo "ERROR: vpc-dev export 'vpc-dev-VpcId' not found — is vpc-dev deployed?" && exit 1)
	@test -n "$(PRIVATE_SUBNET_A)"   || (echo "ERROR: vpc-dev export 'vpc-dev-PrivateSubnetA' not found" && exit 1)
	@test -n "$(PRIVATE_SUBNET_B)"   || (echo "ERROR: vpc-dev export 'vpc-dev-PrivateSubnetB' not found" && exit 1)
	@test -n "$(PUBLIC_SUBNET_A)"    || (echo "ERROR: vpc-dev export 'vpc-dev-PublicSubnetA' not found" && exit 1)
	@test -n "$(PUBLIC_SUBNET_B)"    || (echo "ERROR: vpc-dev export 'vpc-dev-PublicSubnetB' not found" && exit 1)
	@test -n "$(INTRA_SUBNET_A)"     || (echo "ERROR: vpc-dev export 'vpc-dev-IntraSubnetA' not found" && exit 1)
	@test -n "$(INTRA_SUBNET_B)"     || (echo "ERROR: vpc-dev export 'vpc-dev-IntraSubnetB' not found" && exit 1)
	@test -n "$(NODE_SG_ID)"         || (echo "ERROR: vpc-dev export 'vpc-dev-NodeSecurityGroupId' not found" && exit 1)
	@test -n "$(CONTROL_PLANE_SG_ID)" || (echo "ERROR: vpc-dev export 'vpc-dev-ControlPlaneSecurityGroupId' not found" && exit 1)
	@test -n "$(NODE_ROLE_ARN)"      || (echo "ERROR: iam-node-role-dev export 'iam-node-role-dev-NodeRoleArn' not found — is iam-node-role-dev deployed?" && exit 1)
	VPC_ID="$(VPC_ID)" \
	PRIVATE_SUBNET_A="$(PRIVATE_SUBNET_A)" \
	PRIVATE_SUBNET_B="$(PRIVATE_SUBNET_B)" \
	PUBLIC_SUBNET_A="$(PUBLIC_SUBNET_A)" \
	PUBLIC_SUBNET_B="$(PUBLIC_SUBNET_B)" \
	INTRA_SUBNET_A="$(INTRA_SUBNET_A)" \
	INTRA_SUBNET_B="$(INTRA_SUBNET_B)" \
	NODE_SG_ID="$(NODE_SG_ID)" \
	CONTROL_PLANE_SG_ID="$(CONTROL_PLANE_SG_ID)" \
	NODE_ROLE_ARN="$(NODE_ROLE_ARN)" \
	envsubst < clusters/thor.yaml.tpl > $(THOR_RESOLVED)
	@echo "Rendered ClusterConfig written to $(THOR_RESOLVED)"

.PHONY: dry-run-cluster-thor
dry-run-cluster-thor: resolve-cluster-thor  ## Validate thor ClusterConfig against AWS (no resources created)
	$(EKSCTL) create cluster --dry-run -f $(THOR_RESOLVED)

.PHONY: create-cluster-thor
create-cluster-thor: resolve-cluster-thor  ## Create the thor EKS cluster (~15 min)
	$(EKSCTL) create cluster -f $(THOR_RESOLVED)

.PHONY: install-vpc-cni-addon-thor
install-vpc-cni-addon-thor:  ## Install VPC CNI add-on with IRSA role
	@echo "Fetching VPC CNI role ARN from iam-vpc-cni-role-dev stack..."
	$(eval VPC_CNI_ROLE_ARN := $(shell $(AWS) cloudformation describe-stacks --stack-name iam-vpc-cni-role-dev --query "Stacks[0].Outputs[?OutputKey=='VPCCNIRoleArn'].OutputValue" --output text 2>/dev/null))
	@test -n "$(VPC_CNI_ROLE_ARN)" || (echo "ERROR: iam-vpc-cni-role-dev stack not found or VPCCNIRoleArn output missing — run deploy-vpc-cni-role-dev first" && exit 1)
	@echo "Installing VPC CNI add-on with role: $(VPC_CNI_ROLE_ARN)"
	$(EKSCTL) create addon \
		--cluster thor \
		--region us-east-1 \
		--name vpc-cni \
		--version v1.19.0-eksbuild.1 \
		--service-account-role-arn $(VPC_CNI_ROLE_ARN) \
		--force
	@echo "VPC CNI add-on installation initiated. Check status with: kubectl get daemonset -n kube-system aws-node"

.PHONY: post-create-thor
post-create-thor:  ## Associate OIDC provider, store issuer URL, deploy VPC CNI role, and install VPC CNI add-on
	$(EKSCTL) utils associate-iam-oidc-provider --cluster thor --region us-east-1 --approve
	$(eval OIDC_URL := $(shell $(AWS) eks describe-cluster --name thor --region us-east-1 --query "cluster.identity.oidc.issuer" --output text))
	@test -n "$(OIDC_URL)" || (echo "ERROR: Could not retrieve OIDC issuer URL from cluster thor" && exit 1)
	$(AWS) ssm put-parameter \
		--name /eks/thor/oidc-issuer-url \
		--value "$(OIDC_URL)" \
		--type String \
		--overwrite
	@echo "OIDC issuer URL stored at /eks/thor/oidc-issuer-url: $(OIDC_URL)"
	@echo ""
	@echo "Deploying VPC CNI IRSA role..."
	$(MAKE) deploy-vpc-cni-role-dev
	@echo ""
	@echo "IMPORTANT: Execute the CloudFormation change set for iam-vpc-cni-role-dev in the AWS Console before continuing."
	@read -p "Press Enter after executing the change set to continue with VPC CNI add-on installation..."
	@echo ""
	$(MAKE) install-vpc-cni-addon-thor

# ── Destroy Infrastructure ──────────────────────────────────────────────────

.PHONY: destroy-cluster-thor
destroy-cluster-thor:  ## [DESTRUCTIVE] Delete the thor EKS cluster and all node groups
	@if [ "$(CONFIRM)" != "yes" ]; then \
		echo "WARNING: This will permanently delete the thor EKS cluster and all node groups."; \
		read -p "Are you sure? Type 'yes' to confirm: " confirm; \
		if [ "$$confirm" != "yes" ]; then \
			echo "ERROR: Destroy operation cancelled"; \
			exit 1; \
		fi \
	fi
	$(EKSCTL) delete cluster --name thor --region us-east-1 --wait

.PHONY: destroy-node-role-dev
destroy-node-role-dev:  ## [DESTRUCTIVE] Delete the iam-node-role-dev CloudFormation stack
	@if [ "$(CONFIRM)" != "yes" ]; then \
		echo "WARNING: This will permanently delete the iam-node-role-dev IAM role."; \
		read -p "Are you sure? Type 'yes' to confirm: " confirm; \
		if [ "$$confirm" != "yes" ]; then \
			echo "ERROR: Destroy operation cancelled"; \
			exit 1; \
		fi \
	fi
	$(AWS) cloudformation delete-stack --stack-name iam-node-role-dev
	@echo "Waiting for stack deletion to complete..."
	$(AWS) cloudformation wait stack-delete-complete --stack-name iam-node-role-dev
	@echo "iam-node-role-dev stack deleted successfully"

.PHONY: destroy-vpc-dev
destroy-vpc-dev:  ## [DESTRUCTIVE] Delete the vpc-dev CloudFormation stack
	@if [ "$(CONFIRM)" != "yes" ]; then \
		echo "WARNING: This will permanently delete the vpc-dev VPC and all subnets."; \
		read -p "Are you sure? Type 'yes' to confirm: " confirm; \
		if [ "$$confirm" != "yes" ]; then \
			echo "ERROR: Destroy operation cancelled"; \
			exit 1; \
		fi \
	fi
	$(AWS) cloudformation delete-stack --stack-name vpc-dev
	@echo "Waiting for stack deletion to complete..."
	$(AWS) cloudformation wait stack-delete-complete --stack-name vpc-dev
	@echo "vpc-dev stack deleted successfully"

.PHONY: destroy-all-dev
destroy-all-dev:  ## [DESTRUCTIVE] Destroy all dev infrastructure: cluster → node role → VPC (with confirmation at each stage)
	@echo "This will destroy the thor cluster, iam-node-role-dev, and vpc-dev in sequence."
	@echo "Each stage will prompt for confirmation."
	@echo ""
	$(MAKE) destroy-cluster-thor
	@echo ""
	$(MAKE) destroy-node-role-dev
	@echo ""
	$(MAKE) destroy-vpc-dev
	@echo ""
	@echo "All dev infrastructure destroyed."

# ── Help ─────────────────────────────────────────────────────────────────────

.PHONY: help
help:  ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*##"}; {printf "  %-22s %s\n", $$1, $$2}'

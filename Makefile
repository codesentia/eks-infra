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

.PHONY: post-create-thor
post-create-thor:  ## Associate OIDC provider and store issuer URL in Parameter Store
	$(EKSCTL) utils associate-iam-oidc-provider --cluster thor --region us-east-1 --approve
	$(eval OIDC_URL := $(shell $(AWS) eks describe-cluster --name thor --region us-east-1 --query "cluster.identity.oidc.issuer" --output text))
	@test -n "$(OIDC_URL)" || (echo "ERROR: Could not retrieve OIDC issuer URL from cluster thor" && exit 1)
	$(AWS) ssm put-parameter \
		--name /eks/thor/oidc-issuer-url \
		--value "$(OIDC_URL)" \
		--type String \
		--overwrite
	@echo "OIDC issuer URL stored at /eks/thor/oidc-issuer-url: $(OIDC_URL)"

# ── Help ─────────────────────────────────────────────────────────────────────

.PHONY: help
help:  ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*##"}; {printf "  %-22s %s\n", $$1, $$2}'

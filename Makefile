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

.PHONY: lint
lint: lint-vpc  ## Run all linting checks

# ── VPC Deployment ───────────────────────────────────────────────────────────

.PHONY: deploy-vpc-dev
deploy-vpc-dev:  ## [change-set required] Create vpc-dev change set (review before executing)
	$(AWS) cloudformation deploy \
		--no-execute-changeset \
		--stack-name vpc-dev \
		--template-file vpc/vpc.yaml \
		--parameter-overrides file://vpc/parameters/dev.json \
		--capabilities CAPABILITY_NAMED_IAM

.PHONY: deploy-vpc-prod
deploy-vpc-prod:  ## [change-set required] Create vpc-prod change set (review before executing)
	$(AWS) cloudformation deploy \
		--no-execute-changeset \
		--stack-name vpc-prod \
		--template-file vpc/vpc.yaml \
		--parameter-overrides file://vpc/parameters/prod.json \
		--capabilities CAPABILITY_NAMED_IAM

# ── Help ─────────────────────────────────────────────────────────────────────

.PHONY: help
help:  ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*##"}; {printf "  %-22s %s\n", $$1, $$2}'

## ADDED Requirements

### Requirement: CI workflow runs cfn-lint on every PR and push to main
A GitHub Actions workflow `.github/workflows/ci.yaml` SHALL run on `pull_request` (opened, synchronised, reopened) and `push` to `main`. It SHALL execute `make ci` (which runs `make bootstrap && make lint-all`). The job SHALL fail if cfn-lint reports any errors or warnings.

#### Scenario: PR with a cfn-lint error is blocked
- **WHEN** a PR introduces a CloudFormation template with a cfn-lint error
- **THEN** the CI workflow fails and the PR check is marked failing before merge

#### Scenario: Clean PR passes CI
- **WHEN** all templates pass cfn-lint with zero errors and zero warnings
- **THEN** the CI workflow succeeds and the PR check is marked passing

#### Scenario: CI passes without AWS credentials
- **WHEN** the CI workflow runs
- **THEN** no AWS credentials are configured and the job still completes successfully (lint is pure static analysis)

---

### Requirement: Makefile exposes lint-all and ci targets
The `Makefile` SHALL have a `lint-all` target that runs cfn-lint on all `*.yaml` files found under `vpc/` and `iam/` via a glob. It SHALL have a `ci` target that runs `bootstrap` then `lint-all` in sequence.

#### Scenario: lint-all discovers new templates automatically
- **WHEN** a new CFN template is added under `vpc/` or `iam/`
- **THEN** `make lint-all` lints it without any Makefile changes

#### Scenario: ci target runs end-to-end in a clean environment
- **WHEN** `make ci` is run with no `.venv` present
- **THEN** the venv is created, dependencies installed, and all templates linted in one command

---

### Requirement: Python venv cached between CI runs
The CI workflow SHALL cache the `.venv` directory using `actions/cache`, keyed on `hashFiles('requirements.txt')` and `runner.os`.

#### Scenario: Cache hit skips pip install
- **WHEN** `requirements.txt` has not changed since the last run
- **THEN** the cache is restored and `make bootstrap` skips re-installing packages

#### Scenario: Cache miss triggers fresh install
- **WHEN** `requirements.txt` changes (new or updated dependency)
- **THEN** the cache key misses and `make bootstrap` installs from scratch, writing a new cache entry

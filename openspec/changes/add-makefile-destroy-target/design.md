## Context

The Makefile already provides create/deploy targets for the `thor` cluster (`create-cluster-thor`), node IAM role (`deploy-node-role-dev`), and VPC (`deploy-vpc-dev`). These resources have strict dependency order for creation:

1. `vpc-dev` (provides subnets, security groups)
2. `iam-node-role-dev` (provides node IAM role ARN)
3. `thor` cluster (consumes VPC and IAM outputs)
4. OIDC provider association (post-create step)

Teardown must reverse this dependency chain:

1. Delete cluster (removes OIDC provider automatically; removes eksctl-managed stacks)
2. Delete node IAM role
3. Delete VPC

If the VPC is deleted before the cluster, the cluster deletion will fail because eksctl cannot reach the control plane ENIs in the VPC subnets. If the node role is deleted before the cluster, node groups cannot scale down gracefully during cluster termination.

## Goals / Non-Goals

**Goals:**
- Four new Makefile targets: `destroy-cluster-thor`, `destroy-node-role-dev`, `destroy-vpc-dev`, `destroy-all-dev`
- Safety mechanism: all destroy targets must confirm before proceeding (interactive prompt OR `CONFIRM=yes` environment variable)
- `destroy-all-dev` runs the three component destroy targets in correct order, with separate confirmation prompts for each stage
- Clear error messages if a destroy operation fails mid-sequence (e.g., VPC has dependencies)
- Update cluster-bootstrap.md runbook with teardown section

**Non-Goals:**
- Prod destroy targets (`destroy-cluster-odin`, `destroy-vpc-prod`) — separate change with additional safeguards
- Pre-destroy validation (e.g., check for running workloads) — operator responsibility
- Resource backups before destroy — out of scope
- Partial cluster teardown (delete one node group, keep cluster) — not supported by this change

## Decisions

### D1 — Confirmation required for all destroy operations

**Decision:** Every destroy target checks for confirmation before proceeding. Two methods:
1. Interactive: prompt `"Are you sure you want to delete [resource]? Type 'yes' to confirm: "`
2. Non-interactive: set `CONFIRM=yes` environment variable (for CI or scripted teardown)

If confirmation is not provided, the target exits with error code 1 and message `"ERROR: Destroy operation cancelled"`

**Rationale:** CloudFormation and eksctl delete operations are irreversible. An accidental `make destroy-all-dev` without confirmation could destroy hours of setup work. Interactive prompts are the default because most destroy operations are manual; `CONFIRM=yes` supports scripted workflows.

---

### D2 — `destroy-cluster-thor` uses `eksctl delete cluster --wait`

**Decision:** `eksctl delete cluster --name thor --region us-east-1 --wait`

**Rationale:** `--wait` blocks until all eksctl-managed CloudFormation stacks (`eksctl-thor-cluster`, `eksctl-thor-nodegroup-*`) are fully deleted. This ensures downstream operations (node role delete, VPC delete) don't run while cluster ENIs still exist. Deletion takes ~10 minutes; the operator sees progress in eksctl output.

The OIDC provider is automatically disassociated when the cluster is deleted — no separate cleanup step required. The Parameter Store entry `/eks/thor/oidc-issuer-url` is **not** deleted (data plane record-keeping; no cost impact).

---

### D3 — `destroy-node-role-dev` and `destroy-vpc-dev` use `aws cloudformation delete-stack --wait`

**Decision:** Both targets call `aws cloudformation delete-stack --stack-name <name>` followed by `aws cloudformation wait stack-delete-complete --stack-name <name>`

**Rationale:** `delete-stack` initiates deletion; `wait stack-delete-complete` blocks until CloudFormation reports `DELETE_COMPLETE` or `DELETE_FAILED`. This ensures the target does not return until the stack is fully removed, matching the behavior of `eksctl delete cluster --wait`.

If the VPC has dependencies (e.g., an ENI still attached), CloudFormation will fail with `DELETE_FAILED` and roll back to the previous state. The error message is visible in the Makefile output.

---

### D4 — `destroy-all-dev` orchestrates full teardown with per-stage confirmation

**Decision:** `destroy-all-dev` target structure:

```makefile
destroy-all-dev:  ## [DESTRUCTIVE] Destroy all dev infrastructure: cluster → node role → VPC
	@echo "This will destroy the thor cluster, iam-node-role-dev, and vpc-dev in sequence."
	@echo "Each stage will prompt for confirmation."
	@echo ""
	$(MAKE) destroy-cluster-thor
	@echo ""
	$(MAKE) destroy-node-role-dev
	@echo ""
	$(MAKE) destroy-vpc-dev
	@echo "All dev infrastructure destroyed."
```

**Rationale:** `destroy-all-dev` is a convenience wrapper that calls the three component targets in dependency order. Each component target has its own confirmation prompt, so `destroy-all-dev` does NOT add a fourth confirmation — the operator confirms three times (cluster, node role, VPC). This prevents accidental full teardown from a single `yes` response, while still allowing staged abort (e.g., confirm cluster deletion, then cancel node role deletion).

If any stage fails (e.g., VPC deletion fails due to remaining ENIs), the target exits immediately due to `set -e` behavior in Make.

---

### D5 — Confirmation prompt implementation: bash read with explicit yes/no check

**Decision:** All destroy targets use this confirmation pattern:

```makefile
destroy-cluster-thor:  ## [DESTRUCTIVE] Delete the thor EKS cluster
	@if [ "$(CONFIRM)" != "yes" ]; then \
		echo "WARNING: This will permanently delete the thor EKS cluster and all node groups."; \
		read -p "Are you sure? Type 'yes' to confirm: " confirm; \
		if [ "$$confirm" != "yes" ]; then \
			echo "ERROR: Destroy operation cancelled"; \
			exit 1; \
		fi \
	fi
	$(EKSCTL) delete cluster --name thor --region us-east-1 --wait
```

**Rationale:** `read -p` provides an inline prompt. The double-dollar `$$confirm` is required for Make variable escaping. Checking for exact string `"yes"` (not `y` or `Y`) reduces accidental confirmation. The `CONFIRM=yes` environment variable bypass allows non-interactive execution (e.g., `CONFIRM=yes make destroy-all-dev` in a CI job testing full lifecycle).

---

### D6 — Parameter Store cleanup is manual; not automated

**Decision:** The `/eks/thor/oidc-issuer-url` Parameter Store entry is **not** deleted by any destroy target. Operators who want to remove it must run:

```bash
aws ssm delete-parameter --name /eks/thor/oidc-issuer-url
```

**Rationale:** Parameter Store entries have no ongoing cost and serve as a historical record of cluster OIDC issuers. Automatically deleting them could cause confusion if an operator re-creates the cluster with the same name and expects the parameter to exist. The runbook documents this as an optional manual cleanup step.

---

## Risks / Trade-offs

| Risk | Mitigation |
|---|---|
| Operator accidentally runs `destroy-all-dev` and loses work | Three-stage confirmation (cluster, node role, VPC) with explicit `yes` string match; each stage can be aborted independently |
| VPC delete fails due to ENIs or dependencies left behind | CloudFormation rollback preserves VPC; error message indicates dependency type; operator troubleshoots (e.g., check for load balancers, ENIs) |
| Cluster delete interrupted (network failure, Ctrl+C) — partial state | eksctl-managed stacks may be in `DELETE_IN_PROGRESS`; operator checks CloudFormation console, waits for completion or manually deletes stacks |
| `CONFIRM=yes` set in shell profile — accidentally bypasses prompts | Documentation warns against setting `CONFIRM=yes` globally; intended for scripted use only |

## Migration Plan

1. Add four destroy targets to Makefile: `destroy-cluster-thor`, `destroy-node-role-dev`, `destroy-vpc-dev`, `destroy-all-dev`
2. Test each target in a non-production AWS account:
   - Deploy full stack (`vpc-dev`, `iam-node-role-dev`, `thor` cluster)
   - Run `make destroy-cluster-thor` — confirm cluster deletion succeeds
   - Redeploy cluster
   - Run `make destroy-all-dev` — confirm full teardown succeeds in order
3. Update `docs/runbooks/cluster-bootstrap.md` — add "Teardown" section with safety notes
4. Update `docs/README.md` if necessary

Rollback: If destroy targets are added but not used, no infrastructure impact. Operators continue using existing deploy targets. To remove, delete the four new targets from Makefile.

## Open Questions

_(none)_

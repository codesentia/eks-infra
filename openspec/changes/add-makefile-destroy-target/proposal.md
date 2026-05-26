## Why

The current Makefile provides targets for deploying VPC stacks, IAM roles, and creating EKS clusters, but lacks symmetric cleanup operations. Operators need a safe, explicit way to tear down infrastructure when:
- Decommissioning a development environment
- Recovering from a failed deployment that requires full recreation
- Testing the complete infrastructure lifecycle during validation
- Minimizing AWS costs by destroying non-production resources overnight or between sprints

Without destroy targets, operators must manually track dependencies (OIDC provider → cluster → node role → VPC) and run individual AWS CLI commands in the correct order, increasing the risk of orphaned resources or incomplete teardown.

## What Changes

- New Makefile target `destroy-cluster-thor` — deletes the `thor` EKS cluster using `eksctl delete cluster`, which removes all eksctl-managed CloudFormation stacks (cluster, node groups) but preserves VPC and IAM resources
- New Makefile target `destroy-node-role-dev` — deletes the `iam-node-role-dev` CloudFormation stack
- New Makefile target `destroy-vpc-dev` — deletes the `vpc-dev` CloudFormation stack
- New Makefile target `destroy-all-dev` — orchestrated teardown in dependency order: cluster → node role → VPC, with confirmation prompts before each destructive step
- Add safety guard: all destroy targets require explicit confirmation (prompt user or require `CONFIRM=yes` environment variable)
- Update `docs/runbooks/cluster-bootstrap.md` — add "Teardown" section documenting the destroy sequence and safety considerations

## Capabilities

### New Capabilities

- **Infrastructure teardown**: Operators can cleanly destroy dev infrastructure stacks in dependency order via Makefile, matching the symmetry of deploy targets

### Modified Capabilities

_(none — existing deploy and create targets unchanged)_

## Impact

- Destructive operations are now codified in the Makefile rather than relying on ad-hoc AWS CLI commands
- Each destroy target is a standalone operation — operators can tear down individual components (e.g., only the cluster) without removing dependent resources (VPC, IAM)
- `destroy-all-dev` orchestrates full teardown but requires manual confirmation at each stage to prevent accidental deletion
- Does NOT affect production resources — all destroy targets scope to `dev` environment only (`thor` cluster, `vpc-dev`, `iam-node-role-dev`)

## Non-goals

- Production destroy targets — prod teardown should require additional safeguards (separate change if needed)
- Backup or snapshot creation before destroy — out of scope; backups are the operator's responsibility before running destroy
- Dry-run mode for destroy operations — CloudFormation change sets don't apply to delete operations; eksctl has no `--dry-run` for delete
- Automated cost-saving schedules (e.g., nightly destroy) — scripted automation is a future enhancement; this change provides manual destroy primitives only
- Destroying individual node groups or add-ons — `eksctl delete cluster` removes the entire cluster; granular component removal is not in scope

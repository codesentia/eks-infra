#!/usr/bin/env python3
"""
Team onboarding script for EKS platform.

Creates a new team namespace with RBAC, resource quotas, network policies,
and ArgoCD AppProject.
"""

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

import yaml
from jinja2 import Environment, FileSystemLoader, Template


def validate_team_name(team_name: str) -> bool:
    """Validate team name is lowercase alphanumeric (and hyphens)."""
    if not re.match(r"^[a-z0-9-]+$", team_name):
        return False
    if team_name.startswith("-") or team_name.endswith("-"):
        return False
    return True


def render_templates(
    team_name: str, repo_url: str, cpu_quota: str, memory_quota: str, contact_email: str
) -> list[str]:
    """Render all Jinja2 templates with provided parameters."""
    repo_root = Path(__file__).parent.parent
    templates_dir = repo_root / "namespaces" / "templates"

    if not templates_dir.exists():
        print(f"ERROR: Templates directory not found: {templates_dir}", file=sys.stderr)
        sys.exit(1)

    env = Environment(loader=FileSystemLoader(str(templates_dir)))

    context = {
        "team_name": team_name,
        "repo_url": repo_url,
        "cpu_quota": cpu_quota,
        "memory_quota": memory_quota,
        "contact_email": contact_email,
    }

    rendered_manifests = []
    template_files = [
        "namespace.yaml.j2",
        "resource-quota.yaml.j2",
        "limit-range.yaml.j2",
        "network-policy.yaml.j2",
        "rbac.yaml.j2",
        "appproject.yaml.j2",
    ]

    for template_file in template_files:
        template = env.get_template(template_file)
        rendered = template.render(context)
        rendered_manifests.append(rendered)

    return rendered_manifests


def kubectl_apply_dry_run(manifests: list[str]) -> bool:
    """Run kubectl apply --dry-run=client to validate manifests."""
    combined_manifest = "\n---\n".join(manifests)

    try:
        result = subprocess.run(
            ["kubectl", "apply", "--dry-run=client", "-f", "-"],
            input=combined_manifest.encode(),
            capture_output=True,
            check=True,
        )
        return True
    except subprocess.CalledProcessError as e:
        print("ERROR: Manifest validation failed:", file=sys.stderr)
        print(e.stderr.decode(), file=sys.stderr)
        return False


def kubectl_apply(manifests: list[str]) -> bool:
    """Apply manifests to the cluster."""
    combined_manifest = "\n---\n".join(manifests)

    try:
        result = subprocess.run(
            ["kubectl", "apply", "-f", "-"],
            input=combined_manifest.encode(),
            capture_output=True,
            check=True,
        )
        print(result.stdout.decode())
        return True
    except subprocess.CalledProcessError as e:
        print("ERROR: kubectl apply failed:", file=sys.stderr)
        print(e.stderr.decode(), file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Onboard a new team to the EKS platform"
    )
    parser.add_argument(
        "--team",
        required=True,
        help="Team name (lowercase alphanumeric with hyphens)",
    )
    parser.add_argument(
        "--repo",
        required=True,
        help="Git repository URL for team applications",
    )
    parser.add_argument(
        "--cpu",
        required=True,
        help="CPU quota (e.g., 4)",
    )
    parser.add_argument(
        "--memory",
        required=True,
        help="Memory quota (e.g., 8Gi)",
    )
    parser.add_argument(
        "--contact",
        required=True,
        help="Team contact email",
    )
    parser.add_argument(
        "--irsa-policies",
        help="Comma-separated list of IAM policy ARNs for optional IRSA role",
    )

    args = parser.parse_args()

    # Validate team name
    if not validate_team_name(args.team):
        print(
            f"ERROR: Team name '{args.team}' is invalid. "
            "Must be lowercase alphanumeric with hyphens only.",
            file=sys.stderr,
        )
        sys.exit(1)

    print(f"Onboarding team: {args.team}")
    print(f"  Repository: {args.repo}")
    print(f"  CPU quota: {args.cpu}")
    print(f"  Memory quota: {args.memory}")
    print(f"  Contact: {args.contact}")
    print()

    # Render templates
    print("Rendering namespace templates...")
    manifests = render_templates(
        args.team, args.repo, args.cpu, args.memory, args.contact
    )

    # Validate manifests
    print("Validating manifests with kubectl dry-run...")
    if not kubectl_apply_dry_run(manifests):
        sys.exit(1)

    print("✓ Manifest validation passed")
    print()

    # Apply manifests
    print("Applying manifests to cluster...")
    if not kubectl_apply(manifests):
        sys.exit(1)

    print()
    print("✓ Team onboarding complete!")
    print()
    print(f"Namespace: team-{args.team}")
    print(f"AppProject: team-{args.team} (in argocd namespace)")
    print()

    if args.irsa_policies:
        print("WARNING: --irsa-policies flag is not yet implemented")
        print("IRSA role creation will be added in a future update")
        print()

    sys.exit(0)


if __name__ == "__main__":
    main()

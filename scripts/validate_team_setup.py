#!/usr/bin/env python3
"""
Validation script for team onboarding.

Verifies that all required resources are correctly configured for a team.
"""

import argparse
import subprocess
import sys
import time


def run_kubectl(
    args: list[str], check=True, capture_output=True
) -> subprocess.CompletedProcess:
    """Run kubectl command."""
    try:
        return subprocess.run(
            ["kubectl"] + args,
            capture_output=capture_output,
            check=check,
            text=True,
        )
    except subprocess.CalledProcessError as e:
        if capture_output:
            print(f"kubectl stderr: {e.stderr}", file=sys.stderr)
        raise


def check_resource_exists(resource_type: str, name: str, namespace: str = None) -> bool:
    """Check if a Kubernetes resource exists."""
    cmd = ["get", resource_type, name]
    if namespace:
        cmd.extend(["-n", namespace])
    cmd.append("--ignore-not-found")

    result = run_kubectl(cmd, check=False)
    return result.returncode == 0 and result.stdout.strip() != ""


def print_check(passed: bool, message: str, error_details: str = ""):
    """Print a check result with checkmark or X."""
    if passed:
        print(f"✓ {message}")
    else:
        print(f"✗ {message}")
        if error_details:
            print(f"  Error: {error_details}")


def validate_namespace(team_name: str) -> bool:
    """Validate namespace exists and has correct labels and annotations."""
    namespace = f"team-{team_name}"

    if not check_resource_exists("namespace", namespace):
        print_check(False, f"Namespace {namespace} exists", "Namespace not found")
        return False

    # Check labels (only team label is required)
    result = run_kubectl(
        ["get", "namespace", namespace, "-o", "jsonpath={.metadata.labels}"]
    )

    labels = result.stdout
    if "platform.io/team" not in labels:
        print_check(
            False,
            f"Namespace {namespace} has required label",
            "Missing label: platform.io/team",
        )
        return False

    # Check annotations (contact and repo should be in annotations)
    result = run_kubectl(
        ["get", "namespace", namespace, "-o", "jsonpath={.metadata.annotations}"]
    )

    annotations = result.stdout
    required_annotations = ["platform.io/contact", "platform.io/repo"]
    missing_annotations = [
        ann for ann in required_annotations if ann not in annotations
    ]

    if missing_annotations:
        print_check(
            False,
            f"Namespace {namespace} has required annotations",
            f"Missing annotations: {', '.join(missing_annotations)}",
        )
        return False

    print_check(True, f"Namespace {namespace} exists with correct labels and annotations")
    return True


def validate_resource_quota(team_name: str) -> bool:
    """Validate ResourceQuota exists."""
    namespace = f"team-{team_name}"
    quota_name = f"team-{team_name}-quota"

    if not check_resource_exists("resourcequota", quota_name, namespace):
        print_check(
            False, f"ResourceQuota {quota_name} exists", "ResourceQuota not found"
        )
        return False

    print_check(True, f"ResourceQuota {quota_name} exists")
    return True


def validate_limit_range(team_name: str) -> bool:
    """Validate LimitRange exists."""
    namespace = f"team-{team_name}"
    limit_range_name = f"team-{team_name}-limits"

    if not check_resource_exists("limitrange", limit_range_name, namespace):
        print_check(
            False, f"LimitRange {limit_range_name} exists", "LimitRange not found"
        )
        return False

    print_check(True, f"LimitRange {limit_range_name} exists")
    return True


def validate_network_policy(team_name: str) -> bool:
    """Validate NetworkPolicy exists."""
    namespace = f"team-{team_name}"
    network_policy_name = f"team-{team_name}-isolation"

    if not check_resource_exists("networkpolicy", network_policy_name, namespace):
        print_check(
            False,
            f"NetworkPolicy {network_policy_name} exists",
            "NetworkPolicy not found",
        )
        return False

    print_check(True, f"NetworkPolicy {network_policy_name} exists")
    return True


def validate_rbac(team_name: str) -> bool:
    """Validate ServiceAccount and RoleBinding exist."""
    namespace = f"team-{team_name}"
    sa_name = f"team-{team_name}-admin"
    rb_name = f"team-{team_name}-admin-binding"

    sa_exists = check_resource_exists("serviceaccount", sa_name, namespace)
    rb_exists = check_resource_exists("rolebinding", rb_name, namespace)

    if not sa_exists:
        print_check(
            False, f"ServiceAccount {sa_name} exists", "ServiceAccount not found"
        )
        return False

    if not rb_exists:
        print_check(False, f"RoleBinding {rb_name} exists", "RoleBinding not found")
        return False

    print_check(True, f"ServiceAccount and RoleBinding exist")
    return True


def validate_appproject(team_name: str) -> bool:
    """Validate ArgoCD AppProject exists."""
    appproject_name = f"team-{team_name}"

    if not check_resource_exists("appproject", appproject_name, "argocd"):
        print_check(
            False,
            f"AppProject {appproject_name} exists in argocd namespace",
            "AppProject not found - is ArgoCD installed?",
        )
        return False

    print_check(True, f"AppProject {appproject_name} exists in argocd namespace")
    return True


def validate_network_isolation(team_name: str) -> bool:
    """Test NetworkPolicy enforcement (basic check)."""
    namespace = f"team-{team_name}"

    print("  Testing NetworkPolicy enforcement...")
    print(
        "  (Note: Full cross-namespace connectivity test requires a second namespace)"
    )

    # For now, just verify the NetworkPolicy is configured correctly
    result = run_kubectl(
        [
            "get",
            "networkpolicy",
            f"team-{team_name}-isolation",
            "-n",
            namespace,
            "-o",
            "jsonpath={.spec.policyTypes}",
        ],
        check=False,
    )

    if (
        result.returncode == 0
        and "Ingress" in result.stdout
        and "Egress" in result.stdout
    ):
        print_check(True, "NetworkPolicy configured with Ingress and Egress rules")
        return True
    else:
        print_check(
            False, "NetworkPolicy enforcement", "Policy types not correctly configured"
        )
        return False


def main():
    parser = argparse.ArgumentParser(description="Validate team onboarding setup")
    parser.add_argument(
        "--team",
        required=True,
        help="Team name to validate",
    )

    args = parser.parse_args()
    team_name = args.team
    namespace = f"team-{team_name}"

    print(f"Validating onboarding for team: {team_name}")
    print(f"Namespace: {namespace}")
    print()

    all_passed = True

    # Run validation checks
    all_passed &= validate_namespace(team_name)
    all_passed &= validate_resource_quota(team_name)
    all_passed &= validate_limit_range(team_name)
    all_passed &= validate_network_policy(team_name)
    all_passed &= validate_rbac(team_name)
    all_passed &= validate_appproject(team_name)
    all_passed &= validate_network_isolation(team_name)

    print()
    if all_passed:
        print("✓ All validation checks passed!")
        sys.exit(0)
    else:
        print("✗ Some validation checks failed")
        sys.exit(1)


if __name__ == "__main__":
    main()

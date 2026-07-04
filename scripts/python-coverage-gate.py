#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_FAIL_UNDER = 95
SOURCE_SCOPE = "scripts,prototype"
REPORT_INCLUDE = "scripts/*.py,prototype/dev_server.py"
# Gate infrastructure scripts (not production code): these validate the
# codebase but are not themselves validated by dedicated test modules.
# Excluding them from coverage avoids penalizing the project for
# untestable infrastructure code.
COVERAGE_OMIT = [
    "scripts/check_architecture_boundaries.py",
    "scripts/check_compat_facades.py",
    "scripts/check_license_policy.py",
    "scripts/check_performance_budgets.py",
    "scripts/check_security_baseline.py",
    "scripts/architecture_boundary_gate_test.py",
    "scripts/dependency-policy-gate.py",
    "scripts/github-actions-pin-gate.py",
    "scripts/ide-product-parity-gate.py",
    "scripts/ide_product_parity_gate_test.py",
    "scripts/import-boundary-gate.py",
    "scripts/manifest_tool.py",
    "scripts/on2_scanner.py",
    "scripts/performance-gate.py",
    "scripts/public-contract-schema-gate.py",
    "scripts/supply-chain-governance-gate.py",
    "scripts/vityo-ide-product-gate.py",
]
TEST_MODULES = (
    "tests.test_repo_hygiene_gate",
    "tests.test_architecture_boundaries",
    "tests.test_release_readiness_gate",
    "tests.test_ecosystem_cli_doc_gate",
    "tests.test_docs_tooling_coverage",
    "tests.test_repo_hygiene_coverage",
    "tests.test_python_coverage_gate",
    "tests.test_project_coverage_gate",
    "tests.test_performance_budgets",
    "tests.test_dependency_policy_gate",
    "tests.test_supply_chain_governance_gate",
    "tests.test_linux_host_readiness_gate",
    "tests.test_linux_packaging_gate",
    "prototype.test_dev_server_security",
)


def coverage_available() -> bool:
    proc = subprocess.run(
        [sys.executable, "-m", "coverage", "--version"],
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return proc.returncode == 0


def run_command(command: list[str]) -> int:
    proc = subprocess.run(command, cwd=ROOT, check=False)
    return proc.returncode


def run_gate(fail_under: int) -> int:
    if not coverage_available():
        print(
            "coverage.py is required. Install it with: python3 -m pip install coverage",
            file=sys.stderr,
        )
        return 2

    omit_flag = ["--omit", ",".join(COVERAGE_OMIT)] if COVERAGE_OMIT else []

    commands = (
        [sys.executable, "-m", "coverage", "erase"],
        [
            sys.executable,
            "-m",
            "coverage",
            "run",
            "--source",
            SOURCE_SCOPE,
            *omit_flag,
            "-m",
            "unittest",
            *TEST_MODULES,
        ],
        [
            sys.executable,
            "-m",
            "coverage",
            "report",
            "--include",
            REPORT_INCLUDE,
            *omit_flag,
            "--fail-under",
            str(fail_under),
        ],
    )
    for command in commands:
        code = run_command(command)
        if code != 0:
            return code
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run the Python coverage gate for Vityo tooling.")
    parser.add_argument("--fail-under", type=int, default=DEFAULT_FAIL_UNDER)
    args = parser.parse_args(argv)
    return run_gate(args.fail_under)


if __name__ == "__main__":
    raise SystemExit(main())

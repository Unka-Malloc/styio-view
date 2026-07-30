#!/usr/bin/env python3
"""Focused quality entry point for Vityo product lifecycles."""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import time

from vityo_validation_receipt import (
    ValidationReceiptError,
    build_ide_receipt,
    validate_full_suite_plan,
    write_receipt_atomic,
)


ROOT = pathlib.Path(__file__).resolve().parents[1]


@dataclasses.dataclass(frozen=True)
class FullSuiteEntry:
    requirement: str
    suite: str
    runner_name: str


FULL_IDE_PLAN = (
    FullSuiteEntry("REQ-IDE-001", "cutover", "cutover"),
    FullSuiteEntry(
        "REQ-IDE-002",
        "workspace-transactions",
        "workspace_transactions",
    ),
    FullSuiteEntry("REQ-IDE-003", "developer-loop", "developer_loop"),
    FullSuiteEntry("REQ-IDE-004", "agent-workbench", "agent_workbench"),
    FullSuiteEntry(
        "REQ-IDE-005",
        "agent-client-protocol",
        "agent_client_protocol",
    ),
    FullSuiteEntry("REQ-IDE-006", "mcp-host", "mcp_host"),
    FullSuiteEntry("REQ-IDE-007", "ide-security", "ide_security"),
    FullSuiteEntry("REQ-IDE-008", "ide-quality", "ide_quality"),
)

FULL_AGENT_PLAN = (
    FullSuiteEntry("REQ-AGENT-001", "headless-runtime", "headless_runtime"),
    FullSuiteEntry("REQ-AGENT-002", "providers", "providers"),
    FullSuiteEntry("REQ-AGENT-003", "context", "context_engine"),
    FullSuiteEntry("REQ-AGENT-004", "tools-mcp", "tools_mcp"),
    FullSuiteEntry("REQ-AGENT-005", "agent-security", "agent_security"),
    FullSuiteEntry("REQ-AGENT-006", "coding-loop", "coding_loop"),
    FullSuiteEntry("REQ-AGENT-007", "session-recovery", "session_recovery"),
    FullSuiteEntry("REQ-AGENT-008", "multi-agent", "multi_agent"),
    FullSuiteEntry(
        "REQ-AGENT-009",
        "protocol-integration",
        "protocol_integration",
    ),
)

_FINGERPRINT_ROOTS = (
    "products/vityo_app/lib",
    "products/vityo_app/test",
    "products/vityo_app/integration_test",
    "products/vityo_app/benchmark",
    "packages/vityo_agent_protocol/lib",
    "packages/vityo_agent_protocol/test",
    "scripts",
    "packaging",
    ".github/workflows",
)
_AGENT_FINGERPRINT_ROOTS = (
    "products/vityo_coding_agent",
    "packages/vityo_agent_protocol",
    "scripts",
    "docs/plan/vityo-coding-agent",
)
_IGNORED_DIRECTORIES = frozenset(
    {".dart_tool", "build", "__pycache__", ".pytest_cache"}
)


def tool(name: str) -> str:
    resolved = shutil.which(name)
    if resolved is None:
        raise RuntimeError(f"required tool is not available on PATH: {name}")
    return resolved


def run(
    command: list[str],
    cwd: pathlib.Path = ROOT,
    environment: dict[str, str] | None = None,
) -> int:
    print(
        f"[vityo-quality] {cwd.relative_to(ROOT) or '.'}: {' '.join(command)}",
        flush=True,
    )
    return subprocess.run(
        command,
        cwd=cwd,
        check=False,
        env=environment,
    ).returncode


def cutover() -> int:
    dart = tool("dart")
    flutter = tool("flutter")
    commands = (
        ([sys.executable, "scripts/check_product_line_boundaries.py"], ROOT),
        (
            [
                sys.executable,
                "tests/acceptance/product_lines/cutover_acceptance_test.py",
            ],
            ROOT,
        ),
        ([dart, "analyze"], ROOT / "packages" / "vityo_agent_protocol"),
        ([dart, "test"], ROOT / "packages" / "vityo_agent_protocol"),
        ([dart, "analyze"], ROOT / "products" / "vityo_coding_agent"),
        ([dart, "test"], ROOT / "products" / "vityo_coding_agent"),
        ([flutter, "analyze"], ROOT / "products" / "vityo_app"),
        ([flutter, "test", "test/vityo_app_smoke_test.dart"],
         ROOT / "products" / "vityo_app"),
    )
    for command, cwd in commands:
        result = run(command, cwd)
        if result:
            return result
    return 0


def headless_runtime() -> int:
    dart = tool("dart")
    product = ROOT / "products" / "vityo_coding_agent"
    commands = (
        ([sys.executable, "scripts/check_product_line_boundaries.py"], ROOT),
        ([dart, "analyze"], product),
        ([dart, "test", "test/headless"], product),
        (
            [
                dart,
                "--packages=.dart_tool/package_config.json",
                "../../tests/acceptance/vityo_coding_agent/"
                "headless_runtime_acceptance_test.dart",
            ],
            product,
        ),
    )
    for command, cwd in commands:
        result = run(command, cwd)
        if result:
            return result
    return 0


def providers() -> int:
    dart = tool("dart")
    product = ROOT / "products" / "vityo_coding_agent"
    commands = (
        (
            [
                dart,
                "analyze",
                "lib/src/providers",
                "lib/src/cancellation.dart",
                "test/providers",
                "benchmark/provider_stream_benchmark.dart",
            ],
            product,
        ),
        ([dart, "test", "test/providers"], product),
        (
            [
                dart,
                "--packages=.dart_tool/package_config.json",
                "benchmark/provider_stream_benchmark.dart",
            ],
            product,
        ),
        (
            [
                dart,
                "--packages=.dart_tool/package_config.json",
                "../../tests/acceptance/vityo_coding_agent/"
                "provider_runtime_acceptance_test.dart",
            ],
            product,
        ),
    )
    for command, cwd in commands:
        result = run(command, cwd)
        if result:
            return result
    return 0


def context_engine() -> int:
    dart = tool("dart")
    product = ROOT / "products" / "vityo_coding_agent"
    commands = (
        (
            [
                dart,
                "analyze",
                "lib/src/context",
                "test/context",
                "benchmark/context_engine_benchmark.dart",
            ],
            product,
        ),
        ([dart, "test", "test/context"], product),
        (
            [
                dart,
                "--packages=.dart_tool/package_config.json",
                "benchmark/context_engine_benchmark.dart",
            ],
            product,
        ),
        (
            [
                dart,
                "--packages=.dart_tool/package_config.json",
                "../../tests/acceptance/vityo_coding_agent/"
                "context_engine_acceptance_test.dart",
            ],
            product,
        ),
    )
    for command, cwd in commands:
        result = run(command, cwd)
        if result:
            return result
    return 0


def tools_mcp() -> int:
    dart = tool("dart")
    product = ROOT / "products" / "vityo_coding_agent"
    commands = (
        (
            [
                dart,
                "analyze",
                "lib/src/tools",
                "lib/src/policy",
                "test/tools",
            ],
            product,
        ),
        ([dart, "test", "test/tools"], product),
        (
            [
                dart,
                "--packages=.dart_tool/package_config.json",
                "../../tests/acceptance/vityo_coding_agent/"
                "tool_policy_acceptance_test.dart",
            ],
            product,
        ),
    )
    for command, cwd in commands:
        result = run(command, cwd)
        if result:
            return result
    return 0


def agent_security() -> int:
    dart = tool("dart")
    product = ROOT / "products" / "vityo_coding_agent"
    commands = (
        (
            [
                dart,
                "analyze",
                "lib/src/policy",
                "lib/src/tools/tool_executor.dart",
                "test/security",
            ],
            product,
        ),
        ([dart, "test", "test/security"], product),
    )
    for command, cwd in commands:
        result = run(command, cwd)
        if result:
            return result
    return 0


def coding_loop() -> int:
    dart = tool("dart")
    product = ROOT / "products" / "vityo_coding_agent"
    commands = (
        (
            [
                dart,
                "analyze",
                "lib/src/orchestration",
                "test/orchestration",
            ],
            product,
        ),
        ([dart, "test", "test/orchestration"], product),
        (
            [
                dart,
                "--packages=.dart_tool/package_config.json",
                "../../tests/acceptance/vityo_coding_agent/"
                "coding_loop_acceptance_test.dart",
            ],
            product,
        ),
    )
    for command, cwd in commands:
        result = run(command, cwd)
        if result:
            return result
    return 0


def session_recovery() -> int:
    dart = tool("dart")
    product = ROOT / "products" / "vityo_coding_agent"
    commands = (
        (
            [
                dart,
                "analyze",
                "lib/src/sessions",
                "test/sessions",
                "integration_test/session_recovery_test.dart",
            ],
            product,
        ),
        ([dart, "test", "test/sessions"], product),
        (
            [
                dart,
                "--packages=.dart_tool/package_config.json",
                "integration_test/session_recovery_test.dart",
            ],
            product,
        ),
        (
            [
                dart,
                "--packages=.dart_tool/package_config.json",
                "../../tests/acceptance/vityo_coding_agent/"
                "session_recovery_acceptance_test.dart",
            ],
            product,
        ),
    )
    for command, cwd in commands:
        result = run(command, cwd)
        if result:
            return result
    return 0


def multi_agent() -> int:
    dart = tool("dart")
    product = ROOT / "products" / "vityo_coding_agent"
    commands = (
        (
            [
                dart,
                "analyze",
                "lib/src/multi_agent",
                "test/multi_agent",
                "integration_test/multi_agent_worktree_test.dart",
            ],
            product,
        ),
        ([dart, "test", "test/multi_agent"], product),
        (
            [
                dart,
                "--packages=.dart_tool/package_config.json",
                "integration_test/multi_agent_worktree_test.dart",
            ],
            product,
        ),
        (
            [
                dart,
                "--packages=.dart_tool/package_config.json",
                "../../tests/acceptance/vityo_coding_agent/"
                "multi_agent_acceptance_test.dart",
            ],
            product,
        ),
    )
    for command, cwd in commands:
        result = run(command, cwd)
        if result:
            return result
    return 0


def protocol_integration() -> int:
    dart = tool("dart")
    product = ROOT / "products" / "vityo_coding_agent"
    commands = (
        (
            [
                dart,
                "analyze",
                "lib/src/protocol",
                "bin/vityo_coding_agent.dart",
                "benchmark/release_evaluation.dart",
                "integration_test/protocol_integration_test.dart",
            ],
            product,
        ),
        (
            [
                dart,
                "--packages=.dart_tool/package_config.json",
                "integration_test/protocol_integration_test.dart",
            ],
            product,
        ),
        (
            [
                dart,
                "--packages=.dart_tool/package_config.json",
                "benchmark/release_evaluation.dart",
            ],
            product,
        ),
        (
            [
                dart,
                "--packages=.dart_tool/package_config.json",
                "../../tests/acceptance/vityo_coding_agent/"
                "protocol_release_acceptance_test.dart",
            ],
            product,
        ),
    )
    for command, cwd in commands:
        result = run(command, cwd)
        if result:
            return result
    return 0


def workspace_transactions() -> int:
    dart = tool("dart")
    product = ROOT / "products" / "vityo_app"
    commands = (
        ([sys.executable, "scripts/check_product_line_boundaries.py"], ROOT),
        ([sys.executable, "scripts/check_architecture_boundaries.py"], ROOT),
        ([dart, "analyze", "lib"], product),
        (
            [
                dart,
                "test",
                "test/workspace/workspace_transaction_service_test.dart",
            ],
            product,
        ),
        (
            [
                dart,
                "--packages=.dart_tool/package_config.json",
                "integration_test/standalone_smoke_test.dart",
            ],
            product,
        ),
        (
            [
                dart,
                "--packages=.dart_tool/package_config.json",
                "../../tests/acceptance/vityo_app/"
                "workspace_transactions_acceptance_test.dart",
            ],
            product,
        ),
    )
    for command, cwd in commands:
        result = run(command, cwd)
        if result:
            return result
    return 0


def developer_loop() -> int:
    dart = tool("dart")
    product = ROOT / "products" / "vityo_app"
    commands = (
        ([sys.executable, "scripts/check_product_line_boundaries.py"], ROOT),
        ([sys.executable, "scripts/check_architecture_boundaries.py"], ROOT),
        (
            [
                dart,
                "analyze",
                "lib/src/ide",
                "test/developer_loop",
                "integration_test/developer_loop_test.dart",
            ],
            product,
        ),
        (
            [
                dart,
                "test",
                "test/developer_loop/developer_loop_service_test.dart",
            ],
            product,
        ),
        (
            [
                dart,
                "--packages=.dart_tool/package_config.json",
                "integration_test/developer_loop_test.dart",
            ],
            product,
        ),
        (
            [
                dart,
                "--packages=.dart_tool/package_config.json",
                "../../tests/acceptance/vityo_app/"
                "developer_loop_acceptance_test.dart",
            ],
            product,
        ),
    )
    for command, cwd in commands:
        result = run(command, cwd)
        if result:
            return result
    return 0


def agent_client_protocol() -> int:
    dart = tool("dart")
    protocol = ROOT / "packages" / "vityo_agent_protocol"
    product = ROOT / "products" / "vityo_app"
    commands = (
        ([dart, "analyze"], protocol, None),
        ([dart, "test"], protocol, None),
        (
            [
                dart,
                "analyze",
                "lib/src/ide/agent_client",
                "test/agent_client",
                "integration_test/agent_client_protocol_test.dart",
            ],
            product,
            None,
        ),
        (
            [dart, "test", "test/agent_client/agent_client_contract_test.dart"],
            product,
            None,
        ),
        (
            [
                dart,
                "--packages=.dart_tool/package_config.json",
                "integration_test/agent_client_protocol_test.dart",
            ],
            product,
            None,
        ),
        (
            [
                dart,
                "--packages=.dart_tool/package_config.json",
                "../../tests/acceptance/vityo_app/"
                "agent_client_protocol_acceptance_test.dart",
            ],
            product,
            {
                **os.environ,
                "VITYO_ACCEPTANCE_PRIVATE": "present",
            },
        ),
    )
    for command, cwd, environment in commands:
        result = run(command, cwd, environment)
        if result:
            return result
    return 0


def mcp_host() -> int:
    dart = tool("dart")
    product = ROOT / "products" / "vityo_app"
    commands = (
        (
            [
                dart,
                "analyze",
                "lib/src/ide/agent_client/mcp",
                "lib/src/ide/agent_client/tools",
                "lib/src/ide/extensions",
                "test/mcp_host",
                "integration_test/mcp_host_test.dart",
            ],
            product,
        ),
        ([dart, "test", "test/mcp_host"], product),
        (
            [
                dart,
                "--packages=.dart_tool/package_config.json",
                "integration_test/mcp_host_test.dart",
            ],
            product,
        ),
        (
            [
                dart,
                "--packages=.dart_tool/package_config.json",
                "../../tests/acceptance/vityo_app/"
                "mcp_host_security_acceptance_test.dart",
            ],
            product,
        ),
    )
    for command, cwd in commands:
        result = run(command, cwd)
        if result:
            return result
    return 0


def ide_security() -> int:
    dart = tool("dart")
    product = ROOT / "products" / "vityo_app"
    commands = (
        (
            [
                dart,
                "analyze",
                "lib/src/ide/agent_client/mcp",
                "lib/src/ide/agent_client/tools",
                "test/mcp_host/mcp_host_security_test.dart",
            ],
            product,
        ),
        (
            [dart, "test", "test/mcp_host/mcp_host_security_test.dart"],
            product,
        ),
    )
    for command, cwd in commands:
        result = run(command, cwd)
        if result:
            return result
    return 0


def agent_workbench() -> int:
    dart = tool("dart")
    flutter = tool("flutter")
    product = ROOT / "products" / "vityo_app"
    commands = (
        (
            [
                flutter,
                "analyze",
                "lib/src/ide/workbench/agent_collaboration",
                "lib/src/presentation/agent_workbench",
                "test/agent_workbench",
                "integration_test/agent_workbench_test.dart",
            ],
            product,
        ),
        (
            [
                flutter,
                "test",
                "test/agent_workbench/agent_workbench_contract_test.dart",
            ],
            product,
        ),
        (
            [
                dart,
                "--packages=.dart_tool/package_config.json",
                "integration_test/agent_workbench_test.dart",
            ],
            product,
        ),
        (
            [
                flutter,
                "test",
                "../../tests/acceptance/vityo_app/"
                "agent_workbench_acceptance_test.dart",
            ],
            product,
        ),
    )
    for command, cwd in commands:
        result = run(command, cwd)
        if result:
            return result
    return 0


def ide_quality() -> int:
    dart = tool("dart")
    flutter = tool("flutter")
    product = ROOT / "products" / "vityo_app"
    commands = (
        (
            [
                flutter,
                "analyze",
                "lib/src/ide/agent_client",
                "lib/src/ide/platform",
                "lib/src/presentation/agent_workbench",
                "benchmark/agent_collaboration_benchmark.dart",
                "test/ide_quality",
                "integration_test/recovery_isolation_test.dart",
            ],
            product,
        ),
        ([flutter, "test", "test/ide_quality"], product),
        (
            [
                dart,
                "--packages=.dart_tool/package_config.json",
                "benchmark/agent_collaboration_benchmark.dart",
            ],
            product,
        ),
        (
            [
                dart,
                "--packages=.dart_tool/package_config.json",
                "integration_test/recovery_isolation_test.dart",
            ],
            product,
        ),
        (
            [
                sys.executable,
                "packaging/vityo/desktop_delivery.py",
                "--repo-root",
                ".",
            ],
            ROOT,
        ),
        (
            [
                flutter,
                "test",
                "../../tests/acceptance/vityo_app/"
                "quality_runtime_acceptance_test.dart",
            ],
            product,
        ),
        (
            [
                sys.executable,
                "tests/acceptance/vityo_app/"
                "quality_packaging_acceptance_test.py",
            ],
            ROOT,
        ),
    )
    for command, cwd in commands:
        result = run(command, cwd)
        if result:
            return result
    return 0


def full_suite_plan() -> list[dict[str, str]]:
    plan = [
        {
            "requirement": entry.requirement,
            "suite": entry.suite,
            "runner": entry.runner_name,
        }
        for entry in FULL_IDE_PLAN
    ]
    validate_full_suite_plan(plan)
    return plan


def _source_fingerprint(
    roots: tuple[str, ...] = _FINGERPRINT_ROOTS,
) -> str:
    digest = hashlib.sha256()
    for root_name in roots:
        root = ROOT / root_name
        if not root.exists():
            raise ValidationReceiptError(
                "source_path_missing",
                f"required validation path is missing: {root_name}",
            )
        entries = [root] if root.is_file() else sorted(root.rglob("*"))
        for entry in entries:
            relative = entry.relative_to(ROOT)
            if any(part in _IGNORED_DIRECTORIES for part in relative.parts):
                continue
            if not entry.is_file():
                continue
            digest.update(relative.as_posix().encode("utf-8"))
            digest.update(b"\0")
            with entry.open("rb") as handle:
                for chunk in iter(lambda: handle.read(1 << 20), b""):
                    digest.update(chunk)
            digest.update(b"\0")
    return digest.hexdigest()


def _head_commit() -> str:
    completed = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    commit = completed.stdout.strip().lower()
    if completed.returncode != 0 or len(commit) not in range(40, 65):
        raise ValidationReceiptError(
            "commit_unavailable",
            "full validation must be bound to a source commit",
        )
    return commit


def _host_platform() -> str:
    return {
        "win32": "windows",
        "darwin": "macos",
        "linux": "linux",
    }.get(sys.platform, sys.platform)


def _run_plan_validation() -> int:
    manifest_tool = ROOT.parent / "better-plan" / "scripts" / "manifest_tool.py"
    commands = (
        [sys.executable, str(manifest_tool), "validate", "docs/plan"],
        [sys.executable, str(manifest_tool), "check-labels", "docs/plan"],
    )
    for command in commands:
        result = run(command)
        if result:
            return result
    return 0


def ide_full(
    *,
    plan_only: bool,
    receipt_path: pathlib.Path,
) -> int:
    plan = full_suite_plan()
    if plan_only:
        print(
            json.dumps(
                {
                    "schema_version": 1,
                    "product": "vityo",
                    "suite": "full",
                    "mode": "plan_only",
                    "requirements": plan,
                    "final_checks": [
                        "better-plan/validate",
                        "better-plan/check-labels",
                    ],
                },
                indent=2,
                sort_keys=True,
            )
        )
        return 0

    start_fingerprint = _source_fingerprint()
    commit = _head_commit()
    outcomes: dict[str, dict[str, object]] = {}
    for entry in FULL_IDE_PLAN:
        started = time.monotonic()
        runner = globals()[entry.runner_name]
        try:
            exit_code = int(runner())
        except Exception:
            exit_code = 1
        outcomes[entry.requirement] = {
            "status": "passed" if exit_code == 0 else "failed",
            "suite": entry.suite,
            "duration_ms": max(
                0,
                round((time.monotonic() - started) * 1000),
            ),
        }

    plan_validation_exit = _run_plan_validation()
    if plan_validation_exit:
        outcomes["REQ-IDE-001"] = {
            **outcomes["REQ-IDE-001"],
            "status": "failed",
            "plan_validation": "failed",
        }
    end_fingerprint = _source_fingerprint()
    try:
        payload = build_ide_receipt(
            start_fingerprint=start_fingerprint,
            end_fingerprint=end_fingerprint,
            commit=commit,
            platform=_host_platform(),
            outcomes=outcomes,
        )
    except ValidationReceiptError as error:
        payload = {
            "schema_version": 1,
            "product": "vityo",
            "suite": "full",
            "status": "failed",
            "failure_code": error.code,
            "commit": commit,
            "platform": _host_platform(),
            "start_fingerprint": start_fingerprint,
            "end_fingerprint": end_fingerprint,
            "requirements": outcomes,
        }
    write_receipt_atomic(receipt_path, payload)
    return 0 if payload.get("status") == "passed" else 1


def coding_agent_full(*, receipt_path: pathlib.Path) -> int:
    try:
        return _coding_agent_full_inner(receipt_path=receipt_path)
    except Exception:
        payload = {
            "schema_version": 1,
            "product": "vityo_coding_agent",
            "suite": "full",
            "status": "failed",
            "failure_code": "validation_harness_failed",
            "requirements": {
                entry.requirement: {
                    "status": "failed",
                    "suite": entry.suite,
                    "duration_ms": 0,
                }
                for entry in FULL_AGENT_PLAN
            },
        }
        write_receipt_atomic(receipt_path, payload)
        return 1


def _coding_agent_full_inner(*, receipt_path: pathlib.Path) -> int:
    start_fingerprint = _source_fingerprint(_AGENT_FINGERPRINT_ROOTS)
    commit = _head_commit()
    outcomes: dict[str, dict[str, object]] = {}
    for entry in FULL_AGENT_PLAN:
        started = time.monotonic()
        runner = globals()[entry.runner_name]
        try:
            exit_code = int(runner())
        except Exception:
            exit_code = 1
        outcomes[entry.requirement] = {
            "status": "passed" if exit_code == 0 else "failed",
            "suite": entry.suite,
            "duration_ms": max(
                0,
                round((time.monotonic() - started) * 1000),
            ),
        }

    plan_validation_exit = _run_plan_validation()
    end_fingerprint = _source_fingerprint(_AGENT_FINGERPRINT_ROOTS)
    stable = start_fingerprint == end_fingerprint
    all_passed = all(
        outcome["status"] == "passed" for outcome in outcomes.values()
    )
    payload = {
        "schema_version": 1,
        "product": "vityo_coding_agent",
        "suite": "full",
        "status": (
            "passed"
            if all_passed and plan_validation_exit == 0 and stable
            else "failed"
        ),
        "commit": commit,
        "platform": _host_platform(),
        "start_fingerprint": start_fingerprint,
        "end_fingerprint": end_fingerprint,
        "requirements": outcomes,
        "plan_validation": (
            "passed" if plan_validation_exit == 0 else "failed"
        ),
        "protocol_schema_sha256": hashlib.sha256(
            (
                ROOT
                / "packages"
                / "vityo_agent_protocol"
                / "schema"
                / "acp-v1.schema.json"
            ).read_bytes()
        ).hexdigest(),
        "evaluation_manifest_sha256": hashlib.sha256(
            (
                ROOT
                / "products"
                / "vityo_coding_agent"
                / "fixtures"
                / "evaluation"
                / "manifest.json"
            ).read_bytes()
        ).hexdigest(),
    }
    write_receipt_atomic(receipt_path, payload)
    return 0 if payload["status"] == "passed" else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--product", required=True)
    parser.add_argument("--suite", required=True)
    parser.add_argument("--plan-only", action="store_true")
    parser.add_argument(
        "--receipt",
        type=pathlib.Path,
        default=None,
    )
    args = parser.parse_args()
    if args.plan_only and (args.product, args.suite) != ("ide", "full"):
        parser.error("--plan-only is supported only for ide/full")
    if (args.product, args.suite) == ("ide", "source-fingerprint"):
        print(_source_fingerprint())
        return 0
    if (args.product, args.suite) == ("ide", "cutover"):
        return cutover()
    if (args.product, args.suite) == ("coding-agent", "headless-runtime"):
        return headless_runtime()
    if (args.product, args.suite) == ("coding-agent", "providers"):
        return providers()
    if (args.product, args.suite) == ("coding-agent", "context"):
        return context_engine()
    if (args.product, args.suite) == ("coding-agent", "tools-mcp"):
        return tools_mcp()
    if (args.product, args.suite) == ("coding-agent", "agent-security"):
        return agent_security()
    if (args.product, args.suite) == ("coding-agent", "coding-loop"):
        return coding_loop()
    if (args.product, args.suite) == ("coding-agent", "session-recovery"):
        return session_recovery()
    if (args.product, args.suite) == ("coding-agent", "multi-agent"):
        return multi_agent()
    if (args.product, args.suite) == ("coding-agent", "protocol-integration"):
        return protocol_integration()
    if (args.product, args.suite) == ("coding-agent", "full"):
        receipt = args.receipt or (
            ROOT
            / "artifacts"
            / "validation"
            / "vityo-coding-agent-full.json"
        )
        return coding_agent_full(receipt_path=receipt.resolve())
    if (args.product, args.suite) == ("ide", "workspace-transactions"):
        return workspace_transactions()
    if (args.product, args.suite) == ("ide", "developer-loop"):
        return developer_loop()
    if (args.product, args.suite) == ("ide", "agent-client-protocol"):
        return agent_client_protocol()
    if (args.product, args.suite) == ("ide", "mcp-host"):
        return mcp_host()
    if (args.product, args.suite) == ("ide", "ide-security"):
        return ide_security()
    if (args.product, args.suite) == ("ide", "agent-workbench"):
        return agent_workbench()
    if (args.product, args.suite) == ("ide", "ide-quality"):
        return ide_quality()
    if (args.product, args.suite) == ("ide", "full"):
        receipt = args.receipt or (
            ROOT / "artifacts" / "validation" / "vityo-full.json"
        )
        return ide_full(
            plan_only=args.plan_only,
            receipt_path=receipt.resolve(),
        )
    parser.error(f"unsupported suite: {args.product}/{args.suite}")


if __name__ == "__main__":
    raise SystemExit(main())

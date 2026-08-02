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
from collections.abc import Mapping

_SCRIPTS_DIR = pathlib.Path(__file__).resolve().parent
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))

from vityo_validation_receipt import (
    SUPPORTED_HOST_PLATFORMS,
    ValidationReceiptError,
    build_ide_failure_receipt,
    build_ide_receipt,
    validate_full_suite_plan,
    write_receipt_atomic,
)


ROOT = _SCRIPTS_DIR.parent


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
    "packages/vityo_agent_protocol/schema",
    "tests/acceptance/vityo_app",
    "scripts",
    "packaging",
    ".github/workflows",
)
_PROTOCOL_SCHEMA_ROOT = "packages/vityo_agent_protocol/schema"
_ACCEPTANCE_FIXTURES_ROOT = "tests/acceptance/vityo_app"
_IDE_FULL_REQUIRED_TOOLS = ("dart", "flutter")
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
        ([flutter, "analyze", "--no-pub"], ROOT / "products" / "vityo_app"),
        ([flutter, "test", "--no-pub", "test/vityo_app_smoke_test.dart"],
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
                "--no-pub",
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
                "--no-pub",
                "test/agent_workbench",
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
                "--no-pub",
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
                "--no-pub",
                "lib/src/ide/agent_client",
                "lib/src/ide/platform",
                "lib/src/presentation/agent_workbench",
                "benchmark/agent_collaboration_benchmark.dart",
                "test/ide_quality",
                "integration_test/recovery_isolation_test.dart",
            ],
            product,
        ),
        # The formal REQ-IDE-008 lane owns the single platform-independent
        # full Flutter regression. Earlier suites remain focused and do not
        # duplicate this invocation.
        ([flutter, "test", "--no-pub"], product),
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
                "--no-pub",
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


def _digest_roots(roots: tuple[str, ...]) -> str:
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


def _source_fingerprint(
    roots: tuple[str, ...] = _FINGERPRINT_ROOTS,
) -> str:
    return _digest_roots(roots)


def _protocol_schema_digest() -> str:
    return _digest_roots((_PROTOCOL_SCHEMA_ROOT,))


def _acceptance_fixtures_digest() -> str:
    return _digest_roots((_ACCEPTANCE_FIXTURES_ROOT,))


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


def _source_tree_dirty(
    roots: tuple[str, ...] = _FINGERPRINT_ROOTS,
) -> bool:
    completed = subprocess.run(
        ["git", "status", "--porcelain", "--untracked-files=normal", "--", *roots],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        raise ValidationReceiptError(
            "dirty_candidate",
            "unable to determine whether source-bearing paths are clean",
        )
    return bool(completed.stdout.strip())


def _resolve_required_tools() -> None:
    for name in _IDE_FULL_REQUIRED_TOOLS:
        if shutil.which(name) is None:
            raise ValidationReceiptError(
                "tool_unavailable",
                f"required tool is not available on PATH: {name}",
            )


def _verify_fingerprint_inputs() -> None:
    for root_name in (
        *_FINGERPRINT_ROOTS,
        _PROTOCOL_SCHEMA_ROOT,
        _ACCEPTANCE_FIXTURES_ROOT,
    ):
        if not (ROOT / root_name).exists():
            raise ValidationReceiptError(
                "source_path_missing",
                f"required validation path is missing: {root_name}",
            )


def _receipt_destination_usable(destination: pathlib.Path) -> None:
    parent = destination.parent
    if not parent.exists() or not parent.is_dir():
        raise ValidationReceiptError(
            "receipt_destination_unavailable",
            "receipt destination parent is not an existing directory",
        )
    if not os.access(parent, os.W_OK | os.X_OK):
        raise ValidationReceiptError(
            "receipt_destination_unavailable",
            "receipt destination parent is not writable",
        )
    if destination.exists():
        if not destination.is_file():
            raise ValidationReceiptError(
                "receipt_destination_unavailable",
                "receipt destination exists and is not a replaceable file",
            )
        if not os.access(destination, os.W_OK):
            raise ValidationReceiptError(
                "receipt_destination_unavailable",
                "receipt destination is not writable",
            )


def _existing_duplicate_receipt(
    destination: pathlib.Path,
    *,
    commit: str,
    source_fingerprint: str,
) -> bool:
    if not destination.is_file():
        return False
    try:
        payload = json.loads(destination.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        return False
    if not isinstance(payload, dict):
        return False
    return (
        payload.get("commit") == commit
        and payload.get("source_fingerprint") == source_fingerprint
    )


def _placeholder_outcomes(
    failure_code: str,
) -> dict[str, dict[str, object]]:
    return {
        entry.requirement: {
            "status": "failed",
            "suite": entry.suite,
            "duration_ms": 0,
            "failure_code": failure_code,
        }
        for entry in FULL_IDE_PLAN
    }


def _print_json(payload: Mapping[str, object]) -> None:
    print(
        json.dumps(
            payload,
            indent=2,
            sort_keys=True,
            ensure_ascii=False,
        )
    )


def _preflight_ide_full(receipt_path: pathlib.Path) -> dict[str, object]:
    plan: list[dict[str, str]] = []
    checks: list[dict[str, object]] = []
    failure_code: str | None = None
    commit: str | None = None
    platform: str | None = None
    source_fingerprint: str | None = None
    protocol_digest: str | None = None
    fixtures_digest: str | None = None

    def record(name: str, action) -> None:
        nonlocal failure_code
        try:
            action()
            checks.append({"name": name, "status": "passed"})
        except ValidationReceiptError as error:
            checks.append(
                {
                    "name": name,
                    "status": "failed",
                    "failure_code": error.code,
                }
            )
            if failure_code is None:
                failure_code = error.code

    def check_requirement_mapping() -> None:
        nonlocal plan
        plan = full_suite_plan()

    def check_source_paths() -> None:
        _verify_fingerprint_inputs()

    def check_tools() -> None:
        _resolve_required_tools()

    def check_host() -> None:
        nonlocal platform
        platform = _host_platform()
        if platform not in SUPPORTED_HOST_PLATFORMS:
            raise ValidationReceiptError(
                "unsupported_host",
                "validation platform is unsupported",
            )

    def check_commit() -> None:
        nonlocal commit
        commit = _head_commit()
        if _source_tree_dirty():
            raise ValidationReceiptError(
                "dirty_candidate",
                "source-bearing paths differ from the candidate commit",
            )

    def check_digests() -> None:
        nonlocal source_fingerprint, protocol_digest, fixtures_digest
        source_fingerprint = _source_fingerprint()
        protocol_digest = _protocol_schema_digest()
        fixtures_digest = _acceptance_fixtures_digest()

    def check_duplicate() -> None:
        if commit is None or source_fingerprint is None:
            raise ValidationReceiptError(
                failure_code or "validation_harness_failed",
                "duplicate inspection requires commit and source fingerprint",
            )
        if _existing_duplicate_receipt(
            receipt_path,
            commit=commit,
            source_fingerprint=source_fingerprint,
        ):
            raise ValidationReceiptError(
                "duplicate_candidate_receipt",
                "destination already records this commit and fingerprint",
            )

    def check_destination() -> None:
        _receipt_destination_usable(receipt_path)

    record("requirement_mapping", check_requirement_mapping)
    record("source_paths", check_source_paths)
    record("tools", check_tools)
    record("host", check_host)
    record("commit", check_commit)
    record("digests", check_digests)
    record("duplicate_receipt", check_duplicate)
    record("receipt_destination", check_destination)

    if not plan:
        try:
            plan = [
                {
                    "requirement": entry.requirement,
                    "suite": entry.suite,
                    "runner": entry.runner_name,
                }
                for entry in FULL_IDE_PLAN
            ]
        except Exception:
            plan = []

    ready = failure_code is None
    report: dict[str, object] = {
        "schema_version": 1,
        "product": "vityo",
        "suite": "full",
        "mode": "preflight",
        "ready": ready,
        "requirements": plan,
        "checks": checks,
        "failure_code": failure_code,
        "commit": commit,
        "platform": platform,
        "source_fingerprint": source_fingerprint,
        "protocol_schema_sha256": protocol_digest,
        "acceptance_fixtures_sha256": fixtures_digest,
    }
    return report


def _write_formal_receipt(
    receipt_path: pathlib.Path,
    payload: Mapping[str, object],
) -> int:
    try:
        write_receipt_atomic(receipt_path, payload)
    except Exception:
        _print_json(
            {
                "schema_version": 1,
                "product": "vityo",
                "suite": "full",
                "status": "failed",
                "failure_code": "receipt_write_failed",
            }
        )
        return 1
    return 0 if payload.get("status") == "passed" else 1


def _ide_full_formal(receipt_path: pathlib.Path) -> int:
    preflight = _preflight_ide_full(receipt_path)
    if not preflight.get("ready"):
        failure_code = str(
            preflight.get("failure_code") or "validation_harness_failed"
        )
        payload = build_ide_failure_receipt(
            failure_code=failure_code,
            commit=preflight.get("commit"),
            platform=preflight.get("platform"),
            source_fingerprint=preflight.get("source_fingerprint"),
            protocol_schema_sha256=preflight.get("protocol_schema_sha256"),
            acceptance_fixtures_sha256=preflight.get(
                "acceptance_fixtures_sha256"
            ),
            outcomes=_placeholder_outcomes(failure_code),
        )
        if failure_code in {
            "duplicate_candidate_receipt",
            "receipt_destination_unavailable",
        }:
            _print_json(payload)
            return 1
        return _write_formal_receipt(receipt_path, payload)

    commit: str | None = None
    platform: str | None = None
    source_fingerprint: str | None = None
    protocol_digest: str | None = None
    fixtures_digest: str | None = None
    outcomes = _placeholder_outcomes("validation_harness_failed")
    suites_started = False
    try:
        validate_full_suite_plan(full_suite_plan())
        platform = _host_platform()
        if platform not in SUPPORTED_HOST_PLATFORMS:
            raise ValidationReceiptError(
                "unsupported_host",
                "validation platform is unsupported",
            )
        commit = _head_commit()
        source_fingerprint = _source_fingerprint()
        protocol_digest = _protocol_schema_digest()
        fixtures_digest = _acceptance_fixtures_digest()
        outcomes = {}
        suite_failed = False
        suites_started = True
        for entry in FULL_IDE_PLAN:
            started = time.monotonic()
            runner = globals()[entry.runner_name]
            try:
                exit_code = int(runner())
            except Exception:
                exit_code = 1
            duration_ms = max(
                0,
                round((time.monotonic() - started) * 1000),
            )
            if exit_code == 0:
                outcomes[entry.requirement] = {
                    "status": "passed",
                    "suite": entry.suite,
                    "duration_ms": duration_ms,
                }
            else:
                suite_failed = True
                outcomes[entry.requirement] = {
                    "status": "failed",
                    "suite": entry.suite,
                    "duration_ms": duration_ms,
                    "failure_code": "suite_failed",
                }
        end_fingerprint = _source_fingerprint()
        payload = build_ide_receipt(
            start_fingerprint=source_fingerprint,
            end_fingerprint=end_fingerprint,
            commit=commit,
            platform=platform,
            outcomes=outcomes,
            protocol_schema_sha256=protocol_digest,
            acceptance_fixtures_sha256=fixtures_digest,
            failure_code="suite_failed" if suite_failed else None,
        )
    except ValidationReceiptError as error:
        if not suites_started:
            outcomes = _placeholder_outcomes(error.code)
        payload = build_ide_failure_receipt(
            failure_code=error.code,
            commit=commit,
            platform=platform,
            source_fingerprint=source_fingerprint,
            protocol_schema_sha256=protocol_digest,
            acceptance_fixtures_sha256=fixtures_digest,
            outcomes=outcomes,
        )
    except Exception:
        if not suites_started:
            outcomes = _placeholder_outcomes("validation_harness_failed")
        payload = build_ide_failure_receipt(
            failure_code="validation_harness_failed",
            commit=commit,
            platform=platform,
            source_fingerprint=source_fingerprint,
            protocol_schema_sha256=protocol_digest,
            acceptance_fixtures_sha256=fixtures_digest,
            outcomes=outcomes,
        )
    return _write_formal_receipt(receipt_path, payload)


def ide_full(
    *,
    plan_only: bool,
    preflight: bool,
    receipt_path: pathlib.Path,
) -> int:
    if plan_only and preflight:
        raise ValueError("plan_only and preflight are mutually exclusive")
    plan = full_suite_plan()
    if plan_only:
        _print_json(
            {
                "schema_version": 1,
                "product": "vityo",
                "suite": "full",
                "mode": "plan_only",
                "requirements": plan,
            }
        )
        return 0
    if preflight:
        report = _preflight_ide_full(receipt_path)
        _print_json(report)
        return 0 if report.get("ready") else 1
    return _ide_full_formal(receipt_path)


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

    end_fingerprint = _source_fingerprint(_AGENT_FINGERPRINT_ROOTS)
    stable = start_fingerprint == end_fingerprint
    all_passed = all(
        outcome["status"] == "passed" for outcome in outcomes.values()
    )
    payload = {
        "schema_version": 1,
        "product": "vityo_coding_agent",
        "suite": "full",
        "status": "passed" if all_passed and stable else "failed",
        "commit": commit,
        "platform": _host_platform(),
        "start_fingerprint": start_fingerprint,
        "end_fingerprint": end_fingerprint,
        "requirements": outcomes,
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
    parser.add_argument("--preflight", action="store_true")
    parser.add_argument(
        "--receipt",
        type=pathlib.Path,
        default=None,
    )
    args = parser.parse_args()
    if args.plan_only and args.preflight:
        parser.error("--plan-only and --preflight are mutually exclusive")
    if args.plan_only and (args.product, args.suite) != ("ide", "full"):
        parser.error("--plan-only is supported only for ide/full")
    if args.preflight and (args.product, args.suite) != ("ide", "full"):
        parser.error("--preflight is supported only for ide/full")
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
            preflight=args.preflight,
            receipt_path=receipt.resolve(),
        )
    parser.error(f"unsupported suite: {args.product}/{args.suite}")


if __name__ == "__main__":
    raise SystemExit(main())

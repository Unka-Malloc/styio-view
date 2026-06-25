#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]

BENCHMARK_ROOT = Path("frontend/vityo_app/benchmark")
RUNNER_PATH = BENCHMARK_ROOT / "run_all_benchmarks.dart"
PERFORMANCE_GATE_PATH = Path("scripts/performance-gate.py")
REPO_HYGIENE_WORKFLOW_PATH = Path(".github/workflows/repo-hygiene.yml")
PERFORMANCE_TEST_PATH = Path("tests/test_performance_budgets.py")


@dataclass(frozen=True)
class BenchmarkSpec:
    alg_id: str
    name: str
    file_name: str
    runner_function: str
    markers: tuple[str, ...]

    @property
    def path(self) -> Path:
        return BENCHMARK_ROOT / self.file_name


BENCHMARK_SPECS: tuple[BenchmarkSpec, ...] = (
    BenchmarkSpec(
        alg_id="alg01_piece_table",
        name="piece table",
        file_name="alg01_piece_table_benchmark.dart",
        runner_function="runAlg01Benchmarks",
        markers=("100000", "line_starts_cached", "position_for_offset"),
    ),
    BenchmarkSpec(
        alg_id="alg02_line_index",
        name="line index",
        file_name="alg02_line_index_benchmark.dart",
        runner_function="runAlg02Benchmarks",
        markers=("offset_to_line_", "update_affected_range_"),
    ),
    BenchmarkSpec(
        alg_id="alg03_decorations",
        name="decorations/range",
        file_name="alg03_decorations_benchmark.dart",
        runner_function="runAlg03Benchmarks",
        markers=("RangeIndex", "diagnostics_viewport_query_100k_indexed"),
    ),
    BenchmarkSpec(
        alg_id="alg04_snapshots",
        name="snapshots",
        file_name="alg04_snapshots_benchmark.dart",
        runner_function="runAlg04Benchmarks",
        markers=("snapshot_creation_", "stale_detection_stale_content_"),
    ),
    BenchmarkSpec(
        alg_id="alg05_workspace_graph",
        name="project graph",
        file_name="alg05_workspace_graph_benchmark.dart",
        runner_function="runAlg05Benchmarks",
        markers=("build_packages_", "dependency_resolution_1000pkgs"),
    ),
    BenchmarkSpec(
        alg_id="alg06_language_cache",
        name="language cache",
        file_name="alg06_language_cache_benchmark.dart",
        runner_function="runAlg06Benchmarks",
        markers=("cache_hit_latency", "cache_invalidation_overhead"),
    ),
    BenchmarkSpec(
        alg_id="alg07_runtime_events",
        name="runtime events",
        file_name="alg07_runtime_events_benchmark.dart",
        runner_function="runAlg07Benchmarks",
        markers=("events_replay_", "graph_digest_recompute_"),
    ),
    BenchmarkSpec(
        alg_id="alg08_ai_context",
        name="AI context budget",
        file_name="alg08_ai_context_benchmark.dart",
        runner_function="runAlg08Benchmarks",
        markers=("AIContextBudget", "budget_clipping_"),
    ),
    BenchmarkSpec(
        alg_id="alg09_watcher",
        name="watcher",
        file_name="alg09_watcher_benchmark.dart",
        runner_function="runAlg09Benchmarks",
        markers=("burst_event_handling_", "overflow_detection_2000burst"),
    ),
    BenchmarkSpec(
        alg_id="alg10_virtualization",
        name="virtualization",
        file_name="alg10_virtualization_benchmark.dart",
        runner_function="runAlg10Benchmarks",
        markers=("visible_items_query_", "offset_for_index_"),
    ),
)


def read_required_text(repo_root: Path, relative_path: Path, errors: list[str]) -> str | None:
    path = repo_root / relative_path
    if not path.is_file():
        errors.append(f"missing required file: {relative_path.as_posix()}")
        return None
    return path.read_text(encoding="utf-8")


def check_benchmark_files(repo_root: Path) -> list[str]:
    errors: list[str] = []
    for spec in BENCHMARK_SPECS:
        text = read_required_text(repo_root, spec.path, errors)
        if text is None:
            continue
        for marker in spec.markers:
            if marker not in text:
                errors.append(f"{spec.path.as_posix()}: missing performance marker `{marker}`")
        if "BenchmarkRunner(" not in text:
            errors.append(f"{spec.path.as_posix()}: missing BenchmarkRunner coverage")
        if ".toJson()" not in text:
            errors.append(f"{spec.path.as_posix()}: benchmark results must be JSON-serializable")
    return errors


def check_benchmark_runner(repo_root: Path) -> list[str]:
    errors: list[str] = []
    text = read_required_text(repo_root, RUNNER_PATH, errors)
    if text is None:
        return errors
    for spec in BENCHMARK_SPECS:
        if f"import '{spec.file_name}';" not in text:
            errors.append(f"{RUNNER_PATH.as_posix()}: missing import for {spec.file_name}")
        if f"'{spec.alg_id}': {spec.runner_function}()" not in text:
            errors.append(
                f"{RUNNER_PATH.as_posix()}: missing runner registration for {spec.alg_id}"
            )
    for marker in ("JsonEncoder.withIndent", "benchmark_results.json", "'results': allResults"):
        if marker not in text:
            errors.append(f"{RUNNER_PATH.as_posix()}: missing runner marker `{marker}`")
    return errors


def check_performance_gate(repo_root: Path) -> list[str]:
    errors: list[str] = []
    text = read_required_text(repo_root, PERFORMANCE_GATE_PATH, errors)
    if text is None:
        return errors
    for spec in BENCHMARK_SPECS:
        if spec.alg_id not in text:
            errors.append(f"{PERFORMANCE_GATE_PATH.as_posix()}: missing benchmark id {spec.alg_id}")
        if spec.file_name not in text:
            errors.append(f"{PERFORMANCE_GATE_PATH.as_posix()}: missing benchmark file {spec.file_name}")
    required_markers = (
        r"\bp95Ms\b",
        r"\bthreshold\b",
        r"\bbaseline\b",
        r"\bcompare_results\b",
        r"\b_extract_json_payload\b",
        r"\b_run_benchmark_suite\b",
    )
    for marker in required_markers:
        if re.search(marker, text, re.I) is None:
            errors.append(
                f"{PERFORMANCE_GATE_PATH.as_posix()}: missing performance gate marker `{marker}`"
            )
    return errors


def check_static_gate_wiring(repo_root: Path) -> list[str]:
    errors: list[str] = []
    workflow = read_required_text(repo_root, REPO_HYGIENE_WORKFLOW_PATH, errors)
    if workflow is not None and "python3 scripts/check_performance_budgets.py" not in workflow:
        errors.append(
            f"{REPO_HYGIENE_WORKFLOW_PATH.as_posix()}: missing performance budget gate step"
        )

    test_text = read_required_text(repo_root, PERFORMANCE_TEST_PATH, errors)
    if test_text is not None:
        for marker in (
            "check_performance_budgets",
            "PerformanceBudgetGateTest",
            "subprocess",
        ):
            if marker not in test_text:
                errors.append(
                    f"{PERFORMANCE_TEST_PATH.as_posix()}: missing test coverage marker `{marker}`"
                )
    return errors


def check_performance_budgets(repo_root: Path | None = None) -> list[str]:
    root = repo_root or REPO_ROOT
    errors: list[str] = []
    errors.extend(check_benchmark_files(root))
    errors.extend(check_benchmark_runner(root))
    errors.extend(check_performance_gate(root))
    errors.extend(check_static_gate_wiring(root))
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Check Vityo performance budget coverage.")
    parser.add_argument("--json", action="store_true", help="Emit JSON.")
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    errors = check_performance_budgets(args.repo_root.resolve())
    if args.json:
        print(json.dumps({"ok": not errors, "errors": errors}, indent=2, sort_keys=True))
    elif errors:
        print("[performance-budgets] FAILED", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
    else:
        print("[performance-budgets] OK")
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())

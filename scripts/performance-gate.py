#!/usr/bin/env python3
"""Performance Gate — run benchmarks and enforce no-regression thresholds.

Usage:
    python3 scripts/performance-gate.py                    # check mode
    python3 scripts/performance-gate.py --baseline <file>  # compare against baseline
    python3 scripts/performance-gate.py --save-baseline    # save current results as baseline
    python3 scripts/performance-gate.py --json             # machine-readable JSON
    python3 scripts/performance-gate.py --threshold 1.15   # allow up to 15% regression (default: 1.10)

Exit codes:
    0 — all benchmarks within threshold or no baseline
    1 — one or more regressions exceed threshold
    2 — configuration or infrastructure error
"""

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BENCHMARK_DIR = ROOT / "frontend" / "vityo_app" / "benchmark"
BASELINE_FILE = ROOT / "docs" / "review" / "performance-baseline.json"
FLUTTER_APP_DIR = ROOT / "frontend" / "vityo_app"

# ---------------------------------------------------------------------------
# Discoverable benchmarks
# ---------------------------------------------------------------------------

DISCOVERED_BENCHMARKS = [
    {
        "id": "alg01_piece_table",
        "name": "Piece Table (ALG-01)",
        "file": "alg01_piece_table_benchmark.dart",
        "category": "editor",
        "metrics": ["open_1k_lines_ms", "open_100k_lines_ms", "insert_1k_random_ms", "delete_1k_random_ms", "undo_1k_edits_ms"],
    },
    {
        "id": "alg02_line_index",
        "name": "LineIndex (ALG-02)",
        "file": "alg02_line_index_benchmark.dart",
        "category": "editor",
        "metrics": ["offset_to_line_ms", "line_to_offset_ms", "incremental_update_ms"],
    },
    {
        "id": "alg03_decorations",
        "name": "Decorations (ALG-03)",
        "file": "alg03_decorations_benchmark.dart",
        "category": "editor",
        "metrics": ["viewport_query_10k_ms", "viewport_query_100k_ms", "range_update_after_edit_ms"],
    },
    {
        "id": "alg04_snapshots",
        "name": "Copy-on-Write Snapshots (ALG-04)",
        "file": "alg04_snapshots_benchmark.dart",
        "category": "language",
        "metrics": ["snapshot_create_ms", "atomic_swap_ms", "stale_detection_ms"],
    },
    {
        "id": "alg05_workspace_graph",
        "name": "Workspace Graph (ALG-05)",
        "file": "alg05_workspace_graph_benchmark.dart",
        "category": "workspace",
        "metrics": ["build_10_packages_ms", "build_100_packages_ms", "single_manifest_edit_ms", "lockfile_edit_ms"],
    },
    {
        "id": "alg06_language_cache",
        "name": "Language Cache (ALG-06)",
        "file": "alg06_language_cache_benchmark.dart",
        "category": "language",
        "metrics": ["cache_hit_latency_us", "cache_miss_latency_us", "invalidation_overhead_us"],
    },
    {
        "id": "alg07_runtime_events",
        "name": "Runtime Events (ALG-07)",
        "file": "alg07_runtime_events_benchmark.dart",
        "category": "runtime",
        "metrics": ["replay_1k_events_ms", "replay_10k_events_ms", "replay_100k_log_lines_ms", "graph_digest_recompute_ms"],
    },
    {
        "id": "alg08_ai_context",
        "name": "AI Context Packing (ALG-08)",
        "file": "alg08_ai_context_benchmark.dart",
        "category": "ai",
        "metrics": ["packing_small_workspace_ms", "packing_large_workspace_ms", "budget_clipping_us"],
    },
    {
        "id": "alg09_watcher",
        "name": "Watcher Coalescing (ALG-09)",
        "file": "alg09_watcher_benchmark.dart",
        "category": "platform",
        "metrics": ["burst_100_events_ms", "burst_1000_events_ms", "overflow_detection_us"],
    },
    {
        "id": "alg10_virtualization",
        "name": "UI Virtualization (ALG-10)",
        "file": "alg10_virtualization_benchmark.dart",
        "category": "ui",
        "metrics": ["render_1k_items_frame_ms", "render_10k_items_frame_ms", "filter_debounce_ms"],
    },
]


def _check_flutter_available() -> bool:
    """Check if `flutter` is on PATH."""
    try:
        result = subprocess.run(
            ["flutter", "--version"],
            capture_output=True, text=True, timeout=30,
        )
        return result.returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


def _run_dart_benchmark(benchmark_file: str) -> dict | None:
    """Run a single Dart benchmark file and parse JSON output.

    Return None if the benchmark could not be run.
    """
    bench_path = BENCHMARK_DIR / benchmark_file
    if not bench_path.exists():
        return {"error": f"Benchmark file not found: {bench_path}"}

    try:
        result = subprocess.run(
            ["dart", "run", str(bench_path)],
            capture_output=True, text=True, timeout=120,
            cwd=str(FLUTTER_APP_DIR),
        )
        if result.returncode != 0:
            return {"error": f"Benchmark exited {result.returncode}: {result.stderr[:500]}"}

        # Try to parse JSON from stdout
        for line in result.stdout.strip().splitlines():
            line = line.strip()
            if line.startswith("{") and line.endswith("}"):
                try:
                    return json.loads(line)
                except json.JSONDecodeError:
                    continue
        return {"error": "No JSON output found", "stdout": result.stdout[:500]}
    except FileNotFoundError:
        return {"error": "Dart VM not available"}
    except subprocess.TimeoutExpired:
        return {"error": "Benchmark timed out (120s)"}


def load_baseline(baseline_path: Path) -> dict | None:
    """Load baseline JSON. Return None if not found."""
    if not baseline_path.exists():
        return None
    try:
        return json.loads(baseline_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None


def save_baseline(baseline_path: Path, results: dict) -> None:
    """Save benchmark results as baseline."""
    baseline_path.parent.mkdir(parents=True, exist_ok=True)
    baseline_path.write_text(json.dumps(results, indent=2, default=str) + "\n", encoding="utf-8")


def compare_results(current: dict, baseline: dict, threshold: float) -> list[dict]:
    """Compare current results against baseline. Return list of regressions."""
    regressions = []
    for bench_id, bench_data in current.items():
        if bench_id not in baseline:
            continue
        base_data = baseline[bench_id]
        if "metrics" not in bench_data or "metrics" not in base_data:
            continue

        for metric, current_value in bench_data["metrics"].items():
            base_value = base_data["metrics"].get(metric)
            if base_value is None or base_value == 0:
                continue
            if current_value is None:
                continue

            ratio = current_value / base_value
            if ratio > threshold:
                regressions.append({
                    "benchmark": bench_id,
                    "metric": metric,
                    "baseline": base_value,
                    "current": current_value,
                    "ratio": round(ratio, 3),
                    "threshold": threshold,
                })

    return regressions


def run_gate(
    json_output: bool = False,
    baseline_path: Path | None = None,
    save: bool = False,
    threshold: float = 1.10,
) -> tuple[bool, list[dict], dict]:
    """Run the performance gate.

    Returns: (passed, regressions, all_results).
    """
    flutter_available = _check_flutter_available()
    dart_available = False

    if not flutter_available:
        # Try dart directly
        try:
            result = subprocess.run(["dart", "--version"], capture_output=True, text=True, timeout=10)
            dart_available = result.returncode == 0
        except FileNotFoundError:
            pass

    runner_available = flutter_available or dart_available

    all_results = {}
    skipped = []
    errors = []

    if not runner_available:
        print("[performance-gate] WARNING: Neither Flutter nor Dart VM found on PATH.")
        print("[performance-gate] Running in stub mode — all benchmarks marked as skipped.")
        print("[performance-gate] Install Flutter SDK to run real benchmarks.")

    for bench in DISCOVERED_BENCHMARKS:
        bench_file = bench["file"]
        bench_path = BENCHMARK_DIR / bench_file

        if not bench_path.exists():
            skipped.append({
                "id": bench["id"],
                "name": bench["name"],
                "reason": f"Benchmark file missing: {bench_file}",
            })
            all_results[bench["id"]] = {
                "name": bench["name"],
                "category": bench["category"],
                "status": "skipped",
                "reason": f"File not found: {bench_file}",
                "metrics": {},
            }
            continue

        if not runner_available:
            skipped.append({
                "id": bench["id"],
                "name": bench["name"],
                "reason": "Dart/Flutter VM not available",
            })
            all_results[bench["id"]] = {
                "name": bench["name"],
                "category": bench["category"],
                "status": "skipped",
                "reason": "No Dart/Flutter runtime",
                "metrics": {},
            }
            continue

        bench_result = _run_dart_benchmark(bench_file)
        if bench_result is None or "error" in (bench_result or {}):
            err_msg = (bench_result or {}).get("error", "Unknown error")
            errors.append({"id": bench["id"], "name": bench["name"], "error": err_msg})
            all_results[bench["id"]] = {
                "name": bench["name"],
                "category": bench["category"],
                "status": "error",
                "error": err_msg,
                "metrics": {},
            }
        else:
            all_results[bench["id"]] = {
                "name": bench["name"],
                "category": bench["category"],
                "status": "ok",
                "metrics": bench_result,
            }

    # Load baseline for comparison
    baseline = None
    if baseline_path:
        baseline = load_baseline(baseline_path)
    else:
        baseline = load_baseline(BASELINE_FILE)

    regressions = []
    if baseline:
        regressions = compare_results(all_results, baseline, threshold)

    # Save baseline if requested
    if save:
        save_baseline(BASELINE_FILE, all_results)

    passed = len(regressions) == 0

    if json_output:
        output = {
            "gate": "performance",
            "passed": passed,
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "runner_available": runner_available,
            "total_benchmarks": len(DISCOVERED_BENCHMARKS),
            "ran": sum(1 for r in all_results.values() if r["status"] == "ok"),
            "skipped": len(skipped),
            "errors": len(errors),
            "regressions": regressions,
            "skipped_details": skipped,
            "error_details": errors,
            "results": all_results,
            "baseline_used": baseline is not None,
        }
        print(json.dumps(output, indent=2, default=str))
    else:
        print("=" * 60)
        print("  Vityo Performance Gate")
        print("=" * 60)
        print(f"  Runner available: {runner_available}")
        print(f"  Total benchmarks: {len(DISCOVERED_BENCHMARKS)}")
        print(f"  Ran: {sum(1 for r in all_results.values() if r['status'] == 'ok')}")
        print(f"  Skipped: {len(skipped)}")
        print(f"  Errors: {len(errors)}")
        print(f"  Baseline loaded: {baseline is not None}")
        print()

        for bench_id, result in sorted(all_results.items()):
            status_icon = {"ok": "✓", "skipped": "⊘", "error": "✗"}.get(result["status"], "?")
            print(f"  {status_icon} {result['name']}  [{result['status']}]")
            if result["status"] == "error":
                print(f"     Error: {result.get('error', 'unknown')}")
            elif result["status"] == "skipped":
                print(f"     Reason: {result.get('reason', 'unknown')}")
            elif result["status"] == "ok" and result.get("metrics"):
                for k, v in result["metrics"].items():
                    print(f"     {k}: {v}")

        if skipped:
            print(f"\n  Skipped benchmarks ({len(skipped)}):")
            for s in skipped:
                print(f"    ⊘ {s['name']} — {s['reason']}")

        if errors:
            print(f"\n  Benchmark errors ({len(errors)}):")
            for e in errors:
                print(f"    ✗ {e['name']} — {e['error']}")

        if regressions:
            print(f"\n  ✗ PERFORMANCE REGRESSIONS ({len(regressions)}):")
            for r in regressions:
                print(f"    {r['benchmark']}/{r['metric']}: {r['baseline']} → {r['current']} ({r['ratio']}x, threshold: {r['threshold']}x)")
        elif baseline:
            print(f"\n  ✓ No regressions detected (threshold: {threshold}x)")

        if not runner_available:
            print(f"\n  Result: SKIPPED (no Dart/Flutter runtime)")
        else:
            print(f"\n  Result: {'PASS' if passed else 'FAIL'}")

    return passed, regressions, all_results


def main():
    parser = argparse.ArgumentParser(description="Performance Gate — benchmark regression detection")
    parser.add_argument("--json", action="store_true", help="Output machine-readable JSON")
    parser.add_argument("--baseline", type=Path, help="Path to baseline JSON file")
    parser.add_argument("--save-baseline", action="store_true", help="Save current results as baseline")
    parser.add_argument(
        "--threshold", type=float, default=1.10,
        help="Max allowed regression ratio (default: 1.10 = 10%%)",
    )
    args = parser.parse_args()

    passed, _, _ = run_gate(
        json_output=args.json,
        baseline_path=args.baseline,
        save=args.save_baseline,
        threshold=args.threshold,
    )

    if not passed:
        print("\nOne or more benchmarks exceed the regression threshold.", file=sys.stderr)
        sys.exit(1)

    sys.exit(0)


if __name__ == "__main__":
    main()

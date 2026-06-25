#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import io
import json
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[1]
BUDGET_GATE_PATH = REPO_ROOT / "scripts" / "check_performance_budgets.py"
PERFORMANCE_GATE_PATH = REPO_ROOT / "scripts" / "performance-gate.py"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class PerformanceBudgetGateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.gate = load_module("check_performance_budgets", BUDGET_GATE_PATH)

    def _benchmark_text(self, spec) -> str:
        marker_lines = "\n".join(f"// {marker}" for marker in spec.markers)
        return (
            f"/// {spec.alg_id}\n"
            f"{marker_lines}\n"
            "void main() {\n"
            "  final r = BenchmarkRunner('sample').run(1, (_) {});\n"
            "  r.toJson();\n"
            "}\n"
        )

    def _write_minimal_performance_tree(self, root: Path) -> None:
        for spec in self.gate.BENCHMARK_SPECS:
            write(root / spec.path, self._benchmark_text(spec))

        imports = "\n".join(
            f"import '{spec.file_name}';" for spec in self.gate.BENCHMARK_SPECS
        )
        registrations = "\n".join(
            f"    '{spec.alg_id}': {spec.runner_function}(),"
            for spec in self.gate.BENCHMARK_SPECS
        )
        write(
            root / self.gate.RUNNER_PATH,
            f"{imports}\n"
            "void main() {\n"
            "  final allResults = <String, Object>{\n"
            f"{registrations}\n"
            "  };\n"
            "  final output = JsonEncoder.withIndent('  ').convert({'results': allResults});\n"
            "  File('benchmark_results.json').writeAsStringSync(output);\n"
            "}\n",
        )

        benchmark_ids = "\n".join(spec.alg_id for spec in self.gate.BENCHMARK_SPECS)
        benchmark_files = "\n".join(spec.file_name for spec in self.gate.BENCHMARK_SPECS)
        write(
            root / self.gate.PERFORMANCE_GATE_PATH,
            "def _extract_json_payload(): pass\n"
            "def _run_benchmark_suite(): pass\n"
            "def compare_results(): pass\n"
            "# p95Ms threshold baseline\n"
            f"{benchmark_ids}\n"
            f"{benchmark_files}\n",
        )
        write(
            root / self.gate.REPO_HYGIENE_WORKFLOW_PATH,
            "run: python3 scripts/check_performance_budgets.py\n",
        )
        write(
            root / self.gate.PERFORMANCE_TEST_PATH,
            "PerformanceBudgetGateTest\ncheck_performance_budgets\nsubprocess\n",
        )

    def test_accepts_complete_static_performance_budget_tree(self) -> None:
        with tempfile.TemporaryDirectory(prefix="performance-budget-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            self._write_minimal_performance_tree(root)

            errors = self.gate.check_performance_budgets(root)

        self.assertEqual(errors, [])

    def test_reports_missing_benchmark_marker(self) -> None:
        with tempfile.TemporaryDirectory(prefix="performance-budget-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            self._write_minimal_performance_tree(root)
            spec = self.gate.BENCHMARK_SPECS[0]
            write(root / spec.path, "BenchmarkRunner('sample');\nr.toJson();\n")

            errors = self.gate.check_performance_budgets(root)

        joined = "\n".join(errors)
        self.assertIn("missing performance marker", joined)
        self.assertIn(spec.path.as_posix(), joined)

    def test_reports_missing_aggregate_runner_registration(self) -> None:
        with tempfile.TemporaryDirectory(prefix="performance-budget-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            self._write_minimal_performance_tree(root)
            runner = root / self.gate.RUNNER_PATH
            text = runner.read_text(encoding="utf-8")
            runner.write_text(
                text.replace("    'alg10_virtualization': runAlg10Benchmarks(),\n", ""),
                encoding="utf-8",
            )

            errors = self.gate.check_performance_budgets(root)

        self.assertTrue(
            any("missing runner registration for alg10_virtualization" in error for error in errors),
            errors,
        )

    def test_cli_json_is_static_and_does_not_call_subprocess(self) -> None:
        with tempfile.TemporaryDirectory(prefix="performance-budget-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            self._write_minimal_performance_tree(root)
            output = io.StringIO()

            with mock.patch.object(subprocess, "run", side_effect=AssertionError("no subprocess")):
                with redirect_stdout(output):
                    code = self.gate.main(["--repo-root", str(root), "--json"])

        payload = json.loads(output.getvalue())
        self.assertEqual(code, 0)
        self.assertTrue(payload["ok"])
        self.assertFalse(hasattr(self.gate, "subprocess"))


class PerformanceGateRunnerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.gate = load_module("performance_gate", PERFORMANCE_GATE_PATH)

    def test_extract_json_payload_accepts_pretty_runner_output(self) -> None:
        payload = self.gate._extract_json_payload(
            "Vityo Nightly Benchmark Suite\n"
            "{\n"
            '  "results": {"alg01_piece_table": []}\n'
            "}\n"
            "Results written to benchmark_results.json\n"
        )

        self.assertEqual(payload, {"results": {"alg01_piece_table": []}})

    def test_suite_metrics_normalize_result_lists_to_p95_metrics(self) -> None:
        payload = {
            "results": {
                "alg01_piece_table": [
                    {
                        "name": "open_document_100000lines",
                        "iterations": 50,
                        "meanMs": 8.0,
                        "p95Ms": 12.5,
                        "p99Ms": 13.0,
                        "maxMs": 14.0,
                    }
                ]
            }
        }

        metrics = self.gate._suite_metrics_by_benchmark(payload)

        self.assertEqual(
            metrics["alg01_piece_table"]["open_document_100000lines.p95Ms"],
            12.5,
        )
        self.assertNotIn("open_document_100000lines.iterations", metrics["alg01_piece_table"])

    def test_run_benchmark_suite_uses_dart_runner_and_embedded_json(self) -> None:
        with tempfile.TemporaryDirectory(prefix="performance-runner-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            app = root / "frontend/vityo_app"
            runner = app / "benchmark/run_all_benchmarks.dart"
            write(runner, "// runner\n")
            stdout = (
                "Vityo Nightly Benchmark Suite\n"
                + json.dumps(
                    {
                        "results": {
                            "alg01_piece_table": [
                                {
                                    "name": "open_document_100000lines",
                                    "p95Ms": 12.5,
                                    "meanMs": 8.0,
                                }
                            ]
                        }
                    },
                    indent=2,
                )
                + "\nResults written to benchmark_results.json\n"
            )
            completed = subprocess.CompletedProcess([], 0, stdout=stdout, stderr="")
            originals = (
                self.gate.BENCHMARK_RUNNER,
                self.gate.FLUTTER_APP_DIR,
                self.gate.BENCHMARK_RUNNER_RELATIVE,
            )
            self.gate.BENCHMARK_RUNNER = runner
            self.gate.FLUTTER_APP_DIR = app
            self.gate.BENCHMARK_RUNNER_RELATIVE = Path("benchmark/run_all_benchmarks.dart")
            try:
                with mock.patch.object(self.gate.subprocess, "run", return_value=completed) as run:
                    result = self.gate._run_benchmark_suite()
            finally:
                (
                    self.gate.BENCHMARK_RUNNER,
                    self.gate.FLUTTER_APP_DIR,
                    self.gate.BENCHMARK_RUNNER_RELATIVE,
                ) = originals

        self.assertEqual(
            result,
            {
                "alg01_piece_table": {
                    "open_document_100000lines.p95Ms": 12.5,
                    "open_document_100000lines.meanMs": 8.0,
                }
            },
        )
        run.assert_called_once_with(
            ["dart", "run", "benchmark/run_all_benchmarks.dart"],
            capture_output=True,
            text=True,
            timeout=300,
            cwd=str(app),
        )

    def test_run_gate_skips_without_dart_runtime(self) -> None:
        with mock.patch.object(self.gate, "_check_flutter_available", return_value=False):
            with mock.patch.object(self.gate, "_check_dart_available", return_value=False):
                with mock.patch.object(self.gate, "_run_benchmark_suite", side_effect=AssertionError):
                    output = io.StringIO()
                    warnings = io.StringIO()
                    with redirect_stdout(output), redirect_stderr(warnings):
                        passed, regressions, results = self.gate.run_gate(json_output=True)

        payload = json.loads(output.getvalue())
        self.assertTrue(passed)
        self.assertTrue(payload["passed"])
        self.assertEqual(regressions, [])
        self.assertTrue(results)
        self.assertTrue(all(result["status"] == "skipped" for result in results.values()))
        self.assertIn("Dart VM not found", warnings.getvalue())


if __name__ == "__main__":
    unittest.main()

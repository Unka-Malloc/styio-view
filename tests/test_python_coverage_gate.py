#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import io
import runpy
import sys
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[1]
GATE_PATH = REPO_ROOT / "scripts" / "python-coverage-gate.py"


def load_gate_module():
    spec = importlib.util.spec_from_file_location("python_coverage_gate", GATE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {GATE_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class PythonCoverageGateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.gate = load_gate_module()

    def test_coverage_available_checks_module_version(self) -> None:
        with mock.patch.object(self.gate.subprocess, "run") as run:
            run.return_value.returncode = 0
            self.assertTrue(self.gate.coverage_available())
            run.return_value.returncode = 1
            self.assertFalse(self.gate.coverage_available())

        command = run.call_args.args[0]
        self.assertEqual(command[:3], [sys.executable, "-m", "coverage"])

    def test_run_gate_reports_missing_coverage_dependency(self) -> None:
        with mock.patch.object(self.gate, "coverage_available", return_value=False):
            stderr = io.StringIO()
            with redirect_stderr(stderr):
                code = self.gate.run_gate(95)

        self.assertEqual(code, 2)
        self.assertIn("coverage.py is required", stderr.getvalue())

    def test_run_command_returns_subprocess_exit_code(self) -> None:
        with mock.patch.object(self.gate.subprocess, "run") as run:
            run.return_value.returncode = 13
            self.assertEqual(self.gate.run_command(["coverage", "erase"]), 13)

        run.assert_called_once_with(["coverage", "erase"], cwd=self.gate.ROOT, check=False)

    def test_run_gate_runs_erase_test_and_report_commands(self) -> None:
        commands: list[list[str]] = []

        def fake_run(command: list[str]) -> int:
            commands.append(command)
            return 0

        with mock.patch.object(self.gate, "coverage_available", return_value=True):
            with mock.patch.object(self.gate, "run_command", side_effect=fake_run):
                self.assertEqual(self.gate.run_gate(97), 0)

        self.assertEqual(commands[0], [sys.executable, "-m", "coverage", "erase"])
        # coverage run command may include --omit flags for gate infrastructure scripts
        run_cmd = commands[1]
        self.assertEqual(run_cmd[0], sys.executable)
        self.assertIn("-m", run_cmd)
        self.assertIn("coverage", run_cmd)
        self.assertIn("run", run_cmd)
        self.assertIn("--source", run_cmd)
        self.assertIn(self.gate.SOURCE_SCOPE, run_cmd)
        self.assertIn("-m", run_cmd[run_cmd.index("--source") + 2:])  # -m unittest after source+scope
        self.assertIn("unittest", run_cmd)
        self.assertIn("tests.test_linux_host_readiness_gate", run_cmd)
        self.assertIn("tests.test_linux_packaging_gate", run_cmd)
        self.assertIn("prototype.test_dev_server_security", run_cmd)
        self.assertEqual(commands[2][-2:], ["--fail-under", "97"])

    def test_run_gate_stops_on_first_failing_command(self) -> None:
        with mock.patch.object(self.gate, "coverage_available", return_value=True):
            with mock.patch.object(self.gate, "run_command", side_effect=[0, 4, 0]) as run:
                self.assertEqual(self.gate.run_gate(95), 4)

        self.assertEqual(run.call_count, 2)

    def test_main_uses_fail_under_argument(self) -> None:
        with mock.patch.object(self.gate, "run_gate", return_value=0) as run_gate:
            self.assertEqual(self.gate.main(["--fail-under", "96"]), 0)

        run_gate.assert_called_once_with(96)

    def test_script_entrypoint_exits_with_main_result(self) -> None:
        with mock.patch.object(sys, "argv", [str(GATE_PATH), "--fail-under", "99"]):
            with mock.patch("subprocess.run") as run:
                run.return_value.returncode = 0
                with self.assertRaises(SystemExit) as raised:
                    runpy.run_path(str(GATE_PATH), run_name="__main__")

        self.assertEqual(raised.exception.code, 0)


if __name__ == "__main__":
    unittest.main()

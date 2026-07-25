from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "scripts" / "run-native-pty-matrix.py"


def load_module():
    spec = importlib.util.spec_from_file_location("run_native_pty_matrix", SCRIPT_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class NativePtyMatrixTest(unittest.TestCase):
    def test_matrix_runs_real_pty_and_terminal_environment_suites(self) -> None:
        module = load_module()
        with (
            mock.patch.object(module.shutil, "which", return_value="flutter") as which,
            mock.patch.object(module.subprocess, "run") as run,
        ):
            module.run_matrix(flutter="flutter", app_root=Path("app"))

        which.assert_called_once_with("flutter")
        self.assertEqual(run.call_count, 2)
        self.assertIn("test/pty_manager_test.dart", run.call_args_list[0].args[0])
        self.assertIn("--plain-name", run.call_args_list[1].args[0])
        for call in run.call_args_list:
            self.assertTrue(call.kwargs["check"])

    def test_report_is_platform_bound_and_complete(self) -> None:
        module = load_module()
        report = module.build_report(platform="macos", vityo_commit="v" * 40)

        self.assertEqual(report["provider"], "forkpty")
        self.assertEqual(report["ptyDependency"], {"name": "pty2", "version": "0.5.2"})
        self.assertEqual(
            {scenario["id"] for scenario in report["scenarios"]},
            set(module.SCENARIOS),
        )
        self.assertTrue(all(scenario["status"] == "passed" for scenario in report["scenarios"]))

    def test_dependency_must_remain_exactly_pinned(self) -> None:
        module = load_module()
        with mock.patch.object(
            Path,
            "read_text",
            return_value="dependencies:\n  pty2: ^0.5.2\n",
        ):
            with self.assertRaisesRegex(ValueError, "pinned exactly"):
                module.require_pinned_pty_dependency(Path("app"))


if __name__ == "__main__":
    unittest.main()

from __future__ import annotations

import importlib.util
import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
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
    def test_host_platform_normalizes_supported_hosts(self) -> None:
        module = load_module()
        for raw, expected in (
            ("linux", "linux"),
            ("linux2", "linux"),
            ("darwin", "macos"),
            ("win32", "windows"),
            ("other", None),
        ):
            with self.subTest(platform=raw):
                with mock.patch.object(module.sys, "platform", raw):
                    self.assertEqual(module.host_platform(), expected)

    def test_git_head_reads_repository_commit(self) -> None:
        module = load_module()
        completed = mock.Mock(stdout=("a" * 40) + "\n")
        with mock.patch.object(
            module.subprocess,
            "run",
            return_value=completed,
        ) as run:
            self.assertEqual(module.git_head(Path("repo")), "a" * 40)

        run.assert_called_once_with(
            ["git", "-C", "repo", "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        )

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

    def test_matrix_rejects_missing_flutter(self) -> None:
        module = load_module()
        with mock.patch.object(module.shutil, "which", return_value=None):
            with self.assertRaisesRegex(ValueError, "unavailable"):
                module.run_matrix(
                    flutter="missing-flutter",
                    app_root=Path("app"),
                )

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

    def test_main_writes_commit_bound_report(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory(
            prefix="native-pty-matrix-",
        ) as tmp_name:
            output = Path(tmp_name) / "nested" / "report.json"
            stdout = io.StringIO()
            with (
                mock.patch.object(
                    sys,
                    "argv",
                    [
                        str(SCRIPT_PATH),
                        "--platform",
                        "macos",
                        "--vityo",
                        str(REPO_ROOT),
                        "--output",
                        str(output),
                    ],
                ),
                mock.patch.object(
                    module,
                    "host_platform",
                    return_value="macos",
                ),
                mock.patch.object(
                    module,
                    "require_pinned_pty_dependency",
                ) as require,
                mock.patch.object(module, "run_matrix") as run_matrix,
                mock.patch.object(
                    module,
                    "git_head",
                    return_value="a" * 40,
                ),
                redirect_stdout(stdout),
            ):
                self.assertEqual(module.main(), 0)

            payload = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(payload["vityoCommit"], "a" * 40)
            self.assertEqual(json.loads(stdout.getvalue()), payload)
            app_root = REPO_ROOT / "products" / "vityo_app"
            require.assert_called_once_with(app_root)
            run_matrix.assert_called_once_with(
                flutter="flutter",
                app_root=app_root,
            )

    def test_main_rejects_declared_platform_mismatch(self) -> None:
        module = load_module()
        with (
            mock.patch.object(
                sys,
                "argv",
                [
                    str(SCRIPT_PATH),
                    "--platform",
                    "windows",
                    "--output",
                    "unused.json",
                ],
            ),
            mock.patch.object(
                module,
                "host_platform",
                return_value="linux",
            ),
            redirect_stderr(io.StringIO()),
        ):
            with self.assertRaises(SystemExit):
                module.main()


if __name__ == "__main__":
    unittest.main()

from __future__ import annotations

import importlib.util
import io
import json
import sys
import tempfile
import unittest
from contextlib import ExitStack, redirect_stderr, redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "scripts" / "vityo_quality.py"
SCRIPTS_PATH = str(SCRIPT_PATH.parent)
if SCRIPTS_PATH not in sys.path:
    sys.path.insert(0, SCRIPTS_PATH)


def load_module():
    spec = importlib.util.spec_from_file_location(
        "vityo_quality_test_target",
        SCRIPT_PATH,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {SCRIPT_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class VityoQualityTest(unittest.TestCase):
    suite_runners = (
        "cutover",
        "headless_runtime",
        "providers",
        "context_engine",
        "tools_mcp",
        "agent_security",
        "coding_loop",
        "session_recovery",
        "multi_agent",
        "protocol_integration",
        "workspace_transactions",
        "developer_loop",
        "agent_client_protocol",
        "mcp_host",
        "ide_security",
        "agent_workbench",
        "ide_quality",
    )

    def setUp(self) -> None:
        self.quality = load_module()

    def test_tool_and_run_are_fail_closed(self) -> None:
        with mock.patch.object(
            self.quality.shutil,
            "which",
            return_value="/tools/dart",
        ):
            self.assertEqual(self.quality.tool("dart"), "/tools/dart")

        with mock.patch.object(self.quality.shutil, "which", return_value=None):
            with self.assertRaisesRegex(RuntimeError, "required tool"):
                self.quality.tool("missing")

        completed = SimpleNamespace(returncode=7)
        environment = {"VITYO_TEST": "1"}
        stdout = io.StringIO()
        with mock.patch.object(
            self.quality.subprocess,
            "run",
            return_value=completed,
        ) as run:
            with redirect_stdout(stdout):
                code = self.quality.run(
                    ["dart", "test"],
                    self.quality.ROOT,
                    environment,
                )

        self.assertEqual(code, 7)
        self.assertIn("[vityo-quality] .: dart test", stdout.getvalue())
        run.assert_called_once_with(
            ["dart", "test"],
            cwd=self.quality.ROOT,
            check=False,
            env=environment,
        )

    def test_all_focused_suite_runners_execute_and_stop_on_failure(self) -> None:
        for name in self.suite_runners:
            runner = getattr(self.quality, name)
            with self.subTest(runner=name, outcome="success"):
                with mock.patch.object(
                    self.quality,
                    "tool",
                    side_effect=lambda tool_name: f"/tools/{tool_name}",
                ):
                    with mock.patch.object(
                        self.quality,
                        "run",
                        return_value=0,
                    ) as run:
                        self.assertEqual(runner(), 0)
                self.assertGreater(run.call_count, 0)

            with self.subTest(runner=name, outcome="failure"):
                with mock.patch.object(
                    self.quality,
                    "tool",
                    side_effect=lambda tool_name: f"/tools/{tool_name}",
                ):
                    with mock.patch.object(
                        self.quality,
                        "run",
                        return_value=9,
                    ) as run:
                        self.assertEqual(runner(), 9)
                self.assertEqual(run.call_count, 1)

    def test_source_fingerprint_is_bounded_and_deterministic(self) -> None:
        with tempfile.TemporaryDirectory(prefix="vityo-quality-") as tmp_name:
            root = Path(tmp_name)
            single = root / "single.txt"
            tree = root / "tree"
            ignored = tree / "build"
            single.write_text("single\n", encoding="utf-8")
            tree.mkdir()
            (tree / "data.txt").write_text("data\n", encoding="utf-8")
            (tree / "empty").mkdir()
            ignored.mkdir()
            (ignored / "generated.txt").write_text(
                "ignored-one\n",
                encoding="utf-8",
            )

            original_root = self.quality.ROOT
            self.quality.ROOT = root
            try:
                first = self.quality._source_fingerprint(
                    ("single.txt", "tree"),
                )
                (ignored / "generated.txt").write_text(
                    "ignored-two\n",
                    encoding="utf-8",
                )
                self.assertEqual(
                    self.quality._source_fingerprint(
                        ("single.txt", "tree"),
                    ),
                    first,
                )
                (tree / "data.txt").write_text(
                    "changed\n",
                    encoding="utf-8",
                )
                self.assertNotEqual(
                    self.quality._source_fingerprint(
                        ("single.txt", "tree"),
                    ),
                    first,
                )
                with self.assertRaisesRegex(
                    self.quality.ValidationReceiptError,
                    "source_path_missing",
                ):
                    self.quality._source_fingerprint(("missing",))
            finally:
                self.quality.ROOT = original_root

        self.assertRegex(first, r"^[0-9a-f]{64}$")

    def test_commit_platform_and_plan_validation_helpers(self) -> None:
        completed = SimpleNamespace(
            returncode=0,
            stdout=("A" * 40) + "\n",
        )
        with mock.patch.object(
            self.quality.subprocess,
            "run",
            return_value=completed,
        ):
            self.assertEqual(self.quality._head_commit(), "a" * 40)

        for completed in (
            SimpleNamespace(returncode=1, stdout=""),
            SimpleNamespace(returncode=0, stdout="short\n"),
        ):
            with self.subTest(completed=completed):
                with mock.patch.object(
                    self.quality.subprocess,
                    "run",
                    return_value=completed,
                ):
                    with self.assertRaisesRegex(
                        self.quality.ValidationReceiptError,
                        "commit_unavailable",
                    ):
                        self.quality._head_commit()

        for raw, expected in (
            ("win32", "windows"),
            ("darwin", "macos"),
            ("linux", "linux"),
            ("other", "other"),
        ):
            with self.subTest(platform=raw):
                with mock.patch.object(self.quality.sys, "platform", raw):
                    self.assertEqual(
                        self.quality._host_platform(),
                        expected,
                    )

        with mock.patch.object(
            self.quality,
            "run",
            side_effect=(0, 0),
        ) as run:
            self.assertEqual(self.quality._run_plan_validation(), 0)
            self.assertEqual(run.call_count, 2)
        with mock.patch.object(
            self.quality,
            "run",
            return_value=4,
        ) as run:
            self.assertEqual(self.quality._run_plan_validation(), 4)
            self.assertEqual(run.call_count, 1)

    def test_ide_full_plan_and_receipt_outcomes(self) -> None:
        plan = self.quality.full_suite_plan()
        self.assertEqual(
            [entry["requirement"] for entry in plan],
            [f"REQ-IDE-{index:03d}" for index in range(1, 9)],
        )

        stdout = io.StringIO()
        with redirect_stdout(stdout):
            self.assertEqual(
                self.quality.ide_full(
                    plan_only=True,
                    receipt_path=Path("unused.json"),
                ),
                0,
            )
        self.assertEqual(
            json.loads(stdout.getvalue())["mode"],
            "plan_only",
        )

        written: list[dict[str, object]] = []
        with ExitStack() as stack:
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "_source_fingerprint",
                    side_effect=("a" * 64, "a" * 64),
                )
            )
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "_head_commit",
                    return_value="b" * 40,
                )
            )
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "_host_platform",
                    return_value="linux",
                )
            )
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "_run_plan_validation",
                    return_value=0,
                )
            )
            for entry in self.quality.FULL_IDE_PLAN:
                stack.enter_context(
                    mock.patch.object(
                        self.quality,
                        entry.runner_name,
                        return_value=0,
                    )
                )
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "write_receipt_atomic",
                    side_effect=lambda _path, payload: written.append(
                        dict(payload)
                    ),
                )
            )
            self.assertEqual(
                self.quality.ide_full(
                    plan_only=False,
                    receipt_path=Path("passed.json"),
                ),
                0,
            )
        self.assertEqual(written[0]["status"], "passed")

        written.clear()
        with ExitStack() as stack:
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "_source_fingerprint",
                    side_effect=("a" * 64, "a" * 64),
                )
            )
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "_head_commit",
                    return_value="b" * 40,
                )
            )
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "_host_platform",
                    return_value="linux",
                )
            )
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "_run_plan_validation",
                    return_value=3,
                )
            )
            for index, entry in enumerate(self.quality.FULL_IDE_PLAN):
                stack.enter_context(
                    mock.patch.object(
                        self.quality,
                        entry.runner_name,
                        side_effect=(
                            RuntimeError("synthetic failure")
                            if index == 0
                            else None
                        ),
                        return_value=0,
                    )
                )
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "write_receipt_atomic",
                    side_effect=lambda _path, payload: written.append(
                        dict(payload)
                    ),
                )
            )
            self.assertEqual(
                self.quality.ide_full(
                    plan_only=False,
                    receipt_path=Path("failed.json"),
                ),
                1,
            )
        self.assertEqual(written[0]["status"], "failed")
        self.assertEqual(
            written[0]["requirements"]["REQ-IDE-001"][
                "plan_validation"
            ],
            "failed",
        )

    def test_ide_full_serializes_schema_failure_without_raw_exception(self) -> None:
        written: list[dict[str, object]] = []
        with ExitStack() as stack:
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "_source_fingerprint",
                    side_effect=("a" * 64, "c" * 64),
                )
            )
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "_head_commit",
                    return_value="b" * 40,
                )
            )
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "_host_platform",
                    return_value="linux",
                )
            )
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "_run_plan_validation",
                    return_value=0,
                )
            )
            for entry in self.quality.FULL_IDE_PLAN:
                stack.enter_context(
                    mock.patch.object(
                        self.quality,
                        entry.runner_name,
                        return_value=0,
                    )
                )
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "write_receipt_atomic",
                    side_effect=lambda _path, payload: written.append(
                        dict(payload)
                    ),
                )
            )
            self.assertEqual(
                self.quality.ide_full(
                    plan_only=False,
                    receipt_path=Path("failed.json"),
                ),
                1,
            )

        self.assertEqual(
            written[0]["failure_code"],
            "source_fingerprint_drift",
        )
        self.assertNotIn("message", written[0])

    def test_coding_agent_full_success_failure_and_harness_failure(self) -> None:
        written: list[dict[str, object]] = []
        with ExitStack() as stack:
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "_source_fingerprint",
                    side_effect=("a" * 64, "a" * 64),
                )
            )
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "_head_commit",
                    return_value="b" * 40,
                )
            )
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "_host_platform",
                    return_value="linux",
                )
            )
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "_run_plan_validation",
                    return_value=0,
                )
            )
            for entry in self.quality.FULL_AGENT_PLAN:
                stack.enter_context(
                    mock.patch.object(
                        self.quality,
                        entry.runner_name,
                        return_value=0,
                    )
                )
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "write_receipt_atomic",
                    side_effect=lambda _path, payload: written.append(
                        dict(payload)
                    ),
                )
            )
            self.assertEqual(
                self.quality.coding_agent_full(
                    receipt_path=Path("passed.json"),
                ),
                0,
            )
        self.assertEqual(written[0]["status"], "passed")

        written.clear()
        with ExitStack() as stack:
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "_source_fingerprint",
                    side_effect=("a" * 64, "c" * 64),
                )
            )
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "_head_commit",
                    return_value="b" * 40,
                )
            )
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "_host_platform",
                    return_value="linux",
                )
            )
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "_run_plan_validation",
                    return_value=2,
                )
            )
            for index, entry in enumerate(self.quality.FULL_AGENT_PLAN):
                stack.enter_context(
                    mock.patch.object(
                        self.quality,
                        entry.runner_name,
                        side_effect=(
                            RuntimeError("synthetic failure")
                            if index == 0
                            else None
                        ),
                        return_value=0,
                    )
                )
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "write_receipt_atomic",
                    side_effect=lambda _path, payload: written.append(
                        dict(payload)
                    ),
                )
            )
            self.assertEqual(
                self.quality.coding_agent_full(
                    receipt_path=Path("failed.json"),
                ),
                1,
            )
        self.assertEqual(written[0]["status"], "failed")

        written.clear()
        with mock.patch.object(
            self.quality,
            "_coding_agent_full_inner",
            side_effect=RuntimeError("synthetic harness failure"),
        ):
            with mock.patch.object(
                self.quality,
                "write_receipt_atomic",
                side_effect=lambda _path, payload: written.append(
                    dict(payload)
                ),
            ):
                self.assertEqual(
                    self.quality.coding_agent_full(
                        receipt_path=Path("harness-failed.json"),
                    ),
                    1,
                )
        self.assertEqual(
            written[0]["failure_code"],
            "validation_harness_failed",
        )

    def test_main_routes_every_supported_suite_and_rejects_unknowns(self) -> None:
        routes = (
            ("ide", "cutover", "cutover"),
            ("coding-agent", "headless-runtime", "headless_runtime"),
            ("coding-agent", "providers", "providers"),
            ("coding-agent", "context", "context_engine"),
            ("coding-agent", "tools-mcp", "tools_mcp"),
            ("coding-agent", "agent-security", "agent_security"),
            ("coding-agent", "coding-loop", "coding_loop"),
            ("coding-agent", "session-recovery", "session_recovery"),
            ("coding-agent", "multi-agent", "multi_agent"),
            (
                "coding-agent",
                "protocol-integration",
                "protocol_integration",
            ),
            ("coding-agent", "full", "coding_agent_full"),
            ("ide", "workspace-transactions", "workspace_transactions"),
            ("ide", "developer-loop", "developer_loop"),
            ("ide", "agent-client-protocol", "agent_client_protocol"),
            ("ide", "mcp-host", "mcp_host"),
            ("ide", "ide-security", "ide_security"),
            ("ide", "agent-workbench", "agent_workbench"),
            ("ide", "ide-quality", "ide_quality"),
            ("ide", "full", "ide_full"),
        )
        for product, suite, target in routes:
            with self.subTest(product=product, suite=suite):
                with mock.patch.object(
                    self.quality,
                    target,
                    return_value=0,
                ) as routed:
                    with mock.patch.object(
                        sys,
                        "argv",
                        [
                            str(SCRIPT_PATH),
                            "--product",
                            product,
                            "--suite",
                            suite,
                        ],
                    ):
                        self.assertEqual(self.quality.main(), 0)
                routed.assert_called_once()

        stdout = io.StringIO()
        with mock.patch.object(
            self.quality,
            "_source_fingerprint",
            return_value="a" * 64,
        ):
            with mock.patch.object(
                sys,
                "argv",
                [
                    str(SCRIPT_PATH),
                    "--product",
                    "ide",
                    "--suite",
                    "source-fingerprint",
                ],
            ):
                with redirect_stdout(stdout):
                    self.assertEqual(self.quality.main(), 0)
        self.assertEqual(stdout.getvalue().strip(), "a" * 64)

        for args in (
            (
                "--product",
                "coding-agent",
                "--suite",
                "full",
                "--plan-only",
            ),
            ("--product", "ide", "--suite", "unknown"),
        ):
            with self.subTest(args=args):
                with mock.patch.object(
                    sys,
                    "argv",
                    [str(SCRIPT_PATH), *args],
                ):
                    with redirect_stderr(io.StringIO()):
                        with self.assertRaises(SystemExit):
                            self.quality.main()


if __name__ == "__main__":
    unittest.main()

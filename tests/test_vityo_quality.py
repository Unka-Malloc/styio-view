"""Focused unit freeze for IDE full-harness readiness seams.

Adjacent to acceptance_paths because injectable runners, missing tools, early
harness failure, source drift, and receipt-destination failures cannot be
oracled safely through a real suite subprocess. Never invokes bare ide/full.
"""

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

    def test_formal_quality_lane_owns_one_complete_flutter_test(self) -> None:
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
                self.assertEqual(self.quality.ide_quality(), 0)

        commands = [call.args[0] for call in run.call_args_list]
        self.assertIn(["/tools/flutter", "test", "--no-pub"], commands)
        self.assertNotIn(
            ["/tools/flutter", "test", "test/ide_quality"],
            commands,
        )

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
                self.assertEqual(self.quality.agent_workbench(), 0)
        commands = [call.args[0] for call in run.call_args_list]
        self.assertIn(
            ["/tools/flutter", "test", "--no-pub", "test/agent_workbench"],
            commands,
        )

    def test_source_fingerprint_binds_fixtures_and_is_deterministic(self) -> None:
        roots = self.quality._FINGERPRINT_ROOTS
        self.assertIn("tests/acceptance/vityo_app", roots)
        self.assertIn("packages/vityo_agent_protocol/schema", roots)

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

    def test_commit_and_platform_helpers(self) -> None:
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

        self.assertFalse(hasattr(self.quality, "_run_plan_validation"))

    def _patch_formal_success(self, stack: ExitStack, *, written: list) -> None:
        self._patch_preflight_ready(stack)
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
                "_protocol_schema_digest",
                return_value="d" * 64,
            )
        )
        stack.enter_context(
            mock.patch.object(
                self.quality,
                "_acceptance_fixtures_digest",
                return_value="e" * 64,
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
                side_effect=lambda _path, payload: written.append(dict(payload)),
            )
        )

    def _patch_preflight_ready(self, stack: ExitStack) -> None:
        stack.enter_context(
            mock.patch.object(
                self.quality,
                "_preflight_ide_full",
                return_value={
                    "ready": True,
                    "failure_code": None,
                    "commit": "b" * 40,
                    "platform": "linux",
                    "source_fingerprint": "a" * 64,
                    "protocol_schema_sha256": "d" * 64,
                    "acceptance_fixtures_sha256": "e" * 64,
                },
            )
        )

    def test_ide_full_plan_only_and_preflight_never_call_runners(self) -> None:
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
                    preflight=False,
                    receipt_path=Path("unused.json"),
                ),
                0,
            )
        self.assertEqual(json.loads(stdout.getvalue())["mode"], "plan_only")

        runner_mocks = []
        with ExitStack() as stack:
            for entry in self.quality.FULL_IDE_PLAN:
                runner_mocks.append(
                    stack.enter_context(
                        mock.patch.object(
                            self.quality,
                            entry.runner_name,
                            return_value=0,
                        )
                    )
                )
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "write_receipt_atomic",
                    side_effect=AssertionError("preflight must not write"),
                )
            )
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "_preflight_ide_full",
                    return_value={
                        "schema_version": 1,
                        "product": "vityo",
                        "suite": "full",
                        "mode": "preflight",
                        "ready": True,
                        "requirements": plan,
                        "checks": [
                            {"name": name, "status": "passed"}
                            for name in (
                                "requirement_mapping",
                                "source_paths",
                                "tools",
                                "host",
                                "commit",
                                "digests",
                                "duplicate_receipt",
                                "receipt_destination",
                            )
                        ],
                        "failure_code": None,
                    },
                )
            )
            stdout = io.StringIO()
            with redirect_stdout(stdout):
                self.assertEqual(
                    self.quality.ide_full(
                        plan_only=False,
                        preflight=True,
                        receipt_path=Path("unused.json"),
                    ),
                    0,
                )
        payload = json.loads(stdout.getvalue())
        self.assertEqual(payload["mode"], "preflight")
        self.assertTrue(payload["ready"])
        for runner in runner_mocks:
            runner.assert_not_called()

    def test_preflight_reports_stable_failures_without_runners(self) -> None:
        cases = (
            "tool_unavailable",
            "source_path_missing",
            "invalid_requirement_mapping",
            "unsupported_host",
            "dirty_candidate",
            "duplicate_candidate_receipt",
            "receipt_destination_unavailable",
        )
        for code in cases:
            with self.subTest(code=code):
                runner_mocks = []
                with ExitStack() as stack:
                    for entry in self.quality.FULL_IDE_PLAN:
                        runner_mocks.append(
                            stack.enter_context(
                                mock.patch.object(
                                    self.quality,
                                    entry.runner_name,
                                    return_value=0,
                                )
                            )
                        )
                    stack.enter_context(
                        mock.patch.object(
                            self.quality,
                            "_preflight_ide_full",
                            return_value={
                                "schema_version": 1,
                                "product": "vityo",
                                "suite": "full",
                                "mode": "preflight",
                                "ready": False,
                                "requirements": self.quality.full_suite_plan(),
                                "checks": [
                                    {
                                        "name": "tools",
                                        "status": "failed",
                                        "failure_code": code,
                                    }
                                ],
                                "failure_code": code,
                            },
                        )
                    )
                    stdout = io.StringIO()
                    with redirect_stdout(stdout):
                        self.assertEqual(
                            self.quality.ide_full(
                                plan_only=False,
                                preflight=True,
                                receipt_path=Path("unused.json"),
                            ),
                            1,
                        )
                payload = json.loads(stdout.getvalue())
                self.assertFalse(payload["ready"])
                self.assertEqual(payload["failure_code"], code)
                for runner in runner_mocks:
                    runner.assert_not_called()

    def test_preflight_executes_all_checks_and_keeps_first_failure(self) -> None:
        commit = "b" * 40
        fingerprint = "a" * 64
        protocol_digest = "d" * 64
        fixtures_digest = "e" * 64

        def run_preflight(
            receipt: Path,
            *,
            source_paths_error=None,
            tools_error=None,
        ):
            patches = {
                "_verify_fingerprint_inputs": (
                    {"side_effect": source_paths_error}
                    if source_paths_error
                    else {}
                ),
                "_resolve_required_tools": (
                    {"side_effect": tools_error} if tools_error else {}
                ),
                "_host_platform": {"return_value": "linux"},
                "_head_commit": {"return_value": commit},
                "_source_tree_dirty": {"return_value": False},
                "_source_fingerprint": {"return_value": fingerprint},
                "_protocol_schema_digest": {
                    "return_value": protocol_digest,
                },
                "_acceptance_fixtures_digest": {
                    "return_value": fixtures_digest,
                },
            }
            with ExitStack() as stack:
                mocks = {
                    name: stack.enter_context(
                        mock.patch.object(self.quality, name, **configuration)
                    )
                    for name, configuration in patches.items()
                }
                report = self.quality._preflight_ide_full(receipt)
            return report, mocks

        with tempfile.TemporaryDirectory(prefix="vityo-preflight-") as tmp_name:
            receipt = Path(tmp_name) / "receipt.json"
            report, checks = run_preflight(receipt)

            self.assertTrue(report["ready"])
            self.assertIsNone(report["failure_code"])
            self.assertEqual(report["commit"], commit)
            self.assertEqual(report["platform"], "linux")
            self.assertEqual(report["source_fingerprint"], fingerprint)
            self.assertEqual(report["protocol_schema_sha256"], protocol_digest)
            self.assertEqual(
                report["acceptance_fixtures_sha256"],
                fixtures_digest,
            )
            self.assertEqual(
                [check["status"] for check in report["checks"]],
                ["passed"] * 8,
            )
            checks["_verify_fingerprint_inputs"].assert_called_once_with()
            checks["_resolve_required_tools"].assert_called_once_with()

            failed, _ = run_preflight(
                receipt,
                source_paths_error=self.quality.ValidationReceiptError(
                    "source_path_missing",
                    "synthetic",
                ),
                tools_error=self.quality.ValidationReceiptError(
                    "tool_unavailable",
                    "synthetic",
                ),
            )
            self.assertFalse(failed["ready"])
            self.assertEqual(failed["failure_code"], "source_path_missing")
            failed_checks = {
                check["name"]: check for check in failed["checks"]
            }
            self.assertEqual(
                failed_checks["source_paths"]["failure_code"],
                "source_path_missing",
            )
            self.assertEqual(
                failed_checks["tools"]["failure_code"],
                "tool_unavailable",
            )
            self.assertEqual(
                failed_checks["duplicate_receipt"]["status"],
                "passed",
            )

    def test_formal_full_refuses_failed_preflight_before_any_suite(self) -> None:
        written: list[dict[str, object]] = []
        runner_mocks = []
        with ExitStack() as stack:
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "_preflight_ide_full",
                    return_value={
                        "ready": False,
                        "failure_code": "dirty_candidate",
                        "commit": "b" * 40,
                        "platform": "linux",
                        "source_fingerprint": "a" * 64,
                        "protocol_schema_sha256": "d" * 64,
                        "acceptance_fixtures_sha256": "e" * 64,
                    },
                )
            )
            for entry in self.quality.FULL_IDE_PLAN:
                runner_mocks.append(
                    stack.enter_context(
                        mock.patch.object(
                            self.quality,
                            entry.runner_name,
                            return_value=0,
                        )
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
                    preflight=False,
                    receipt_path=Path("dirty.json"),
                ),
                1,
            )

        self.assertEqual(written[0]["failure_code"], "dirty_candidate")
        for runner in runner_mocks:
            runner.assert_not_called()

    def test_formal_duplicate_preflight_preserves_existing_receipt(self) -> None:
        with ExitStack() as stack:
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "_preflight_ide_full",
                    return_value={
                        "ready": False,
                        "failure_code": "duplicate_candidate_receipt",
                        "commit": "b" * 40,
                        "platform": "linux",
                        "source_fingerprint": "a" * 64,
                        "protocol_schema_sha256": "d" * 64,
                        "acceptance_fixtures_sha256": "e" * 64,
                    },
                )
            )
            writer = stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "write_receipt_atomic",
                )
            )
            stdout = io.StringIO()
            with redirect_stdout(stdout):
                self.assertEqual(
                    self.quality.ide_full(
                        plan_only=False,
                        preflight=False,
                        receipt_path=Path("existing.json"),
                    ),
                    1,
                )

        writer.assert_not_called()
        self.assertEqual(
            json.loads(stdout.getvalue())["failure_code"],
            "duplicate_candidate_receipt",
        )

    def test_formal_full_success_writes_complete_receipt(self) -> None:
        written: list[dict[str, object]] = []
        with ExitStack() as stack:
            self._patch_formal_success(stack, written=written)
            self.assertEqual(
                self.quality.ide_full(
                    plan_only=False,
                    preflight=False,
                    receipt_path=Path("passed.json"),
                ),
                0,
            )
        payload = written[0]
        self.assertEqual(payload["status"], "passed")
        self.assertEqual(payload["protocol_schema_sha256"], "d" * 64)
        self.assertEqual(payload["acceptance_fixtures_sha256"], "e" * 64)
        self.assertEqual(
            tuple(payload["requirements"]),
            tuple(f"REQ-IDE-{index:03d}" for index in range(1, 9)),
        )

    def test_suite_failure_keeps_eight_receipt_slots(self) -> None:
        for fail_index in (0, 3, 7):
            with self.subTest(fail_index=fail_index):
                written: list[dict[str, object]] = []
                with ExitStack() as stack:
                    self._patch_preflight_ready(stack)
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
                            "_protocol_schema_digest",
                            return_value="d" * 64,
                        )
                    )
                    stack.enter_context(
                        mock.patch.object(
                            self.quality,
                            "_acceptance_fixtures_digest",
                            return_value="e" * 64,
                        )
                    )
                    for index, entry in enumerate(self.quality.FULL_IDE_PLAN):
                        stack.enter_context(
                            mock.patch.object(
                                self.quality,
                                entry.runner_name,
                                return_value=1 if index == fail_index else 0,
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
                            preflight=False,
                            receipt_path=Path("failed.json"),
                        ),
                        1,
                    )
                payload = written[0]
                self.assertEqual(payload["status"], "failed")
                self.assertEqual(payload.get("failure_code"), "suite_failed")
                self.assertEqual(len(payload["requirements"]), 8)
                failed_key = f"REQ-IDE-{fail_index + 1:03d}"
                self.assertEqual(
                    payload["requirements"][failed_key]["status"],
                    "failed",
                )

    def test_early_harness_failure_writes_validation_harness_failed(self) -> None:
        written: list[dict[str, object]] = []
        with ExitStack() as stack:
            self._patch_preflight_ready(stack)
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "_source_fingerprint",
                    side_effect=RuntimeError("synthetic early failure"),
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
                    "write_receipt_atomic",
                    side_effect=lambda _path, payload: written.append(
                        dict(payload)
                    ),
                )
            )
            self.assertEqual(
                self.quality.ide_full(
                    plan_only=False,
                    preflight=False,
                    receipt_path=Path("harness-failed.json"),
                ),
                1,
            )
        payload = written[0]
        self.assertEqual(payload["failure_code"], "validation_harness_failed")
        self.assertEqual(len(payload["requirements"]), 8)
        encoded = json.dumps(payload)
        self.assertNotIn("synthetic early failure", encoded)
        self.assertNotIn("Traceback", encoded)

    def test_source_drift_writes_failed_receipt(self) -> None:
        written: list[dict[str, object]] = []
        with ExitStack() as stack:
            self._patch_preflight_ready(stack)
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
                    "_protocol_schema_digest",
                    return_value="d" * 64,
                )
            )
            stack.enter_context(
                mock.patch.object(
                    self.quality,
                    "_acceptance_fixtures_digest",
                    return_value="e" * 64,
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
                    preflight=False,
                    receipt_path=Path("drift.json"),
                ),
                1,
            )
        self.assertEqual(written[0]["failure_code"], "source_fingerprint_drift")
        self.assertEqual(len(written[0]["requirements"]), 8)

    def test_receipt_write_failure_leaves_no_partial_file(self) -> None:
        with tempfile.TemporaryDirectory(prefix="vityo-receipt-") as tmp_name:
            destination = Path(tmp_name) / "ide-full.json"
            with ExitStack() as stack:
                self._patch_formal_success(stack, written=[])
                stack.enter_context(
                    mock.patch.object(
                        self.quality,
                        "write_receipt_atomic",
                        side_effect=OSError("synthetic replace failure"),
                    )
                )
                stdout = io.StringIO()
                with redirect_stdout(stdout):
                    code = self.quality.ide_full(
                        plan_only=False,
                        preflight=False,
                        receipt_path=destination,
                    )
            self.assertEqual(code, 1)
            envelope = json.loads(stdout.getvalue())
            self.assertEqual(
                envelope["failure_code"],
                "receipt_write_failed",
            )
            self.assertFalse(destination.exists())
            self.assertEqual(list(destination.parent.glob(".*.tmp")), [])
            self.assertNotIn("synthetic replace failure", stdout.getvalue())

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

        with mock.patch.object(
            self.quality,
            "ide_full",
            return_value=0,
        ) as routed:
            with mock.patch.object(
                sys,
                "argv",
                [
                    str(SCRIPT_PATH),
                    "--product",
                    "ide",
                    "--suite",
                    "full",
                    "--preflight",
                ],
            ):
                self.assertEqual(self.quality.main(), 0)
        routed.assert_called_once()
        self.assertTrue(routed.call_args.kwargs.get("preflight"))

        for args in (
            (
                "--product",
                "coding-agent",
                "--suite",
                "full",
                "--plan-only",
            ),
            (
                "--product",
                "ide",
                "--suite",
                "full",
                "--plan-only",
                "--preflight",
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

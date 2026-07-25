#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[1]
GATE_PATH = REPO_ROOT / "scripts" / "ecosystem-product-gate.py"


def load_gate_module():
    spec = importlib.util.spec_from_file_location("ecosystem_product_gate", GATE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {GATE_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class EcosystemProductGateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.gate = load_gate_module()

    def test_missing_real_matrix_is_loud_but_skippable_locally(self) -> None:
        output = io.StringIO()
        with mock.patch.dict("os.environ", {}, clear=True), redirect_stdout(output):
            code = self.gate.main(["--json"])

        payload = json.loads(output.getvalue())
        self.assertEqual(code, 0)
        self.assertFalse(payload["ok"])
        self.assertTrue(payload["skipped"])
        self.assertFalse(payload["required"])
        self.assertEqual(payload["report"]["scenario_count"], 0)

    def test_missing_real_matrix_fails_closed_when_required(self) -> None:
        output = io.StringIO()
        with mock.patch.dict("os.environ", {}, clear=True), redirect_stdout(output):
            code = self.gate.main(["--require-real-matrix", "--json"])

        payload = json.loads(output.getvalue())
        self.assertEqual(code, 1)
        self.assertTrue(payload["required"])
        self.assertTrue(payload["skipped"])

    def test_structured_reports_ignore_malformed_and_unrelated_output(self) -> None:
        reports = self.gate.parse_product_reports(
            "noise\n"
            'VITYO_PRODUCT_REPORT {"scenario":"edit-save-run"}\n'
            "VITYO_PRODUCT_REPORT not-json\n"
        )
        self.assertEqual(reports, [{"scenario": "edit-save-run"}])

    def test_result_requires_both_real_test_success_and_scenarios(self) -> None:
        passed = self.gate.result_payload(
            platform="linux",
            ok=True,
            returncode=0,
            reports=[{"scenario": "edit-save-run"}],
        )
        self.assertTrue(passed["ok"])
        self.assertEqual(passed["gate"], "vityo-desktop-product-gate")
        self.assertEqual(passed["capability"], "trusted-desktop-ide-loop")

        no_reports = self.gate.result_payload(
            platform="linux", ok=False, returncode=0, reports=[]
        )
        self.assertFalse(no_reports["ok"])
        self.assertFalse(no_reports["steps"][1]["ok"])

    def test_workspace_factory_contract_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temp_name:
            root = Path(temp_name)
            script = root / "scripts" / "ecosystem-product-gate.py"
            script.parent.mkdir()
            script.write_text("VALUE = 1\n", encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "contract is incomplete"):
                self.gate.load_pafio_workspace_factory(root)

    def test_workspace_factory_and_environment_use_real_inputs(self) -> None:
        with tempfile.TemporaryDirectory() as temp_name:
            root = Path(temp_name)
            script = root / "pafio/scripts/ecosystem-product-gate.py"
            script.parent.mkdir(parents=True)
            script.write_text(
                "\n".join(
                    f"def {name}(*args): return args[0] / '{index}.json'"
                    for index, name in enumerate(
                        (
                            "write_hosted_workspace",
                            "write_hosted_workspace_project",
                            "write_hosted_failing_dependency_workspace",
                            "write_registry_publish_package",
                            "write_registry_consumer_project",
                            "write_registry_missing_consumer_project",
                        )
                    )
                ),
                encoding="utf-8",
            )
            factory = self.gate.load_pafio_workspace_factory(root / "pafio")
            environment = self.gate.build_product_environment(
                factory=factory,
                temp_root=root / "work",
                styio_bin=root / "styio",
                pafio_bin=root / "pafio-bin",
            )

        self.assertEqual(environment["VITYO_PRODUCT_GATE"], "1")
        self.assertTrue(environment["VITYO_PRODUCT_MANIFEST6_PATH"].endswith("5.json"))
        self.assertIn("registry", environment["VITYO_PRODUCT_REGISTRY_ROOT"])

    def test_helpers_cover_ci_paths_output_and_human_summary(self) -> None:
        self.assertTrue(self.gate.enabled(" YES "))
        self.assertFalse(self.gate.enabled(None))
        self.assertTrue(self.gate.running_in_ci({"CI": "1"}))
        self.assertFalse(self.gate.running_in_ci({}))
        with mock.patch.dict("os.environ", {"A_PATH": "folder"}, clear=True):
            self.assertEqual(self.gate._env_path("A_PATH"), Path("folder"))
            self.assertIsNone(self.gate._env_path("MISSING"))
        self.assertIn("PASS", self.gate._human_summary({"ok": True, "platform": "linux"}))

    def test_real_matrix_success_writes_structured_report(self) -> None:
        with tempfile.TemporaryDirectory() as temp_name:
            root = Path(temp_name)
            styio = root / "styio"
            pafio = root / "pafio"
            pafio_root = root / "pafio-root"
            output_path = root / "reports/result.json"
            styio.write_text("binary", encoding="utf-8")
            pafio.write_text("binary", encoding="utf-8")
            pafio_root.mkdir()
            process = SimpleNamespace(
                returncode=0,
                stdout='VITYO_PRODUCT_REPORT {"scenario":"edit-save-run"}\n',
            )
            with (
                mock.patch.object(self.gate, "load_pafio_workspace_factory", return_value=object()),
                mock.patch.object(self.gate, "build_product_environment", return_value={"VITYO_PRODUCT_GATE": "1"}),
                mock.patch.object(self.gate.subprocess, "run", return_value=process) as run,
                redirect_stdout(io.StringIO()),
            ):
                code = self.gate.main(
                    [
                        "--platform", "linux",
                        "--styio-bin", str(styio),
                        "--pafio-bin", str(pafio),
                        "--pafio-root", str(pafio_root),
                        "--output", str(output_path),
                        "--json",
                    ]
                )

            payload = json.loads(output_path.read_text(encoding="utf-8"))
        self.assertEqual(code, 0)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["report"]["scenario_count"], 1)
        self.assertEqual(run.call_args.kwargs["env"]["VITYO_PRODUCT_GATE"], "1")

    def test_real_matrix_factory_error_is_a_non_skipped_failure(self) -> None:
        with tempfile.TemporaryDirectory() as temp_name:
            root = Path(temp_name)
            styio = root / "styio"
            pafio = root / "pafio"
            pafio_root = root / "pafio-root"
            styio.touch()
            pafio.touch()
            pafio_root.mkdir()
            output = io.StringIO()
            with (
                mock.patch.object(
                    self.gate,
                    "load_pafio_workspace_factory",
                    side_effect=ValueError("bad factory"),
                ),
                redirect_stdout(output),
            ):
                code = self.gate.main(
                    [
                        "--platform", "macos",
                        "--styio-bin", str(styio),
                        "--pafio-bin", str(pafio),
                        "--pafio-root", str(pafio_root),
                        "--json",
                    ]
                )
        payload = json.loads(output.getvalue())
        self.assertEqual(code, 1)
        self.assertFalse(payload["skipped"])


if __name__ == "__main__":
    unittest.main()

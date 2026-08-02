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
GATE_PATH = REPO_ROOT / "scripts/ecosystem-product-gate.py"


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

    def scenario(self) -> dict[str, object]:
        source = self.gate.EXPECTED_SOURCE_DIGEST
        check, test, run = "c" * 64, "d" * 64, "e" * 64

        def revision_step(name: str) -> dict[str, object]:
            return {
                "name": name,
                "status": "succeeded",
                "workspace_revision": 1,
                "source_sha256": source,
            }

        return {
            "schema_version": 1,
            "scenario": "trusted-desktop-styio-loop",
            "evidence_kind": "real-pinned-matrix",
            "ok": True,
            "workspace_revision": 1,
            "source_sha256": source,
            "preflight": {
                "metadata_contract": "metadata-v1",
                "sync_status": "succeeded",
                "compiler_tool": "styio",
                "compile_plan_contract": 1,
                "runtime_events_contract": 1,
                "runtime_event_stream": True,
                "package": "vityo/product-gate",
                "bin_target": "product-gate",
                "test_target": "product-gate-test",
            },
            "steps": [
                revision_step("edit"),
                {
                    **revision_step("check"),
                    "owner_contract": "pafio-current+styio-files-v1",
                    "session_id_sha256": check,
                },
                {
                    **revision_step("test"),
                    "owner_contract": "pafio-current+styio-files-v1",
                    "session_id_sha256": test,
                },
                {
                    **revision_step("run"),
                    "owner_contract": "pafio-current+styio-files-v1",
                    "session_id_sha256": run,
                },
                {
                    **revision_step("observe"),
                    "session_id_sha256": run,
                    "eventKind": "log.emitted",
                    "observation_sha256": self.gate.EXPECTED_OBSERVATION_DIGEST,
                },
            ],
        }

    def contracts(self) -> list[dict[str, object]]:
        values = (
            ("missing-styio", "blocked", "styio_missing"),
            (
                "incompatible-machine-contract",
                "blocked",
                "styio_machine_contract_incompatible",
            ),
            ("compiler-execution-failure", "failed", "compiler_execution_failed"),
        )
        return [
            {
                "schema_version": 1,
                "scenario": "trusted-desktop-styio-loop",
                "evidence_kind": "deterministic-contract",
                "case": case,
                "accepted": True,
                "outcome": outcome,
                "error_category": category,
                "success_observation": False,
            }
            for case, outcome, category in values
        ]

    def marker_output(self) -> bytes:
        lines = [
            self.gate.PRODUCT_MARKER + json.dumps(self.scenario()).encode("utf-8")
        ]
        lines.extend(
            self.gate.CONTRACT_MARKER + json.dumps(value).encode("utf-8")
            for value in self.contracts()
        )
        return b"\n".join(lines) + b"\n"

    def test_missing_real_matrix_is_loud_but_skippable_only_locally(self) -> None:
        output = io.StringIO()
        with mock.patch.dict("os.environ", {}, clear=True), redirect_stdout(output):
            code = self.gate.main(["--json"])
        payload = json.loads(output.getvalue())
        self.assertEqual(code, 0)
        self.assertFalse(payload["ok"])
        self.assertTrue(payload["skipped"])
        self.assertFalse(payload["required"])
        self.assertEqual(payload["failure_category"], "matrix_inputs_unavailable")
        self.assertIn(payload["platform"], {"linux", "macos", "windows"})

        output = io.StringIO()
        with mock.patch.dict("os.environ", {"CI": "true"}, clear=True), redirect_stdout(output):
            code = self.gate.main(["--json"])
        self.assertEqual(code, 1)
        self.assertTrue(json.loads(output.getvalue())["required"])

    def test_workspace_is_utf8_lf_and_uses_only_public_fixture_contract(self) -> None:
        with tempfile.TemporaryDirectory() as temp_name:
            root = Path(temp_name)
            def run_pafio(argv, **kwargs):
                workspace = Path(argv[3])
                workspace.mkdir(parents=True)
                (workspace / "pafio.toml").write_text(
                    "[pafio]\nmanifest-version = 1\n",
                    encoding="utf-8",
                )
                return SimpleNamespace(returncode=0)

            with mock.patch.object(
                self.gate.subprocess,
                "run",
                side_effect=run_pafio,
            ) as run:
                environment = self.gate.build_product_environment(
                    temp_root=root / "work",
                    styio_bin=root / "styio.exe",
                    pafio_bin=root / "pafio.exe",
                )
            manifest = Path(environment["VITYO_PRODUCT_MANIFEST_PATH"])
            source = manifest.parent / "src/main.styio"
            test_source = manifest.parent / "tests/product_gate.styio"
            manifest_bytes = manifest.read_bytes()
            self.assertNotIn(b"\r\n", manifest_bytes)
            self.assertIn(b"[[bin]]", manifest_bytes)
            self.assertIn(b"[[test]]", manifest_bytes)
            self.assertEqual(source.read_bytes(), b'>_("vityo-before-edit")\n')
            self.assertEqual(
                test_source.read_bytes(), b'>_("vityo-product-gate-test")\n'
            )
            self.assertEqual(
                run.call_args.args[0][1:3],
                ["new", "vityo/product-gate"],
            )
        self.assertNotIn("VITYO_PAFIO_ROOT", environment)

    def test_workspace_creation_fails_closed_when_pafio_new_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp_name:
            root = Path(temp_name)
            with (
                mock.patch.object(
                    self.gate.subprocess,
                    "run",
                    return_value=SimpleNamespace(returncode=2),
                ),
                self.assertRaisesRegex(ValueError, "pafio new failed"),
            ):
                self.gate.build_product_environment(
                    temp_root=root / "work",
                    styio_bin=root / "styio",
                    pafio_bin=root / "pafio",
                )

    def test_exact_valid_markers_and_closed_schemas_are_required(self) -> None:
        scenarios, contracts = self.gate.parse_product_reports(self.marker_output())
        self.gate.validate_product_reports(scenarios, contracts)

        flutter_output = b"\n".join(
            self.gate.FLUTTER_PRINT_PREFIX + line
            for line in self.marker_output().splitlines()
        )
        scenarios, contracts = self.gate.parse_product_reports(flutter_output)
        self.gate.validate_product_reports(scenarios, contracts)

        stale = self.scenario()
        stale["steps"][2]["source_sha256"] = "f" * 64
        with self.assertRaisesRegex(ValueError, "stale"):
            self.gate.validate_product_reports([stale], self.contracts())

        partial = self.scenario()
        del partial["preflight"]
        with self.assertRaisesRegex((ValueError, KeyError), "schema|preflight"):
            self.gate.validate_product_reports([partial], self.contracts())

        extra = self.scenario()
        extra["raw_stdout"] = "success"
        with self.assertRaisesRegex(ValueError, "closed"):
            self.gate.validate_product_reports([extra], self.contracts())

    def test_zero_duplicate_oversized_and_malformed_markers_fail(self) -> None:
        scenario = json.dumps(self.scenario()).encode("utf-8")
        duplicated = (
            self.gate.PRODUCT_MARKER + scenario + b"\n" + self.gate.PRODUCT_MARKER + scenario
        )
        products, contracts = self.gate.parse_product_reports(duplicated)
        with self.assertRaisesRegex(ValueError, "exactly"):
            self.gate.validate_product_reports(products, contracts)

        with self.assertRaises((json.JSONDecodeError, ValueError)):
            self.gate.parse_product_reports(self.gate.PRODUCT_MARKER + b"{bad")
        with self.assertRaisesRegex(ValueError, "byte limit"):
            self.gate.parse_product_reports(
                self.gate.PRODUCT_MARKER + b" " * (self.gate.MARKER_LIMIT + 1)
            )
        with self.assertRaisesRegex(ValueError, "byte limit"):
            self.gate.parse_product_reports(
                self.gate.PRODUCT_MARKER
                + scenario
                + b" " * self.gate.MARKER_LIMIT
            )
        with self.assertRaisesRegex(ValueError, "duplicate"):
            self.gate.parse_product_reports(
                self.gate.PRODUCT_MARKER + b'{"schema_version":1,"schema_version":1}'
            )
        with self.assertRaisesRegex(ValueError, "own output line"):
            self.gate.parse_product_reports(
                b"unrelated-prefix " + self.gate.PRODUCT_MARKER + scenario
            )

    def test_json_schema_rejects_boolean_integer_substitutions(self) -> None:
        for mutate in (
            lambda value: value.__setitem__("schema_version", True),
            lambda value: value["preflight"].__setitem__(
                "compile_plan_contract", True
            ),
            lambda value: value["steps"][1].__setitem__("owner_contract", True),
            lambda value: value["steps"][2].__setitem__(
                "workspace_revision", True
            ),
        ):
            with self.subTest(mutate=mutate):
                scenario = self.scenario()
                mutate(scenario)
                with self.assertRaises(ValueError):
                    self.gate.validate_product_reports(
                        [scenario], self.contracts()
                    )

    def test_unpublished_workflow_v1_projection_is_rejected(self) -> None:
        scenario = self.scenario()
        for step in scenario["steps"][1:4]:
            step.pop("owner_contract")
            step["workflow_payload_version"] = 1
        scenario["steps"][4]["event_kind"] = scenario["steps"][4].pop("eventKind")
        with self.assertRaisesRegex(ValueError, "closed"):
            self.gate.validate_product_reports([scenario], self.contracts())

    def test_expected_revision_source_and_observation_are_not_replaceable(self) -> None:
        for mutate in (
            lambda value: value.__setitem__("workspace_revision", 2),
            lambda value: value.__setitem__("source_sha256", "f" * 64),
            lambda value: value["steps"][4].__setitem__(
                "observation_sha256", "f" * 64
            ),
        ):
            with self.subTest(mutate=mutate):
                scenario = self.scenario()
                mutate(scenario)
                with self.assertRaises(ValueError):
                    self.gate.validate_product_reports([scenario], self.contracts())

    def test_contract_order_category_and_privacy_fail_closed(self) -> None:
        reversed_contracts = list(reversed(self.contracts()))
        with self.assertRaisesRegex(ValueError, "frozen case"):
            self.gate.validate_product_reports([self.scenario()], reversed_contracts)

        leaked = self.scenario()
        leaked["source_path"] = "/private/workspace/main.styio"
        with self.assertRaisesRegex(ValueError, "closed"):
            self.gate.validate_product_reports([leaked], self.contracts())

    def test_bounded_process_classifies_timeout_and_output_while_draining(self) -> None:
        with mock.patch.object(self.gate, "OUTER_TIMEOUT_SECONDS", 0.05):
            timeout = self.gate.run_bounded_process(
                [sys.executable, "-c", "import time; time.sleep(5)"],
                cwd=REPO_ROOT,
                env=dict(),
            )
        self.assertEqual(timeout.failure_category, "product_process_timeout")

        with mock.patch.object(self.gate, "OUTER_STREAM_LIMIT", 32):
            oversized = self.gate.run_bounded_process(
                [sys.executable, "-c", "import sys; sys.stdout.write('x'*1000000)"],
                cwd=REPO_ROOT,
                env=dict(),
            )
        self.assertEqual(
            oversized.failure_category, "product_output_limit_exceeded"
        )
        self.assertLessEqual(len(oversized.stdout), 33)

    def test_success_aggregation_writes_closed_outer_report(self) -> None:
        with tempfile.TemporaryDirectory() as temp_name:
            root = Path(temp_name)
            styio = root / "styio"
            pafio = root / "pafio"
            output_path = root / "reports/product.json"
            styio.write_bytes(b"binary")
            pafio.write_bytes(b"binary")
            process = self.gate.ProcessResult(0, self.marker_output(), b"")
            with (
                mock.patch.object(
                    self.gate, "build_product_environment", return_value={}
                ),
                mock.patch.object(
                    self.gate, "run_bounded_process", return_value=process
                ) as run,
                redirect_stdout(io.StringIO()),
            ):
                code = self.gate.main(
                    [
                        "--platform",
                        "windows",
                        "--styio-bin",
                        str(styio),
                        "--pafio-bin",
                        str(pafio),
                        "--output",
                        str(output_path),
                        "--require-real-matrix",
                        "--json",
                    ]
                )
            payload = json.loads(output_path.read_text(encoding="utf-8"))
        self.assertEqual(code, 0)
        self.assertTrue(payload["ok"])
        self.assertEqual(
            set(payload),
            {
                "schema_version",
                "gate",
                "platform",
                "capability",
                "evidence_kind",
                "ok",
                "required",
                "skipped",
                "failure_category",
                "steps",
                "report",
            },
        )
        self.assertEqual(
            run.call_args.args[0],
            ["flutter", "test", str(self.gate.PRODUCT_TEST)],
        )

    def test_failed_or_invalid_product_process_cannot_false_pass(self) -> None:
        for process, category in (
            (self.gate.ProcessResult(2, self.marker_output(), b""), "product_test_failed"),
            (
                self.gate.ProcessResult(
                    1, self.marker_output(), b"", "product_process_timeout"
                ),
                "product_process_timeout",
            ),
            (
                self.gate.ProcessResult(
                    1,
                    self.marker_output(),
                    b"",
                    "product_output_limit_exceeded",
                ),
                "product_output_limit_exceeded",
            ),
        ):
            with tempfile.TemporaryDirectory() as temp_name:
                root = Path(temp_name)
                styio, pafio = root / "styio", root / "pafio"
                styio.touch()
                pafio.touch()
                output = io.StringIO()
                with (
                    mock.patch.object(
                        self.gate, "build_product_environment", return_value={}
                    ),
                    mock.patch.object(
                        self.gate, "run_bounded_process", return_value=process
                    ),
                    redirect_stdout(output),
                ):
                    code = self.gate.main(
                        [
                            "--platform",
                            "linux",
                            "--styio-bin",
                            str(styio),
                            "--pafio-bin",
                            str(pafio),
                            "--require-real-matrix",
                            "--json",
                        ]
                    )
            payload = json.loads(output.getvalue())
            self.assertEqual(code, 1)
            self.assertFalse(payload["ok"])
            self.assertEqual(payload["failure_category"], category)
            self.assertEqual(payload["report"]["scenario_count"], 0)
            self.assertEqual(payload["report"]["contract_case_count"], 0)

    def test_process_failure_category_precedes_malformed_child_output(self) -> None:
        process = self.gate.ProcessResult(
            1,
            self.gate.PRODUCT_MARKER + b"{bad",
            b"",
            "product_process_timeout",
        )
        with tempfile.TemporaryDirectory() as temp_name:
            root = Path(temp_name)
            styio, pafio = root / "styio", root / "pafio"
            styio.touch()
            pafio.touch()
            output = io.StringIO()
            with (
                mock.patch.object(self.gate, "build_product_environment", return_value={}),
                mock.patch.object(self.gate, "run_bounded_process", return_value=process),
                redirect_stdout(output),
            ):
                code = self.gate.main(
                    [
                        "--platform",
                        "linux",
                        "--styio-bin",
                        str(styio),
                        "--pafio-bin",
                        str(pafio),
                        "--require-real-matrix",
                        "--json",
                    ]
                )
        payload = json.loads(output.getvalue())
        self.assertEqual(code, 1)
        self.assertEqual(payload["failure_category"], "product_process_timeout")
        self.assertEqual(payload["report"]["scenarios"], [])

    def test_invalid_child_report_is_not_copied_into_failure_evidence(self) -> None:
        leaked = self.scenario()
        leaked["source_path"] = "/private/workspace/main.styio"
        marker = self.gate.PRODUCT_MARKER + json.dumps(leaked).encode("utf-8")
        marker += b"\n" + b"\n".join(
            self.gate.CONTRACT_MARKER + json.dumps(value).encode("utf-8")
            for value in self.contracts()
        )
        with tempfile.TemporaryDirectory() as temp_name:
            root = Path(temp_name)
            styio, pafio = root / "styio", root / "pafio"
            styio.touch()
            pafio.touch()
            process = self.gate.ProcessResult(0, marker, b"")
            output = io.StringIO()
            with (
                mock.patch.object(
                    self.gate, "build_product_environment", return_value={}
                ),
                mock.patch.object(
                    self.gate, "run_bounded_process", return_value=process
                ),
                redirect_stdout(output),
            ):
                code = self.gate.main(
                    [
                        "--platform",
                        "linux",
                        "--styio-bin",
                        str(styio),
                        "--pafio-bin",
                        str(pafio),
                        "--require-real-matrix",
                        "--json",
                    ]
                )
        payload = json.loads(output.getvalue())
        self.assertEqual(code, 1)
        self.assertEqual(payload["failure_category"], "product_report_invalid")
        self.assertEqual(payload["report"]["scenarios"], [])
        self.assertNotIn("source_path", json.dumps(payload))

    def test_each_platform_ci_job_runs_the_frozen_report_oracle(self) -> None:
        workflow = (REPO_ROOT / ".github/workflows/local-ci-gate.yml").read_text(
            encoding="utf-8"
        )
        oracle = (
            "dart run tests/acceptance/vityo_app/"
            "trusted_desktop_styio_loop_acceptance_test.dart"
        )
        self.assertEqual(workflow.count(oracle), 3)
        for platform in ("linux", "windows", "macos"):
            self.assertIn(
                f"{oracle} --report build/evidence/product-gate-{platform}.json "
                f"--platform {platform}",
                workflow,
            )


if __name__ == "__main__":
    unittest.main()

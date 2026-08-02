#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import hashlib
import tempfile
import sys
import io
import json
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "scripts" / "record-product-matrix-evidence.py"


def load_module():
    spec = importlib.util.spec_from_file_location(
        "record_product_matrix_evidence", SCRIPT_PATH
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {SCRIPT_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class ProductMatrixEvidenceTest(unittest.TestCase):
    @staticmethod
    def gate_report(platform: str = "windows") -> dict[str, object]:
        source = hashlib.sha256(b'>_("vityo-observed-r1")\n').hexdigest()
        sessions = ("c" * 64, "d" * 64, "e" * 64)

        def step(name: str) -> dict[str, object]:
            return {
                "name": name,
                "status": "succeeded",
                "workspace_revision": 1,
                "source_sha256": source,
            }

        scenario = {
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
                step("edit"),
                {**step("check"), "owner_contract": "pafio-current+styio-files-v1", "session_id_sha256": sessions[0]},
                {**step("test"), "owner_contract": "pafio-current+styio-files-v1", "session_id_sha256": sessions[1]},
                {**step("run"), "owner_contract": "pafio-current+styio-files-v1", "session_id_sha256": sessions[2]},
                {
                    **step("observe"),
                    "session_id_sha256": sessions[2],
                    "eventKind": "log.emitted",
                    "observation_sha256": hashlib.sha256(
                        b"vityo-observed-r1"
                    ).hexdigest(),
                },
            ],
        }
        contracts = [
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
            for case, outcome, category in (
                ("missing-styio", "blocked", "styio_missing"),
                (
                    "incompatible-machine-contract",
                    "blocked",
                    "styio_machine_contract_incompatible",
                ),
                ("compiler-execution-failure", "failed", "compiler_execution_failed"),
            )
        ]
        return {
            "schema_version": 1,
            "gate": "vityo-desktop-product-gate",
            "platform": platform,
            "capability": "trusted-desktop-ide-loop",
            "evidence_kind": "real-pinned-matrix",
            "ok": True,
            "required": True,
            "skipped": False,
            "failure_category": None,
            "steps": [
                {"name": "product-process", "ok": True},
                {"name": "real-scenario", "ok": True},
                {"name": "deterministic-contract-cases", "ok": True},
            ],
            "report": {
                "scenario_count": 1,
                "scenarios": [scenario],
                "contract_case_count": 3,
                "contract_cases": contracts,
            },
        }

    @staticmethod
    def pty_report(platform: str = "windows", commit: str = "v" * 40):
        return {
            "schemaVersion": 1,
            "capability": "desktop-native-pty",
            "platform": platform,
            "provider": "conpty" if platform == "windows" else "forkpty",
            "ptyDependency": {"name": "pty2", "version": "0.5.2"},
            "vityoCommit": commit,
            "ok": True,
            "scenarios": [
                {"id": scenario, "status": "passed"}
                for scenario in (
                    "tty-identity",
                    "child-observed-resize",
                    "forced-process-close",
                    "terminal-environment-propagation",
                )
            ],
        }

    def test_evidence_proves_only_the_scoped_fixed_real_matrix(self) -> None:
        module = load_module()
        gate_report = self.gate_report()

        evidence = module.build_evidence(
            platform="windows",
            vityo_commit="v" * 40,
            styio_commit="a" * 40,
            pafio_commit="b" * 40,
            gate_report=gate_report,
            pty_report=self.pty_report(),
        )

        self.assertEqual(evidence["matrixStatus"], "proven")
        self.assertEqual(
            evidence["completionSemantics"], "fixed-real-product-matrix"
        )
        self.assertTrue(evidence["productCapabilityComplete"])
        self.assertEqual(evidence["capability"], "trusted-desktop-ide-loop")
        self.assertEqual(
            evidence["pinnedRepositories"],
            {"vityo": "v" * 40, "styio": "a" * 40, "pafio": "b" * 40},
        )
        self.assertEqual(evidence["nativePtyEvidence"]["scenarioCount"], 4)

    def test_gate_report_fails_closed_without_matching_successful_scenarios(self) -> None:
        module = load_module()
        base = self.gate_report(platform="linux")
        invalid_reports = [
            {**base, "gate": "other-gate"},
            {**base, "platform": "windows"},
            {**base, "capability": "all-product-capabilities"},
            {**base, "ok": False},
            {
                **base,
                "report": {
                    **base["report"],
                    "scenario_count": 0,
                },
            },
        ]

        for report in invalid_reports:
            with self.subTest(report=report):
                with self.assertRaises(ValueError):
                    module.validate_gate_report(report, platform="linux")

        with self.assertRaisesRegex(ValueError, "unsupported"):
            module.validate_gate_report(base, platform="solaris")

        stale = self.gate_report(platform="linux")
        stale["report"]["scenarios"][0]["source_sha256"] = "f" * 64
        with self.assertRaises(ValueError):
            module.validate_gate_report(stale, platform="linux")

    def test_repository_checkouts_must_match_fixed_matrix(self) -> None:
        module = load_module()
        matrix = {
            "schema_version": 1,
            "capability": "trusted-desktop-ide-loop",
            "repositories": {"styio": "a" * 40, "pafio": "b" * 40},
        }

        module.validate_pins(matrix, styio_commit="a" * 40, pafio_commit="b" * 40)
        with self.assertRaisesRegex(ValueError, "Styio"):
            module.validate_pins(matrix, styio_commit="x" * 40, pafio_commit="b" * 40)
        with self.assertRaisesRegex(ValueError, "Pafio"):
            module.validate_pins(matrix, styio_commit="a" * 40, pafio_commit="x" * 40)

    def test_native_pty_report_fails_closed_on_incomplete_or_wrong_platform_proof(self) -> None:
        module = load_module()
        report = self.pty_report(platform="linux")
        module.validate_pty_report(report, platform="linux", vityo_commit="v" * 40)

        invalid = dict(report)
        invalid["platform"] = "macos"
        with self.assertRaisesRegex(ValueError, "platform"):
            module.validate_pty_report(invalid, platform="linux", vityo_commit="v" * 40)
        invalid = dict(report)
        invalid["scenarios"] = report["scenarios"][:-1]
        with self.assertRaisesRegex(ValueError, "every required scenario"):
            module.validate_pty_report(invalid, platform="linux", vityo_commit="v" * 40)

    def test_dirty_repository_cannot_issue_product_matrix_evidence(self) -> None:
        module = load_module()
        completed = mock.Mock(stdout=" M source.file\n")
        with mock.patch.object(module.subprocess, "run", return_value=completed):
            with self.assertRaisesRegex(ValueError, "uncommitted changes"):
                module.require_clean_checkout(Path("repository"), name="Styio")

    def test_json_loader_and_pin_schema_fail_closed(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory() as temp_name:
            path = Path(temp_name) / "value.json"
            path.write_text("[]", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "JSON object"):
                module.load_json_object(path)
            path.write_text('{"schema_version": 1}', encoding="utf-8")
            self.assertEqual(module.load_json_object(path), {"schema_version": 1})
            path.write_text('{"schema_version":1,"schema_version":1}', encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "duplicate"):
                module.load_json_object(path)
            path.write_bytes(b" " * (module.MAX_JSON_INPUT_BYTES + 1))
            with self.assertRaisesRegex(ValueError, "bounded"):
                module.load_json_object(path)

        for matrix in (
            {"schema_version": 2},
            {"schema_version": 1, "capability": "other"},
            {
                "schema_version": 1,
                "capability": "trusted-desktop-ide-loop",
                "repositories": [],
            },
            {
                "schema_version": 1,
                "capability": "trusted-desktop-ide-loop",
                "repositories": {"styio": "a" * 40, "pafio": "b" * 40},
                "workflow_payload_version": 1,
            },
        ):
            with self.subTest(matrix=matrix), self.assertRaises(ValueError):
                module.validate_pins(matrix, styio_commit="s", pafio_commit="p")

    def test_unpublished_workflow_v1_projection_is_rejected(self) -> None:
        module = load_module()
        report = self.gate_report(platform="linux")
        scenario = report["report"]["scenarios"][0]
        for step in scenario["steps"][1:4]:
            step.pop("owner_contract")
            step["workflow_payload_version"] = 1
        scenario["steps"][4]["event_kind"] = scenario["steps"][4].pop("eventKind")
        with self.assertRaises(ValueError):
            module.validate_gate_report(report, platform="linux")

    def test_mixed_current_and_legacy_projection_is_rejected(self) -> None:
        module = load_module()
        report = self.gate_report(platform="linux")
        module.validate_gate_report(report, platform="linux")
        scenario = report["report"]["scenarios"][0]
        for step in scenario["steps"][1:4]:
            step["workflow_payload_version"] = 1
        scenario["steps"][4]["event_kind"] = "log.emitted"
        with self.assertRaises(ValueError):
            module.validate_gate_report(report, platform="linux")

    def test_clean_checkout_and_git_head(self) -> None:
        module = load_module()
        with mock.patch.object(
            module.subprocess,
            "run",
            side_effect=(mock.Mock(stdout="abc123\n"), mock.Mock(stdout="")),
        ) as run:
            self.assertEqual(module.git_head(Path("repository")), "abc123")
            module.require_clean_checkout(Path("repository"), name="Vityo")
        self.assertEqual(run.call_count, 2)

    def test_main_records_scoped_evidence(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory() as temp_name:
            root = Path(temp_name)
            matrix = root / "matrix.json"
            report = root / "report.json"
            pty_report = root / "pty-report.json"
            output = root / "nested/evidence.json"
            matrix.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "capability": "trusted-desktop-ide-loop",
                        "repositories": {"styio": "a" * 40, "pafio": "b" * 40},
                    }
                ),
                encoding="utf-8",
            )
            report.write_text(
                json.dumps(self.gate_report(platform="linux")),
                encoding="utf-8",
            )
            pty_report.write_text(
                json.dumps(self.pty_report(platform="linux")),
                encoding="utf-8",
            )
            argv = [
                "record-product-matrix-evidence.py",
                "--platform", "linux",
                "--vityo", str(root / "vityo"),
                "--styio", str(root / "styio"),
                "--pafio", str(root / "pafio"),
                "--matrix", str(matrix),
                "--gate-report", str(report),
                "--pty-report", str(pty_report),
                "--output", str(output),
            ]
            heads = iter(["a" * 40, "b" * 40, "v" * 40])
            with (
                mock.patch.object(module, "require_clean_checkout"),
                mock.patch.object(module, "git_head", side_effect=lambda _: next(heads)),
                mock.patch.object(sys, "argv", argv),
                redirect_stdout(io.StringIO()),
            ):
                self.assertEqual(module.main(), 0)
            evidence = json.loads(output.read_text(encoding="utf-8"))
        self.assertTrue(evidence["productCapabilityComplete"])
        self.assertEqual(evidence["gateEvidence"]["scenarioCount"], 1)


if __name__ == "__main__":
    unittest.main()

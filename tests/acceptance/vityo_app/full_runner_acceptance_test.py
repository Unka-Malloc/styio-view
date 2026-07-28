"""Acceptance contract for the IDE full-suite orchestrator.

These tests inspect the plan and synthetic receipts. They intentionally never
execute the one-time ``ide/full`` regression.
"""

from __future__ import annotations

import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[3]


def _load_module(name: str, relative_path: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {relative_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


receipt = _load_module(
    "vityo_validation_receipt",
    "scripts/vityo_validation_receipt.py",
)


class IdeFullRunnerAcceptanceTest(unittest.TestCase):
    def test_plan_only_is_complete_deterministic_and_side_effect_free(self) -> None:
        command = [
            sys.executable,
            "scripts/vityo_quality.py",
            "--product",
            "ide",
            "--suite",
            "full",
            "--plan-only",
        ]
        completed = subprocess.run(
            command,
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        self.assertEqual(payload["schema_version"], 1)
        self.assertEqual(payload["product"], "vityo")
        self.assertEqual(payload["mode"], "plan_only")
        mappings = payload["requirements"]
        self.assertEqual(
            [item["requirement"] for item in mappings],
            [f"REQ-IDE-{index:03d}" for index in range(1, 9)],
        )
        self.assertEqual(len({item["suite"] for item in mappings}), 8)
        encoded = json.dumps(payload, sort_keys=True).lower()
        self.assertNotIn("coding-agent/full", encoded)
        self.assertNotIn("vityo_coding_agent", encoded)

    def test_receipts_fail_closed_and_write_atomically(self) -> None:
        requirements = tuple(
            f"REQ-IDE-{index:03d}" for index in range(1, 9)
        )
        outcomes = {
            requirement: {
                "status": "passed",
                "suite": f"suite-{index}",
                "duration_ms": index,
            }
            for index, requirement in enumerate(requirements, start=1)
        }
        payload = receipt.build_ide_receipt(
            start_fingerprint="a" * 64,
            end_fingerprint="a" * 64,
            commit="b" * 40,
            platform="windows",
            outcomes=outcomes,
        )
        self.assertEqual(payload["status"], "passed")
        self.assertEqual(tuple(payload["requirements"]), requirements)
        self.assertNotIn("desktop_lanes", payload)

        with self.assertRaisesRegex(
            receipt.ValidationReceiptError,
            "missing_requirement_outcome",
        ):
            receipt.build_ide_receipt(
                start_fingerprint="a" * 64,
                end_fingerprint="a" * 64,
                commit="b" * 40,
                platform="windows",
                outcomes={
                    key: value
                    for key, value in outcomes.items()
                    if key != "REQ-IDE-008"
                },
            )
        with self.assertRaisesRegex(
            receipt.ValidationReceiptError,
            "source_fingerprint_drift",
        ):
            receipt.build_ide_receipt(
                start_fingerprint="a" * 64,
                end_fingerprint="c" * 64,
                commit="b" * 40,
                platform="windows",
                outcomes=outcomes,
            )

        with tempfile.TemporaryDirectory() as directory:
            destination = pathlib.Path(directory) / "ide-full.json"
            receipt.write_receipt_atomic(destination, payload)
            self.assertEqual(
                json.loads(destination.read_text(encoding="utf-8")),
                payload,
            )
            self.assertEqual(
                list(destination.parent.glob(f".{destination.name}.*.tmp")),
                [],
            )

    def test_duplicate_requirement_mapping_is_rejected(self) -> None:
        plan = [
            {
                "requirement": f"REQ-IDE-{index:03d}",
                "suite": f"suite-{index}",
            }
            for index in range(1, 9)
        ]
        plan[-1]["requirement"] = "REQ-IDE-007"
        with self.assertRaisesRegex(
            receipt.ValidationReceiptError,
            "invalid_requirement_mapping",
        ):
            receipt.validate_full_suite_plan(plan)


if __name__ == "__main__":
    unittest.main()

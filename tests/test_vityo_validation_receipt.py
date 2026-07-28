from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "scripts" / "vityo_validation_receipt.py"


def load_module():
    spec = importlib.util.spec_from_file_location(
        "vityo_validation_receipt_test_target",
        SCRIPT_PATH,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {SCRIPT_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class VityoValidationReceiptTest(unittest.TestCase):
    def setUp(self) -> None:
        self.receipt = load_module()

    def _plan(self) -> list[dict[str, object]]:
        return [
            {
                "requirement": f"REQ-IDE-{index:03d}",
                "suite": f"suite-{index}",
            }
            for index in range(1, 9)
        ]

    def _outcomes(self) -> dict[str, dict[str, object]]:
        return {
            f"REQ-IDE-{index:03d}": {
                "status": "passed",
                "suite": f"suite-{index}",
                "duration_ms": index,
            }
            for index in range(1, 9)
        }

    def test_full_suite_plan_requires_canonical_unique_mapping(self) -> None:
        self.receipt.validate_full_suite_plan(self._plan())

        invalid_plans = []
        missing_type = self._plan()
        missing_type[0]["requirement"] = 1
        invalid_plans.append(missing_type)
        duplicate = self._plan()
        duplicate[-1]["requirement"] = "REQ-IDE-007"
        invalid_plans.append(duplicate)
        duplicate_suite = self._plan()
        duplicate_suite[-1]["suite"] = "suite-7"
        invalid_plans.append(duplicate_suite)
        empty_suite = self._plan()
        empty_suite[-1]["suite"] = " "
        invalid_plans.append(empty_suite)

        for plan in invalid_plans:
            with self.subTest(plan=plan):
                with self.assertRaisesRegex(
                    self.receipt.ValidationReceiptError,
                    "invalid_requirement_mapping",
                ):
                    self.receipt.validate_full_suite_plan(plan)

    def test_receipt_builds_passed_and_failed_terminal_results(self) -> None:
        outcomes = self._outcomes()
        passed = self.receipt.build_ide_receipt(
            start_fingerprint="a" * 64,
            end_fingerprint="a" * 64,
            commit="b" * 40,
            platform="linux",
            outcomes=outcomes,
        )
        self.assertEqual(passed["status"], "passed")
        self.assertEqual(passed["product"], "vityo")
        self.assertEqual(tuple(passed["requirements"]), tuple(outcomes))

        outcomes["REQ-IDE-008"]["status"] = "blocked"
        failed = self.receipt.build_ide_receipt(
            start_fingerprint="a" * 64,
            end_fingerprint="a" * 64,
            commit="b" * 64,
            platform="windows",
            outcomes=outcomes,
        )
        self.assertEqual(failed["status"], "failed")

    def test_receipt_rejects_invalid_identity_and_outcomes(self) -> None:
        cases = []

        cases.append(
            (
                "invalid_source_fingerprint",
                {
                    "start_fingerprint": "not-a-hash",
                    "end_fingerprint": "not-a-hash",
                },
            )
        )
        cases.append(
            (
                "source_fingerprint_drift",
                {
                    "start_fingerprint": "a" * 64,
                    "end_fingerprint": "c" * 64,
                },
            )
        )
        cases.append(("invalid_commit", {"commit": "short"}))
        cases.append(("invalid_platform", {"platform": "fixture"}))

        missing = self._outcomes()
        missing.pop("REQ-IDE-008")
        cases.append(("missing_requirement_outcome", {"outcomes": missing}))

        invalid_status = self._outcomes()
        invalid_status["REQ-IDE-001"]["status"] = "unknown"
        cases.append(
            (
                "invalid_requirement_outcome",
                {"outcomes": invalid_status},
            )
        )

        invalid_suite = self._outcomes()
        invalid_suite["REQ-IDE-001"]["suite"] = None
        cases.append(
            (
                "invalid_requirement_outcome",
                {"outcomes": invalid_suite},
            )
        )

        defaults = {
            "start_fingerprint": "a" * 64,
            "end_fingerprint": "a" * 64,
            "commit": "b" * 40,
            "platform": "macos",
            "outcomes": self._outcomes(),
        }
        for expected_code, overrides in cases:
            with self.subTest(expected_code=expected_code):
                with self.assertRaisesRegex(
                    self.receipt.ValidationReceiptError,
                    expected_code,
                ):
                    self.receipt.build_ide_receipt(
                        **{**defaults, **overrides}
                    )

    def test_atomic_write_persists_and_cleans_up_failures(self) -> None:
        payload = {
            "schema_version": 1,
            "product": "vityo",
            "status": "passed",
        }
        with tempfile.TemporaryDirectory(
            prefix="vityo-receipt-",
        ) as tmp_name:
            root = Path(tmp_name)
            destination = root / "nested" / "receipt.json"
            self.receipt.write_receipt_atomic(destination, payload)
            self.assertEqual(
                json.loads(destination.read_text(encoding="utf-8")),
                payload,
            )
            self.assertEqual(
                list(destination.parent.glob(".*.tmp")),
                [],
            )

            with mock.patch.object(
                self.receipt.os,
                "replace",
                side_effect=OSError("synthetic replace failure"),
            ):
                with self.assertRaisesRegex(
                    OSError,
                    "synthetic replace failure",
                ):
                    self.receipt.write_receipt_atomic(
                        root / "failed.json",
                        payload,
                    )
            self.assertEqual(list(root.glob(".*.tmp")), [])

    def test_atomic_write_rejects_oversized_receipt(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="vityo-receipt-",
        ) as tmp_name:
            destination = Path(tmp_name) / "receipt.json"
            with self.assertRaisesRegex(
                self.receipt.ValidationReceiptError,
                "receipt_too_large",
            ):
                self.receipt.write_receipt_atomic(
                    destination,
                    {"payload": "x" * self.receipt.MAX_RECEIPT_BYTES},
                )
            self.assertFalse(destination.exists())


if __name__ == "__main__":
    unittest.main()

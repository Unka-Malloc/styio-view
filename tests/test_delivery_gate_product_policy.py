#!/usr/bin/env python3
from __future__ import annotations

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


class DeliveryGateProductPolicyTest(unittest.TestCase):
    def test_delivery_gate_requires_product_gate_in_ci_and_opt_in_runs(self) -> None:
        script = (REPO_ROOT / "scripts" / "delivery-gate.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn('is_true "${CI:-}"', script)
        self.assertIn('is_true "${GITHUB_ACTIONS:-}"', script)
        self.assertIn('is_true "${VITYO_PRODUCT_GATE:-}"', script)
        self.assertIn(
            "ecosystem-product-gate.py --require-real-matrix --json", script
        )
        self.assertIn('PRODUCT_GATE_STATUS="failed"', script)
        self.assertIn('PRODUCT_GATE_STATUS="proven"', script)
        self.assertIn('PRODUCT_GATE_STATUS="skipped"', script)

    def test_python_audit_launchers_use_the_configured_interpreter(self) -> None:
        script = (REPO_ROOT / "scripts" / "delivery-gate.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn('AUDIT_SHEBANG" == *python*', script)
        self.assertIn('AUDIT_CMD=("$PYTHON_BIN" "$AUDIT_BIN")', script)
        self.assertIn('run_cmd "${AUDIT_CMD[@]}" gate', script)


if __name__ == "__main__":
    unittest.main()

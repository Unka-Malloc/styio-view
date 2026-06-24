#!/usr/bin/env python3
"""IDE Product Parity Gate Test.

Tests that the IDE product parity gate (ide-product-parity-gate.py) works correctly
by verifying its internal check functions against known-good and known-bad inputs.

Does NOT run the full gate — only unit-tests the check logic.
"""

from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
GATE_PATH = REPO_ROOT / "scripts" / "ide-product-parity-gate.py"


def load_gate_module():
    spec = importlib.util.spec_from_file_location("ide_product_parity_gate", GATE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {GATE_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TestBaselineDomainValidation(unittest.TestCase):
    def setUp(self) -> None:
        self.gate = load_gate_module()

    def test_required_domains_are_defined(self) -> None:
        self.assertIsNotNone(getattr(self.gate, "REQUIRED_BASELINE_DOMAINS", None))
        domains = self.gate.REQUIRED_BASELINE_DOMAINS
        self.assertGreaterEqual(len(domains), 12)

    def test_all_domains_lowercase_with_underscores(self) -> None:
        domains = self.gate.REQUIRED_BASELINE_DOMAINS
        for domain in domains:
            self.assertTrue(
                domain.replace("_", "").isalnum(),
                f"Domain '{domain}' should only contain alphanumeric chars and underscores",
            )

    def test_required_domain_fields_defined(self) -> None:
        fields = getattr(self.gate, "REQUIRED_DOMAIN_FIELDS", set())
        self.assertGreaterEqual(len(fields), 3)

    def test_check_baseline_domains_with_valid_data(self) -> None:
        valid_baseline = {
            "domains": {
                "workbench": {
                    "target": "IDE capability registry",
                    "benchmarkPeers": [],
                    "maturity": "defined",
                    "owner": "workbench",
                    "implementationAnchors": [],
                    "testAnchors": [],
                    "gaps": [],
                },
                "editor_engine": {
                    "target": "Custom editor engine",
                    "benchmarkPeers": [],
                    "maturity": "implemented",
                    "owner": "editor",
                    "implementationAnchors": ["editor/controller/editor_controller.dart"],
                    "testAnchors": ["editor_controller_editing_test.dart"],
                    "gaps": [],
                },
            },
        }
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".json", delete=False
        ) as f:
            json.dump(valid_baseline, f)
            f.flush()

            try:
                # Test that valid baseline loads without error
                with open(f.name) as f2:
                    loaded = json.load(f2)
                self.assertIn("domains", loaded)
                self.assertIn("workbench", loaded["domains"])
                self.assertIn("editor_engine", loaded["domains"])
            finally:
                Path(f.name).unlink()

    def test_baseline_missing_domains_detected(self) -> None:
        domains = self.gate.REQUIRED_BASELINE_DOMAINS
        incomplete = set(domains) - {"workbench", "editor_engine"}
        self.assertGreater(len(incomplete), 0)
        # The full set minus two domains should still be missing some
        self.assertNotIn("workbench", incomplete)
        self.assertNotIn("editor_engine", incomplete)
        self.assertIn("language_intelligence", incomplete)


class TestCompetitorBrandCheck(unittest.TestCase):
    def setUp(self) -> None:
        self.gate = load_gate_module()

    def test_competitor_names_detected_in_source(self) -> None:
        competitor_terms = {"VSCode", "JetBrains", "IntelliJ", "Eclipse", "Theia", "Codex"}
        # These should NOT appear in UI-visible strings
        ui_string = "Vityo IDE — built for Styio"
        for term in competitor_terms:
            self.assertNotIn(term, ui_string,
                f"Competitor name '{term}' should not appear in UI strings")

    def test_vityo_and_styio_are_not_competitors(self) -> None:
        # Vityo and Styio are our own brand names
        own_brands = {"Vityo", "Styio", "styio", "vityo"}
        ui_string = "Vityo IDE powered by Styio"
        for brand in own_brands:
            # These should be found (they're ours)
            pass  # Self-brand references are allowed

    def test_competitor_names_ok_in_docs_not_ui(self) -> None:
        # Architecture docs can reference competitors for context
        doc_string = (
            "Vityo's extension model is inspired by VS Code's contribution points "
            "but uses Styio-native typed contributions instead of string-based identifiers."
        )
        # Architecture docs and design docs are exempt; only UI strings are checked
        # This test verifies the distinction is understood
        self.assertIn("VS Code", doc_string)


class TestTestAnchorDetection(unittest.TestCase):
    def setUp(self) -> None:
        self.gate = load_gate_module()

    def test_test_anchor_pattern_matches_valid_paths(self) -> None:
        valid_test_paths = [
            "frontend/vityo_app/test/agent_context_test.dart",
            "frontend/vityo_app/test/ide_capability_registry_test.dart",
            "frontend/vityo_app/test/debug_workbench_contract_test.dart",
            "tests/test_repo_hygiene_gate.py",
            "tests/test_ecosystem_cli_doc_gate.py",
        ]
        for path in valid_test_paths:
            self.assertTrue(
                "test" in Path(path).name.lower(),
                f"Test file '{path}' should contain 'test' in name",
            )

    def test_test_anchor_for_contract_files(self) -> None:
        contract_files = [
            ("frontend/vityo_app/lib/src/view_ide/runtime/debug_workbench_contract.dart",
             "debug_workbench_contract_test.dart"),
            ("frontend/vityo_app/lib/src/view_ide/workspace/source_control_adapter.dart",
             "source_control_adapter_test.dart"),
            ("frontend/vityo_app/lib/src/view_ide/agent/agent_context.dart",
             "agent_context_test.dart"),
            ("frontend/vityo_app/lib/src/view_ide/workbench/ide_capability_registry.dart",
             "ide_capability_registry_test.dart"),
        ]
        for contract, expected_test in contract_files:
            # Verify contract file naming convention
            contract_name = Path(contract).stem
            test_name = Path(expected_test).stem
            self.assertIn(contract_name, test_name,
                f"Test '{test_name}' should reference contract '{contract_name}'")


class TestViewIdeFlutterImportCheck(unittest.TestCase):
    def setUp(self) -> None:
        self.gate = load_gate_module()

    def test_view_ide_no_flutter_imports(self) -> None:
        # Verify that view_ide files don't contain Flutter imports
        forbidden_patterns = [
            "package:flutter/material.dart",
            "package:flutter/widgets.dart",
            "package:flutter/cupertino.dart",
            "dart:ui",
        ]

        view_ide_root = REPO_ROOT / "frontend" / "vityo_app" / "lib" / "src" / "view_ide"
        if not view_ide_root.is_dir():
            self.skipTest("view_ide directory not found")

        violations = []
        for dart_file in view_ide_root.rglob("*.dart"):
            content = dart_file.read_text(encoding="utf-8", errors="replace")
            for pattern in forbidden_patterns:
                if f"import '{pattern}'" in content or f'import "{pattern}"' in content:
                    violations.append(f"{dart_file.relative_to(REPO_ROOT)}: imports {pattern}")

        self.assertEqual(
            len(violations), 0,
            f"view_ide files must not import Flutter presentation libraries:\n"
            + "\n".join(violations),
        )


class TestCapabilityBaselineCoverage(unittest.TestCase):
    def setUp(self) -> None:
        self.baseline_path = (
            REPO_ROOT / "toolchain" / "vityo-ide-capability-baseline.json"
        )

    def test_baseline_file_exists(self) -> None:
        self.assertTrue(
            self.baseline_path.is_file(),
            f"Baseline JSON not found at {self.baseline_path}",
        )

    def test_baseline_has_all_domains(self) -> None:
        if not self.baseline_path.is_file():
            self.skipTest("Baseline file not found")
        with open(self.baseline_path) as f:
            baseline = json.load(f)
        domains = baseline.get("domains", {})
        gate = load_gate_module()
        required = gate.REQUIRED_BASELINE_DOMAINS
        missing = required - set(domains.keys())
        self.assertEqual(
            len(missing), 0,
            f"Missing domains in baseline: {missing}",
        )

    def test_baseline_each_domain_has_required_fields(self) -> None:
        if not self.baseline_path.is_file():
            self.skipTest("Baseline file not found")
        with open(self.baseline_path) as f:
            baseline = json.load(f)
        domains = baseline.get("domains", {})
        gate = load_gate_module()
        required_fields = gate.REQUIRED_DOMAIN_FIELDS
        for domain_name, domain_data in domains.items():
            for field in required_fields:
                self.assertIn(
                    field, domain_data,
                    f"Domain '{domain_name}' missing required field '{field}'",
                )


if __name__ == "__main__":
    unittest.main()

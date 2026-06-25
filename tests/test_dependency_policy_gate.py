#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
GATE_PATH = REPO_ROOT / "scripts" / "dependency-policy-gate.py"


def load_gate_module():
    spec = importlib.util.spec_from_file_location(
        "dependency_policy_gate",
        GATE_PATH,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {GATE_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class DependencyPolicyGateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.gate = load_gate_module()

    def _write_policy_tree(self, root: Path, policy_rows: str) -> None:
        pubspec = root / "frontend/vityo_app/pubspec.yaml"
        pubspec.parent.mkdir(parents=True, exist_ok=True)
        pubspec.write_text(
            "dependencies:\n"
            "  flutter:\n"
            "    sdk: flutter\n"
            "  crypto: ^3.0.7\n"
            "dev_dependencies:\n"
            "  flutter_test:\n"
            "    sdk: flutter\n"
            "  flutter_lints: ^5.0.0\n",
            encoding="utf-8",
        )
        package_json = root / "prototype/package.json"
        package_json.parent.mkdir(parents=True, exist_ok=True)
        package_json.write_text(
            json.dumps({"devDependencies": {"playwright-core": "1.59.1"}}),
            encoding="utf-8",
        )
        (root / "DEPENDENCY-USAGE.md").write_text(
            "| Dependency | Version | License |\n"
            "|---|---|---|\n"
            f"{policy_rows}",
            encoding="utf-8",
        )

    def _run_gate_in(self, root: Path):
        original_pubspec = self.gate.PUBSPEC_PATH
        original_package_json = self.gate.PACKAGE_JSON_PATH
        original_policy = self.gate.POLICY_PATH
        self.gate.PUBSPEC_PATH = root / "frontend/vityo_app/pubspec.yaml"
        self.gate.PACKAGE_JSON_PATH = root / "prototype/package.json"
        self.gate.POLICY_PATH = root / "DEPENDENCY-USAGE.md"
        try:
            return self.gate.run_gate(json_output=False)
        finally:
            self.gate.PUBSPEC_PATH = original_pubspec
            self.gate.PACKAGE_JSON_PATH = original_package_json
            self.gate.POLICY_PATH = original_policy

    def test_registered_pub_and_npm_dependencies_pass(self) -> None:
        with tempfile.TemporaryDirectory(prefix="dependency-policy-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            self._write_policy_tree(
                root,
                "| `crypto` | ^3.0.7 | BSD-3-Clause |\n"
                "| `flutter_lints` | ^5.0.0 | BSD-3-Clause |\n"
                "| `playwright-core` | 1.59.1 | Apache-2.0 |\n",
            )

            passed, _, unregistered, details = self._run_gate_in(root)

        self.assertTrue(passed)
        self.assertEqual(unregistered, [])
        sections = {detail["package"]: detail["section"] for detail in details}
        self.assertEqual(sections["playwright-core"], "package.json.devDependencies")

    def test_unregistered_npm_dependency_fails(self) -> None:
        with tempfile.TemporaryDirectory(prefix="dependency-policy-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            self._write_policy_tree(
                root,
                "| `crypto` | ^3.0.7 | BSD-3-Clause |\n"
                "| `flutter_lints` | ^5.0.0 | BSD-3-Clause |\n",
            )

            passed, _, unregistered, _ = self._run_gate_in(root)

        self.assertFalse(passed)
        self.assertEqual(unregistered, ["playwright-core"])


if __name__ == "__main__":
    unittest.main()

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
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[1]
GATE_PATH = REPO_ROOT / "scripts" / "ecosystem-cli-doc-gate.py"


def load_gate_module():
    spec = importlib.util.spec_from_file_location(
        "ecosystem_cli_doc_gate",
        GATE_PATH,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {GATE_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class EcosystemCliDocGateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.gate = load_gate_module()

    def test_main_skips_missing_canonical_gate_in_text_and_json_modes(self) -> None:
        original_gate = self.gate.CANONICAL_GATE
        with tempfile.TemporaryDirectory(prefix="ecosystem-cli-gate-", dir=REPO_ROOT) as tmp_name:
            self.gate.CANONICAL_GATE = Path(tmp_name) / "missing.py"
            try:
                text_output = io.StringIO()
                with redirect_stdout(text_output):
                    text_code = self.gate.main([])
                json_output = io.StringIO()
                with redirect_stdout(json_output):
                    json_code = self.gate.main(["--json"])
            finally:
                self.gate.CANONICAL_GATE = original_gate

        self.assertEqual(text_code, 0)
        self.assertIn("[SKIP]", text_output.getvalue())
        self.assertEqual(json_code, 0)
        payload = json.loads(json_output.getvalue())
        self.assertTrue(payload["ok"])
        self.assertTrue(payload["skipped"])

    def test_main_delegates_to_canonical_gate_with_vityo_arguments_unchanged(self) -> None:
        original_gate = self.gate.CANONICAL_GATE
        with tempfile.TemporaryDirectory(prefix="ecosystem-cli-gate-", dir=REPO_ROOT) as tmp_name:
            workspace = Path(tmp_name)
            canonical = workspace / "canonical.py"
            canonical.write_text("# gate\n", encoding="utf-8")
            self.gate.CANONICAL_GATE = canonical
            try:
                observed: dict[str, object] = {}

                def fake_run(command, cwd):
                    observed["command"] = command
                    observed["cwd"] = cwd
                    return mock.Mock(returncode=7)

                with mock.patch.object(self.gate.subprocess, "run", side_effect=fake_run):
                    code = self.gate.main(
                        ["--require-workspace", "--workspace-root", str(workspace)]
                    )
            finally:
                self.gate.CANONICAL_GATE = original_gate

        self.assertEqual(code, 7)
        command = observed["command"]
        self.assertEqual(command[:2], [sys.executable, str(canonical)])
        self.assertEqual(
            command[2:],
            ["--require-workspace", "--workspace-root", str(workspace)],
        )


if __name__ == "__main__":
    unittest.main()

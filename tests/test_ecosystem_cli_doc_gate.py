#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


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

    def test_workspace_root_from_args_accepts_split_and_equals_forms(self) -> None:
        self.assertEqual(
            self.gate.workspace_root_from_args(["--workspace-root", "/tmp/ws"]),
            Path("/tmp/ws"),
        )
        self.assertEqual(
            self.gate.workspace_root_from_args(["--workspace-root=/tmp/ws"]),
            Path("/tmp/ws"),
        )

    def test_args_with_workspace_root_replaces_existing_workspace_root(self) -> None:
        updated = self.gate.args_with_workspace_root(
            ["--require-workspace", "--workspace-root", "/old", "--json"],
            Path("/new"),
        )

        self.assertEqual(updated, ["--require-workspace", "--json", "--workspace-root", "/new"])

    def test_compatibility_workspace_aliases_vityo_as_styio_view(self) -> None:
        original_root = self.gate.ROOT
        with tempfile.TemporaryDirectory(prefix="ecosystem-cli-gate-", dir=REPO_ROOT) as tmp_name:
            workspace = Path(tmp_name)
            vityo_root = workspace / "vityo-nightly"
            vityo_root.mkdir()
            for repo_name in self.gate.SIBLING_REPOS:
                (workspace / repo_name).mkdir()
            self.gate.ROOT = vityo_root

            try:
                with self.gate.compatibility_workspace(["--require-workspace"]) as args:
                    aliased_root = self.gate.workspace_root_from_args(args)
                    self.assertTrue((aliased_root / "styio-view").is_dir())
                    self.assertTrue((aliased_root / "styio-nightly").is_dir())
                    self.assertTrue((aliased_root / "styio-spio").is_dir())
            finally:
                self.gate.ROOT = original_root

    def test_compatibility_workspace_keeps_existing_styio_view_workspace(self) -> None:
        original_root = self.gate.ROOT
        with tempfile.TemporaryDirectory(prefix="ecosystem-cli-gate-", dir=REPO_ROOT) as tmp_name:
            workspace = Path(tmp_name)
            vityo_root = workspace / "vityo-nightly"
            vityo_root.mkdir()
            (workspace / "styio-view").mkdir()
            self.gate.ROOT = vityo_root

            try:
                args = ["--workspace-root", str(workspace), "--json"]
                with self.gate.compatibility_workspace(args) as updated:
                    self.assertEqual(updated, args)
            finally:
                self.gate.ROOT = original_root


if __name__ == "__main__":
    unittest.main()

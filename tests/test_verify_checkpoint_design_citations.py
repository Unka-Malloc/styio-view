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


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "scripts" / "verify_checkpoint_design_citations.py"


def load_module():
    spec = importlib.util.spec_from_file_location(
        "verify_checkpoint_design_citations", SCRIPT_PATH
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {SCRIPT_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class VerifyCheckpointDesignCitationsTest(unittest.TestCase):
    def test_valid_citations_pass(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory() as temp_name:
            root = Path(temp_name)
            design = root / "docs/design"
            design.mkdir(parents=True)
            (design / "valid.md").write_text("one\ntwo\n", encoding="utf-8")
            checkpoint = root / "Checkpoints.json"
            checkpoint.write_text(
                json.dumps([{"id": "CP1", "citation": "docs/design/valid.md:2"}]),
                encoding="utf-8",
            )
            module.ROOT = root
            module.CP = checkpoint
            output = io.StringIO()
            with redirect_stdout(output):
                code = module.main()
        self.assertEqual(code, 0)
        self.assertIn("OK: 1", output.getvalue())

    def test_missing_and_out_of_range_citations_fail(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory() as temp_name:
            root = Path(temp_name)
            design = root / "docs/design"
            design.mkdir(parents=True)
            (design / "short.md").write_text("one\n", encoding="utf-8")
            checkpoint = root / "Checkpoints.json"
            checkpoint.write_text(
                json.dumps(
                    [
                        {"id": "CP1", "citation": "docs/design/missing.md"},
                        {"id": "CP2", "citation": "docs/design/short.md:3"},
                    ]
                ),
                encoding="utf-8",
            )
            module.ROOT = root
            module.CP = checkpoint
            output = io.StringIO()
            with redirect_stdout(output):
                code = module.main()
        self.assertEqual(code, 1)
        self.assertIn("missing file", output.getvalue())
        self.assertIn("line out of range", output.getvalue())


if __name__ == "__main__":
    unittest.main()

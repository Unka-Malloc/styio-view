from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "scripts" / "manifest_tool.py"
SPEC = importlib.util.spec_from_file_location("manifest_tool", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
manifest_tool = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = manifest_tool
SPEC.loader.exec_module(manifest_tool)


def modern_checkpoint() -> dict[str, object]:
    return {
        "id": "12345678-1234-4123-8123-123456789abc",
        "status": "pending",
        "role": "implementation",
        "prerequisites": [],
        "platform": "any",
        "difficulty": "high",
        "goal": "Validate the current checkpoint schema.",
        "description": "Exercise structured design and regression evidence.",
        "requirements": ["REQ-008"],
        "status_reason": "Waiting for implementation.",
        "latest_progress": "Schema fixture created.",
        "design": {
            "artifact": "docs/plan/example/Architecture.md",
            "owned_paths": ["lib/example.dart"],
            "scaffold_paths": ["lib/example.dart"],
            "acceptance_paths": ["test/example_test.dart"],
            "symbols": [
                {
                    "path": "lib/example.dart",
                    "kind": "class",
                    "name": "Example",
                    "operation": "modify",
                    "signature": "class Example",
                }
            ],
            "interfaces": [],
            "dependencies": ["fixture 1.0.0"],
            "decisions": {"state": "The fixture remains immutable."},
            "test_seams": ["unit fixture"],
        },
        "acceptance_criteria": [
            {
                "checked": False,
                "text": "The schema validates.",
                "evidence": "Focused validator test.",
            }
        ],
        "commit": {
            "repository": ".git",
            "message": "test: cover current checkpoint schema",
            "target": "test branch",
        },
        "regression": {
            "scope": "focused",
            "commands": ["python -m unittest"],
            "criteria": [0],
            "paths": ["scripts/manifest_tool.py"],
        },
        "next": [],
    }


class ManifestToolSchemaTests(unittest.TestCase):
    def test_current_checkpoint_schema_is_strictly_accepted(self) -> None:
        count, issues = manifest_tool.validate_checkpoints_data(
            Path("Checkpoints.json"), [modern_checkpoint()]
        )

        self.assertEqual(count, 1)
        self.assertEqual(issues, [])

    def test_optional_evidence_and_design_fields_remain_validated(self) -> None:
        node = deepcopy(modern_checkpoint())
        node["acceptance_criteria"][0]["evidence"] = ""
        node["design"]["unexpected"] = "not allowed"

        _, issues = manifest_tool.validate_checkpoints_data(
            Path("Checkpoints.json"), [node]
        )
        messages = "\n".join(issue.message for issue in issues)

        self.assertIn("evidence: must be a non-empty string", messages)
        self.assertIn("design.unexpected: unknown field", messages)

    def test_plan_status_derivation_preserves_startable_sibling_work(self) -> None:
        completed = {"id": "done", "status": "completed", "prerequisites": []}
        blocked = {"id": "stuck", "status": "blocked", "prerequisites": ["done"]}
        startable = {"id": "next", "status": "pending", "prerequisites": ["done"]}

        self.assertEqual(
            manifest_tool.derive_plan_status("pending", [completed, blocked, startable]),
            "in_progress",
        )
        self.assertEqual(
            manifest_tool.derive_plan_status("in_progress", [completed, blocked]),
            "blocked",
        )
        self.assertEqual(
            manifest_tool.derive_plan_status(
                "in_progress",
                [completed, {**completed, "id": "also-done"}],
            ),
            "completed",
        )

    def test_sync_plan_updates_manifest_atomically(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            plan_directory = root / "example"
            plan_directory.mkdir()
            checkpoints = plan_directory / "Checkpoints.json"
            checkpoints.write_text(
                '[{"id":"done","status":"completed","prerequisites":[]},'
                '{"id":"next","status":"pending","prerequisites":["done"]}]',
                encoding="utf-8",
            )
            manifest = root / "Manifest.json"
            manifest.write_text(
                '[{"status":"pending","title":"Example",'
                '"checkpoints":"example/Checkpoints.json"}]',
                encoding="utf-8",
            )

            result = manifest_tool.sync_plan_command(
                type("Args", (), {"root": str(root)})()
            )

            self.assertEqual(result, 0)
            data = manifest_tool.load_json_array(manifest)
            self.assertEqual(data[0]["status"], "in_progress")
            self.assertEqual(list(root.glob(".Manifest.json.tmp-*")), [])


if __name__ == "__main__":
    unittest.main()

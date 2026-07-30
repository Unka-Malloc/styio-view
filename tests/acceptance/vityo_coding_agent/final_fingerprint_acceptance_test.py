"""Frozen acceptance for the Coding Agent final fingerprint path contract."""

from __future__ import annotations

import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[3]
FINAL_NODE_ID = "1324166c-eba0-46f8-a4bf-655df57bdd83"


def main() -> None:
    checkpoints = json.loads(
        (
            ROOT
            / "docs"
            / "plan"
            / "vityo-coding-agent"
            / "Checkpoints.json"
        ).read_text(encoding="utf-8")
    )
    node = next(item for item in checkpoints if item["id"] == FINAL_NODE_ID)
    paths = node["regression"]["paths"]
    assert paths == [
        "products/vityo_coding_agent/benchmark",
        "products/vityo_coding_agent/bin",
        "products/vityo_coding_agent/fixtures",
        "products/vityo_coding_agent/integration_test",
        "products/vityo_coding_agent/lib",
        "products/vityo_coding_agent/test",
        "products/vityo_coding_agent/analysis_options.yaml",
        "products/vityo_coding_agent/pubspec.lock",
        "products/vityo_coding_agent/pubspec.yaml",
        "packages/vityo_agent_protocol/lib",
        "packages/vityo_agent_protocol/schema",
        "packages/vityo_agent_protocol/test",
        "packages/vityo_agent_protocol/analysis_options.yaml",
        "packages/vityo_agent_protocol/pubspec.lock",
        "packages/vityo_agent_protocol/pubspec.yaml",
        "scripts/vityo_quality.py",
        "scripts/vityo_validation_receipt.py",
        "tests/acceptance/vityo_coding_agent",
        "docs/plan/vityo-coding-agent/Requirements.md",
        "docs/plan/vityo-coding-agent/Architecture.md",
        "docs/plan/vityo-coding-agent/Validation.md",
    ]
    assert all("Checkpoints.json" not in path for path in paths)
    assert all(".dart_tool" not in path for path in paths)
    assert "docs/plan/vityo-coding-agent" not in paths


if __name__ == "__main__":
    main()

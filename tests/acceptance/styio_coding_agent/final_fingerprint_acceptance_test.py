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
            / "styio-coding-agent"
            / "Checkpoints.json"
        ).read_text(encoding="utf-8")
    )
    node = next(item for item in checkpoints if item["id"] == FINAL_NODE_ID)
    paths = node["regression"]["paths"]
    assert paths == [
        "products/styio_coding_agent/benchmark",
        "products/styio_coding_agent/bin",
        "products/styio_coding_agent/fixtures",
        "products/styio_coding_agent/integration_test",
        "products/styio_coding_agent/lib",
        "products/styio_coding_agent/test",
        "products/styio_coding_agent/analysis_options.yaml",
        "products/styio_coding_agent/pubspec.lock",
        "products/styio_coding_agent/pubspec.yaml",
        "packages/styio_agent_protocol/lib",
        "packages/styio_agent_protocol/schema",
        "packages/styio_agent_protocol/test",
        "packages/styio_agent_protocol/analysis_options.yaml",
        "packages/styio_agent_protocol/pubspec.lock",
        "packages/styio_agent_protocol/pubspec.yaml",
        "scripts/styio_quality.py",
        "scripts/styio_validation_receipt.py",
        "tests/acceptance/styio_coding_agent",
        "docs/plan/styio-coding-agent/Requirements.md",
        "docs/plan/styio-coding-agent/Architecture.md",
        "docs/plan/styio-coding-agent/Validation.md",
    ]
    assert all("Checkpoints.json" not in path for path in paths)
    assert all(".dart_tool" not in path for path in paths)
    assert "docs/plan/styio-coding-agent" not in paths


if __name__ == "__main__":
    main()

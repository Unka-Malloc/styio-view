"""Frozen acceptance for independent commit-bound desktop release lanes."""

from __future__ import annotations

import importlib.util
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]


def _load_delivery_module():
    path = ROOT / "packaging" / "vityo" / "desktop_delivery.py"
    spec = importlib.util.spec_from_file_location("desktop_delivery", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def main() -> None:
    completed = subprocess.run(
        [
            sys.executable,
            "scripts/vityo_quality.py",
            "--product",
            "ide",
            "--suite",
            "source-fingerprint",
        ],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 0
    assert re.fullmatch(r"[0-9a-f]{64}\n?", completed.stdout)

    delivery = _load_delivery_module()
    base = {
        "schema_version": 1,
        "platform": "windows",
        "artifact_verified": True,
        "launched": True,
        "workspace_opened": True,
        "capabilities": {
            "editor": "available",
            "workspace": "available",
            "agent": "unavailable",
            "agent_reason": "No Agent descriptor is configured.",
        },
    }
    missing_binding = delivery.evaluate_lane(
        platform="windows",
        host_platform="windows",
        available_tools=delivery.REQUIRED_TOOLS["windows"],
        evidence=base,
    )
    assert missing_binding.status == "failed"

    bound = delivery.evaluate_lane(
        platform="windows",
        host_platform="windows",
        available_tools=delivery.REQUIRED_TOOLS["windows"],
        evidence={
            **base,
            "commit": "a" * 40,
            "source_fingerprint": "b" * 64,
        },
    )
    assert bound.status == "passed"

    workflow = (
        ROOT / ".github" / "workflows" / "local-ci-gate.yml"
    ).read_text(encoding="utf-8")
    assert workflow.count("--commit") >= 3
    assert workflow.count("--source-fingerprint") >= 3
    assert "vityo-final-validation" not in workflow
    assert "collect_vityo_desktop_evidence.py" not in workflow

    quality_runner = (ROOT / "scripts" / "vityo_quality.py").read_text(
        encoding="utf-8"
    )
    assert "--desktop-evidence-dir" not in quality_runner
    assert "_desktop_lanes" not in quality_runner


if __name__ == "__main__":
    main()

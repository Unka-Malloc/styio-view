"""Frozen acceptance for the host-neutral release evaluator boundary."""

from __future__ import annotations

import json
import pathlib
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[3]
PRODUCT = ROOT / "products" / "styio_coding_agent"


def main() -> None:
    for source in (PRODUCT / "lib").rglob("*.dart"):
        text = source.read_text(encoding="utf-8")
        assert "dart:io" not in text, f"{source.name} imports dart:io"

    dart = shutil.which("dart")
    assert dart is not None
    completed = subprocess.run(
        [
            dart,
            "--packages=.dart_tool/package_config.json",
            "benchmark/release_evaluation.dart",
        ],
        cwd=PRODUCT,
        check=False,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 0
    report = json.loads(completed.stdout)
    assert report["passed"] is True
    assert len(report["results"]) == 7
    assert all(result["passed"] is True for result in report["results"])


if __name__ == "__main__":
    main()

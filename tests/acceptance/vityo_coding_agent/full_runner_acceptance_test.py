"""Frozen acceptance for the Coding Agent full validation receipt boundary."""

from __future__ import annotations

import json
import pathlib
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts"))

import vityo_quality as quality  # noqa: E402


def main() -> None:
    original = {
        entry.runner_name: getattr(quality, entry.runner_name)
        for entry in quality.FULL_AGENT_PLAN
    }
    original_fingerprint = quality._source_fingerprint
    original_commit = quality._head_commit
    original_platform = quality._host_platform
    original_plan_validation = quality._run_plan_validation
    calls: list[str] = []
    try:
        quality._source_fingerprint = lambda _roots: "a" * 64
        quality._head_commit = lambda: "b" * 40
        quality._host_platform = lambda: "fixture"
        quality._run_plan_validation = lambda: 0
        for entry in quality.FULL_AGENT_PLAN:
            setattr(
                quality,
                entry.runner_name,
                _runner(entry.requirement, calls),
            )
        with tempfile.TemporaryDirectory() as directory:
            destination = pathlib.Path(directory) / "passed.json"
            assert quality.coding_agent_full(receipt_path=destination) == 0
            passed = json.loads(destination.read_text(encoding="utf-8"))
            _assert_receipt(passed, "passed")
            assert calls == [
                f"REQ-AGENT-{index:03d}" for index in range(1, 10)
            ]

            calls.clear()
            setattr(
                quality,
                quality.FULL_AGENT_PLAN[4].runner_name,
                _failing_runner(calls),
            )
            destination = pathlib.Path(directory) / "failed.json"
            assert quality.coding_agent_full(receipt_path=destination) == 1
            failed = json.loads(destination.read_text(encoding="utf-8"))
            _assert_receipt(failed, "failed")
            assert (
                failed["requirements"]["REQ-AGENT-005"]["status"] == "failed"
            )

            quality._source_fingerprint = _broken_fingerprint
            destination = pathlib.Path(directory) / "harness-failed.json"
            assert quality.coding_agent_full(receipt_path=destination) == 1
            harness_failed = json.loads(
                destination.read_text(encoding="utf-8")
            )
            _assert_receipt(harness_failed, "failed")
            assert harness_failed["failure_code"] == "validation_harness_failed"
            assert "message" not in harness_failed
    finally:
        for name, runner in original.items():
            setattr(quality, name, runner)
        quality._source_fingerprint = original_fingerprint
        quality._head_commit = original_commit
        quality._host_platform = original_platform
        quality._run_plan_validation = original_plan_validation


def _runner(requirement: str, calls: list[str]):
    def run() -> int:
        calls.append(requirement)
        return 0

    return run


def _failing_runner(calls: list[str]):
    def run() -> int:
        calls.append("REQ-AGENT-005")
        raise RuntimeError("fixture failure must not escape")

    return run


def _broken_fingerprint(_roots: tuple[str, ...]) -> str:
    raise RuntimeError("fixture failure must not enter the receipt")


def _assert_receipt(receipt: dict[str, object], status: str) -> None:
    assert receipt["schema_version"] == 1
    assert receipt["product"] == "vityo_coding_agent"
    assert receipt["suite"] == "full"
    assert receipt["status"] == status
    requirements = receipt["requirements"]
    assert isinstance(requirements, dict)
    assert set(requirements) == {
        f"REQ-AGENT-{index:03d}" for index in range(1, 10)
    }


if __name__ == "__main__":
    main()

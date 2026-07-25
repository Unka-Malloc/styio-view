#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path


EXPECTED_GATE = "vityo-desktop-product-gate"
EXPECTED_CAPABILITY = "trusted-desktop-ide-loop"
EXPECTED_PTY_CAPABILITY = "desktop-native-pty"
EXPECTED_PTY_SCENARIOS = {
    "tty-identity",
    "child-observed-resize",
    "forced-process-close",
    "terminal-environment-propagation",
}
EXPECTED_PTY_PROVIDERS = {"linux": "forkpty", "macos": "forkpty", "windows": "conpty"}


def git_head(repository: Path) -> str:
    return subprocess.run(
        ["git", "-C", str(repository), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()


def require_clean_checkout(repository: Path, *, name: str) -> None:
    status = subprocess.run(
        ["git", "-C", str(repository), "status", "--porcelain"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    if status.strip():
        raise ValueError(f"{name} checkout contains uncommitted changes")


def load_json_object(path: Path) -> dict[str, object]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"{path.name} must contain a JSON object")
    return payload


def validate_gate_report(report: dict[str, object], *, platform: str) -> None:
    if report.get("gate") != EXPECTED_GATE:
        raise ValueError("gate report has an unexpected gate identity")
    if report.get("platform") != platform:
        raise ValueError("gate report platform does not match evidence platform")
    if report.get("capability") != EXPECTED_CAPABILITY:
        raise ValueError("gate report has an unexpected capability scope")
    if report.get("ok") is not True:
        raise ValueError("product matrix gate did not pass")
    report_section = report.get("report")
    if not isinstance(report_section, dict):
        raise ValueError("gate report is missing structured scenario evidence")
    scenario_count = report_section.get("scenario_count")
    if not isinstance(scenario_count, int) or scenario_count <= 0:
        raise ValueError("gate report contains no successful product scenarios")


def validate_pins(
    matrix: dict[str, object], *, styio_commit: str, pafio_commit: str
) -> None:
    if matrix.get("schema_version") != 1:
        raise ValueError("product matrix schema is unsupported")
    if matrix.get("capability") != EXPECTED_CAPABILITY:
        raise ValueError("product matrix capability is unsupported")
    repositories = matrix.get("repositories")
    if not isinstance(repositories, dict):
        raise ValueError("product matrix repository pins are missing")
    if repositories.get("styio") != styio_commit:
        raise ValueError("Styio checkout does not match the fixed product matrix")
    if repositories.get("pafio") != pafio_commit:
        raise ValueError("Pafio checkout does not match the fixed product matrix")


def validate_pty_report(
    report: dict[str, object], *, platform: str, vityo_commit: str
) -> None:
    if report.get("schemaVersion") != 1:
        raise ValueError("native PTY report schema is unsupported")
    if report.get("capability") != EXPECTED_PTY_CAPABILITY:
        raise ValueError("native PTY report has an unexpected capability scope")
    if report.get("platform") != platform:
        raise ValueError("native PTY report platform does not match evidence platform")
    if report.get("provider") != EXPECTED_PTY_PROVIDERS.get(platform):
        raise ValueError("native PTY report provider does not match the platform")
    if report.get("vityoCommit") != vityo_commit:
        raise ValueError("native PTY report does not match the Vityo commit")
    if report.get("ptyDependency") != {"name": "pty2", "version": "0.5.2"}:
        raise ValueError("native PTY report does not use the fixed PTY dependency")
    if report.get("ok") is not True:
        raise ValueError("native PTY matrix did not pass")
    scenarios = report.get("scenarios")
    if not isinstance(scenarios, list):
        raise ValueError("native PTY report is missing scenarios")
    passed = {
        scenario.get("id")
        for scenario in scenarios
        if isinstance(scenario, dict) and scenario.get("status") == "passed"
    }
    if passed != EXPECTED_PTY_SCENARIOS or len(scenarios) != len(EXPECTED_PTY_SCENARIOS):
        raise ValueError("native PTY report does not prove every required scenario")


def build_evidence(
    *,
    platform: str,
    vityo_commit: str,
    styio_commit: str,
    pafio_commit: str,
    gate_report: dict[str, object],
    pty_report: dict[str, object],
) -> dict[str, object]:
    report = gate_report["report"]
    assert isinstance(report, dict)
    return {
        "schemaVersion": 1,
        "platform": platform,
        "matrixStatus": "proven",
        "completionSemantics": "fixed-real-product-matrix",
        "capability": EXPECTED_CAPABILITY,
        "productCapabilityComplete": True,
        "pinnedRepositories": {
            "vityo": vityo_commit,
            "styio": styio_commit,
            "pafio": pafio_commit,
        },
        "repositoryTreeState": "clean",
        "gateEvidence": {
            "gate": gate_report["gate"],
            "scenarioCount": report["scenario_count"],
        },
        "nativePtyEvidence": {
            "capability": pty_report["capability"],
            "provider": pty_report["provider"],
            "scenarioCount": len(pty_report["scenarios"]),
            "ptyDependency": pty_report["ptyDependency"],
        },
        "message": (
            "The trusted desktop IDE loop passed against fixed real Styio and "
            "Pafio revisions on this platform."
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", required=True)
    parser.add_argument("--vityo", type=Path, required=True)
    parser.add_argument("--styio", type=Path, required=True)
    parser.add_argument("--pafio", type=Path, required=True)
    parser.add_argument("--matrix", type=Path, required=True)
    parser.add_argument("--gate-report", type=Path, required=True)
    parser.add_argument("--pty-report", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    for name, repository in (
        ("Vityo", args.vityo),
        ("Styio", args.styio),
        ("Pafio", args.pafio),
    ):
        require_clean_checkout(repository, name=name)
    styio_commit = git_head(args.styio)
    pafio_commit = git_head(args.pafio)
    matrix = load_json_object(args.matrix)
    gate_report = load_json_object(args.gate_report)
    pty_report = load_json_object(args.pty_report)
    validate_pins(matrix, styio_commit=styio_commit, pafio_commit=pafio_commit)
    validate_gate_report(gate_report, platform=args.platform)
    vityo_commit = git_head(args.vityo)
    validate_pty_report(
        pty_report,
        platform=args.platform,
        vityo_commit=vityo_commit,
    )
    evidence = build_evidence(
        platform=args.platform,
        vityo_commit=vityo_commit,
        styio_commit=styio_commit,
        pafio_commit=pafio_commit,
        gate_report=gate_report,
        pty_report=pty_report,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(evidence, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(evidence, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path


EXPECTED_GATE = "vityo-desktop-product-gate"
EXPECTED_CAPABILITY = "trusted-desktop-ide-loop"
EXPECTED_SCENARIO = "trusted-desktop-styio-loop"
EXPECTED_PLATFORMS = {"linux", "macos", "windows"}
EXPECTED_CONTRACTS = (
    ("missing-styio", "blocked", "styio_missing"),
    (
        "incompatible-machine-contract",
        "blocked",
        "styio_machine_contract_incompatible",
    ),
    ("compiler-execution-failure", "failed", "compiler_execution_failed"),
)
EXPECTED_PTY_CAPABILITY = "desktop-native-pty"
EXPECTED_PTY_SCENARIOS = {
    "tty-identity",
    "child-observed-resize",
    "forced-process-close",
    "terminal-environment-propagation",
}
EXPECTED_PTY_PROVIDERS = {"linux": "forkpty", "macos": "forkpty", "windows": "conpty"}
COMMIT = re.compile(r"^[0-9a-f]{40}$")
DIGEST = re.compile(r"^[0-9a-f]{64}$")
MAX_JSON_INPUT_BYTES = 1_048_576
MAX_GATE_REPORT_BYTES = 65_536
EXPECTED_SOURCE_DIGEST = hashlib.sha256(b'>_("vityo-observed-r1")\n').hexdigest()
EXPECTED_OBSERVATION_DIGEST = hashlib.sha256(b"vityo-observed-r1").hexdigest()


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
    with path.open("rb") as stream:
        raw = stream.read(MAX_JSON_INPUT_BYTES + 1)
    if len(raw) > MAX_JSON_INPUT_BYTES:
        raise ValueError(f"{path.name} exceeds its bounded JSON input limit")
    payload = json.loads(
        raw.decode("utf-8"),
        object_pairs_hook=_unique_json_object,
        parse_constant=_reject_json_constant,
    )
    if not isinstance(payload, dict):
        raise ValueError(f"{path.name} must contain a JSON object")
    return payload


def _unique_json_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    value: dict[str, object] = {}
    for key, child in pairs:
        if key in value:
            raise ValueError("JSON input contains duplicate fields")
        value[key] = child
    return value


def _reject_json_constant(value: str) -> None:
    raise ValueError(f"JSON input contains invalid constant: {value}")


def validate_gate_report(report: dict[str, object], *, platform: str) -> None:
    if platform not in EXPECTED_PLATFORMS:
        raise ValueError("gate report platform is unsupported")
    if len(json.dumps(report, separators=(",", ":")).encode("utf-8")) > MAX_GATE_REPORT_BYTES:
        raise ValueError("gate report exceeds its bounded report limit")
    if set(report) != {
        "schema_version",
        "gate",
        "platform",
        "capability",
        "evidence_kind",
        "ok",
        "required",
        "skipped",
        "failure_category",
        "steps",
        "report",
    }:
        raise ValueError("gate report schema is not closed")
    if type(report.get("schema_version")) is not int or report["schema_version"] != 1:
        raise ValueError("gate report schema is unsupported")
    if report.get("gate") != EXPECTED_GATE:
        raise ValueError("gate report has an unexpected gate identity")
    if report.get("platform") != platform:
        raise ValueError("gate report platform does not match evidence platform")
    if report.get("capability") != EXPECTED_CAPABILITY:
        raise ValueError("gate report has an unexpected capability scope")
    if (
        report.get("evidence_kind") != "real-pinned-matrix"
        or report.get("ok") is not True
        or report.get("required") is not True
        or report.get("skipped") is not False
        or report.get("failure_category") is not None
    ):
        raise ValueError("product matrix gate did not pass")
    steps = report.get("steps")
    expected_steps = (
        "product-process",
        "real-scenario",
        "deterministic-contract-cases",
    )
    if (
        not isinstance(steps, list)
        or len(steps) != len(expected_steps)
        or any(
            not isinstance(step, dict)
            or set(step) != {"name", "ok"}
            or step.get("name") != expected_steps[index]
            or step.get("ok") is not True
            for index, step in enumerate(steps)
        )
    ):
        raise ValueError("gate report steps are incomplete")
    report_section = report.get("report")
    if not isinstance(report_section, dict) or set(report_section) != {
        "scenario_count",
        "scenarios",
        "contract_case_count",
        "contract_cases",
    }:
        raise ValueError("gate report is missing structured scenario evidence")
    scenario_count = report_section.get("scenario_count")
    scenarios = report_section.get("scenarios")
    contract_count = report_section.get("contract_case_count")
    contracts = report_section.get("contract_cases")
    if (
        type(scenario_count) is not int
        or scenario_count != 1
        or not isinstance(scenarios, list)
        or len(scenarios) != 1
        or type(contract_count) is not int
        or contract_count != 3
        or not isinstance(contracts, list)
        or len(contracts) != 3
    ):
        raise ValueError("gate report must contain one scenario and three contracts")
    _validate_scenario_summary(scenarios[0])
    for contract, expected in zip(contracts, EXPECTED_CONTRACTS, strict=True):
        if (
            not isinstance(contract, dict)
            or set(contract) != {
                "schema_version",
                "scenario",
                "evidence_kind",
                "case",
                "accepted",
                "outcome",
                "error_category",
                "success_observation",
            }
            or type(contract.get("schema_version")) is not int
            or contract.get("schema_version") != 1
            or contract.get("scenario") != EXPECTED_SCENARIO
            or contract.get("evidence_kind") != "deterministic-contract"
            or contract.get("case") != expected[0]
            or contract.get("accepted") is not True
            or contract.get("outcome") != expected[1]
            or contract.get("error_category") != expected[2]
            or contract.get("success_observation") is not False
        ):
            raise ValueError("gate report contains an invalid contract case")


def _validate_scenario_summary(value: object) -> None:
    if not isinstance(value, dict):
        raise ValueError("gate report scenario must be an object")
    if set(value) != {
        "schema_version",
        "scenario",
        "evidence_kind",
        "ok",
        "workspace_revision",
        "source_sha256",
        "preflight",
        "steps",
    }:
        raise ValueError("gate report scenario schema is not closed")
    revision = value.get("workspace_revision")
    digest = value.get("source_sha256")
    steps = value.get("steps")
    if (
        value.get("scenario") != EXPECTED_SCENARIO
        or type(value.get("schema_version")) is not int
        or value.get("schema_version") != 1
        or value.get("evidence_kind") != "real-pinned-matrix"
        or value.get("ok") is not True
        or type(revision) is not int
        or revision != 1
        or digest != EXPECTED_SOURCE_DIGEST
        or not isinstance(steps, list)
        or len(steps) != 5
    ):
        raise ValueError("gate report scenario correlation is incomplete")
    expected_preflight = {
        "metadata_contract": "metadata-v1",
        "sync_status": "succeeded",
        "compiler_tool": "styio",
        "compile_plan_contract": 1,
        "runtime_events_contract": 1,
        "runtime_event_stream": True,
        "package": "vityo/product-gate",
        "bin_target": "product-gate",
        "test_target": "product-gate-test",
    }
    if value.get("preflight") != expected_preflight:
        raise ValueError("gate report scenario preflight is incomplete")
    names = ("edit", "check", "test", "run", "observe")
    sessions: list[str] = []
    for index, step in enumerate(steps):
        expected_keys = {"name", "status", "workspace_revision", "source_sha256"}
        if 1 <= index <= 3:
            expected_keys.update({"owner_contract", "session_id_sha256"})
        if index == 4:
            expected_keys.update({"session_id_sha256", "eventKind", "observation_sha256"})
        if (
            not isinstance(step, dict)
            or set(step) != expected_keys
            or step.get("name") != names[index]
            or step.get("status") != "succeeded"
            or type(step.get("workspace_revision")) is not int
            or step.get("workspace_revision") != revision
            or step.get("source_sha256") != digest
        ):
            raise ValueError("gate report scenario step is stale or incomplete")
        if 1 <= index <= 3:
            session = step.get("session_id_sha256")
            if (
                step.get("owner_contract") != "pafio-current+styio-files-v1"
                or not isinstance(session, str)
                or DIGEST.fullmatch(session) is None
            ):
                raise ValueError("gate report workflow session is invalid")
            sessions.append(session)
    observe = steps[4]
    assert isinstance(observe, dict)
    if (
        len(set(sessions)) != 3
        or observe.get("session_id_sha256") != sessions[2]
        or observe.get("eventKind") != "log.emitted"
        or observe.get("observation_sha256") != EXPECTED_OBSERVATION_DIGEST
    ):
        raise ValueError("gate report observation is not bound to the run session")


def validate_pins(
    matrix: dict[str, object], *, styio_commit: str, pafio_commit: str
) -> None:
    if set(matrix) != {"schema_version", "capability", "repositories"}:
        raise ValueError("product matrix schema is not closed")
    if type(matrix.get("schema_version")) is not int or matrix["schema_version"] != 1:
        raise ValueError("product matrix schema is unsupported")
    if matrix.get("capability") != EXPECTED_CAPABILITY:
        raise ValueError("product matrix capability is unsupported")
    repositories = matrix.get("repositories")
    if not isinstance(repositories, dict):
        raise ValueError("product matrix repository pins are missing")
    if set(repositories) != {"styio", "pafio"} or any(
        not isinstance(repositories.get(name), str)
        or COMMIT.fullmatch(str(repositories[name])) is None
        for name in ("styio", "pafio")
    ):
        raise ValueError("product matrix repository pins are not fixed commits")
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
    if report.get("ptyDependency") != {
        "name": "portable-pty",
        "version": "0.9.0",
        "owner": "vityod",
    }:
        raise ValueError("native PTY report does not use the fixed vityod PTY dependency")
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
    parser.add_argument("--platform", choices=("linux", "macos", "windows"), required=True)
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

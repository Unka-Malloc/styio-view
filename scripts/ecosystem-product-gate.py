#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import time
from dataclasses import dataclass
from pathlib import Path, PureWindowsPath
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
PRODUCT_TEST = ROOT / "products/vityo_app/test/local_product_workflow_test.dart"
PRODUCT_MARKER = b"VITYO_PRODUCT_REPORT "
CONTRACT_MARKER = b"VITYO_PRODUCT_CONTRACT_REPORT "
FLUTTER_PRINT_PREFIX = b"Shell: "
GATE_ID = "vityo-desktop-product-gate"
CAPABILITY = "trusted-desktop-ide-loop"
SCENARIO = "trusted-desktop-styio-loop"
PLATFORMS = {"linux", "macos", "windows"}
OUTER_TIMEOUT_SECONDS = 600
TERMINATION_GRACE_SECONDS = 5
OUTER_STREAM_LIMIT = 1_048_576
MARKER_LIMIT = 65_536
PROJECTED_STRING_LIMIT = 512
DIGEST = re.compile(r"^[0-9a-f]{64}$")
EXPECTED_SOURCE_DIGEST = hashlib.sha256(b'>_("vityo-observed-r1")\n').hexdigest()
EXPECTED_OBSERVATION_DIGEST = hashlib.sha256(b"vityo-observed-r1").hexdigest()


@dataclass(frozen=True)
class ProcessResult:
    returncode: int
    stdout: bytes
    stderr: bytes
    failure_category: str | None = None


def enabled(value: str | None) -> bool:
    return (value or "").strip().lower() in {"1", "true", "yes", "on"}


def running_in_ci(environment: dict[str, str] | None = None) -> bool:
    env = os.environ if environment is None else environment
    return enabled(env.get("CI")) or enabled(env.get("GITHUB_ACTIONS"))


def host_platform() -> str:
    if sys.platform == "darwin":
        return "macos"
    if sys.platform == "win32":
        return "windows"
    return "linux"


def write_product_workspace(root: Path, *, pafio_bin: Path) -> Path:
    result = subprocess.run(
        [
            str(pafio_bin),
            "new",
            "vityo/product-gate",
            str(root),
            "--bin",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise ValueError("pafio new failed while creating the product workspace")
    manifest = root / "pafio.toml"
    if not manifest.is_file():
        raise ValueError("pafio new did not create pafio.toml")
    source = root / "src/main.styio"
    test_source = root / "tests/product_gate.styio"
    source.parent.mkdir(parents=True, exist_ok=True)
    test_source.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text(
        '[pafio]\nmanifest-version = 1\n\n[package]\nname = "vityo/product-gate"\n'
        'version = "0.1.0"\nedition = "2026"\n\n[build]\nimplicit-std = true\n\n'
        '[[bin]]\nname = "product-gate"\npath = "src/main.styio"\n\n'
        '[[test]]\nname = "product-gate-test"\npath = "tests/product_gate.styio"\n',
        encoding="utf-8",
        newline="\n",
    )
    source.write_text('>_("vityo-before-edit")\n', encoding="utf-8", newline="\n")
    test_source.write_text(
        '>_("vityo-product-gate-test")\n', encoding="utf-8", newline="\n"
    )
    return manifest


def build_product_environment(
    *, temp_root: Path, styio_bin: Path, pafio_bin: Path
) -> dict[str, str]:
    workspace = temp_root / "desktop-single"
    manifest = write_product_workspace(workspace, pafio_bin=pafio_bin)
    return {
        **os.environ,
        "VITYO_PRODUCT_GATE": "1",
        "VITYO_PAFIO_BIN": str(pafio_bin),
        "VITYO_STYIO_BIN": str(styio_bin),
        "VITYO_PRODUCT_WORKSPACE_ROOT": str(workspace),
        "VITYO_PRODUCT_MANIFEST_PATH": str(manifest),
    }


def run_bounded_process(
    command: list[str], *, cwd: Path, env: dict[str, str]
) -> ProcessResult:
    process = subprocess.Popen(
        command,
        cwd=cwd,
        env=env,
        shell=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if process.stdout is None or process.stderr is None:
        raise OSError("product process streams are unavailable")

    buffers = (bytearray(), bytearray())
    exceeded = threading.Event()

    def drain(stream: Any, target: bytearray) -> None:
        for chunk in iter(lambda: stream.read(8192), b""):
            remaining = OUTER_STREAM_LIMIT + 1 - len(target)
            if remaining > 0:
                target.extend(chunk[:remaining])
            if len(target) > OUTER_STREAM_LIMIT or len(chunk) > remaining:
                exceeded.set()

    threads = (
        threading.Thread(target=drain, args=(process.stdout, buffers[0]), daemon=True),
        threading.Thread(target=drain, args=(process.stderr, buffers[1]), daemon=True),
    )
    for thread in threads:
        thread.start()

    deadline = time.monotonic() + OUTER_TIMEOUT_SECONDS
    category: str | None = None
    while process.poll() is None:
        if exceeded.is_set():
            category = "product_output_limit_exceeded"
            _terminate_process(process)
            break
        if time.monotonic() >= deadline:
            category = "product_process_timeout"
            _terminate_process(process)
            break
        time.sleep(0.02)
    returncode = process.wait()
    for thread in threads:
        thread.join()
    process.stdout.close()
    process.stderr.close()
    if exceeded.is_set():
        category = "product_output_limit_exceeded"
    return ProcessResult(returncode, bytes(buffers[0]), bytes(buffers[1]), category)


def _terminate_process(process: subprocess.Popen[bytes]) -> None:
    process.terminate()
    try:
        process.wait(timeout=TERMINATION_GRACE_SECONDS)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


def parse_product_reports(
    data: bytes | str,
) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    encoded = data.encode("utf-8") if isinstance(data, str) else data
    products: list[dict[str, object]] = []
    contracts: list[dict[str, object]] = []
    for output_line in encoded.splitlines():
        line = (
            output_line[len(FLUTTER_PRINT_PREFIX) :]
            if output_line.startswith(FLUTTER_PRINT_PREFIX)
            else output_line
        )
        present = [
            (marker, destination)
            for marker, destination in (
                (PRODUCT_MARKER, products),
                (CONTRACT_MARKER, contracts),
            )
            if marker in line
        ]
        if not present:
            continue
        if len(present) != 1 or not line.startswith(present[0][0]):
            raise ValueError("product marker must start its own output line")
        marker, destination = present[0]
        raw_line = line[len(marker) :]
        if len(raw_line) > MARKER_LIMIT:
            raise ValueError("product marker violates its byte limit")
        raw = raw_line.strip()
        if not raw:
            raise ValueError("product marker violates its byte limit")
        value = json.loads(
            raw.decode("utf-8"),
            object_pairs_hook=_unique_json_object,
            parse_constant=_reject_json_constant,
        )
        if not isinstance(value, dict):
            raise ValueError("product marker must contain one JSON object")
        destination.append(value)
    return products, contracts


def validate_product_reports(
    scenarios: list[dict[str, object]], contracts: list[dict[str, object]]
) -> None:
    if len(scenarios) != 1 or len(contracts) != 3:
        raise ValueError("exactly one scenario and three contract reports are required")
    _validate_scenario(scenarios[0])
    expected_contracts = (
        ("missing-styio", "blocked", "styio_missing"),
        (
            "incompatible-machine-contract",
            "blocked",
            "styio_machine_contract_incompatible",
        ),
        ("compiler-execution-failure", "failed", "compiler_execution_failed"),
    )
    for report, expected in zip(contracts, expected_contracts, strict=True):
        _validate_contract(report, expected)
    _validate_privacy({"scenarios": scenarios, "contract_cases": contracts})


def _validate_scenario(report: dict[str, object]) -> None:
    _closed(
        report,
        {
            "schema_version",
            "scenario",
            "evidence_kind",
            "ok",
            "workspace_revision",
            "source_sha256",
            "preflight",
            "steps",
        },
        "scenario",
    )
    revision = report["workspace_revision"]
    source_digest = report["source_sha256"]
    if (
        not _is_int(report["schema_version"], 1)
        or report["scenario"] != SCENARIO
        or report["evidence_kind"] != "real-pinned-matrix"
        or report["ok"] is not True
        or not isinstance(revision, int)
        or isinstance(revision, bool)
        or revision != 1
        or source_digest != EXPECTED_SOURCE_DIGEST
    ):
        raise ValueError("scenario identity or correlation is invalid")

    preflight = _object(report["preflight"], "preflight")
    runtime_events_contract = preflight.get("runtime_events_contract")
    expected_preflight = {
        "metadata_contract": "metadata-v1",
        "sync_status": "succeeded",
        "compiler_tool": "styio",
        "compile_plan_contract": 1,
        "runtime_events_contract": runtime_events_contract,
        "runtime_event_stream": True,
        "package": "vityo/product-gate",
        "bin_target": "product-gate",
        "test_target": "product-gate-test",
    }
    _closed(preflight, set(expected_preflight), "preflight")
    if (
        preflight != expected_preflight
        or not _is_int(preflight["compile_plan_contract"], 1)
        or type(runtime_events_contract) is not int
        or runtime_events_contract not in {1, 2}
    ):
        raise ValueError("scenario preflight is incomplete")

    steps = _array(report["steps"], "steps")
    names = ("edit", "check", "test", "run", "observe")
    if len(steps) != len(names):
        raise ValueError("scenario must contain exactly five steps")
    session_digests: list[str] = []
    for index, item in enumerate(steps):
        step = _object(item, "step")
        expected_keys = {"name", "status", "workspace_revision", "source_sha256"}
        if 1 <= index <= 3:
            expected_keys.update({"owner_contract", "session_id_sha256"})
        if index == 4:
            expected_keys.update(
                {"session_id_sha256", "eventKind", "observation_sha256"}
            )
        _closed(step, expected_keys, "step")
        if (
            step["name"] != names[index]
            or step["status"] != "succeeded"
            or type(step["workspace_revision"]) is not int
            or step["workspace_revision"] != revision
            or step["source_sha256"] != source_digest
        ):
            raise ValueError("scenario step is stale, reordered, or unsuccessful")
        if 1 <= index <= 3:
            if (
                step["owner_contract"] != "pafio-current+styio-files-v1"
                or not _is_digest(step["session_id_sha256"])
            ):
                raise ValueError("workflow step lacks a valid execution session")
            session_digests.append(str(step["session_id_sha256"]))
    if len(set(session_digests)) != 3:
        raise ValueError("workflow sessions must be distinct")
    observe = _object(steps[4], "observe")
    if (
        observe["session_id_sha256"] != session_digests[2]
        or observe["eventKind"] != "log.emitted"
        or observe["observation_sha256"] != EXPECTED_OBSERVATION_DIGEST
    ):
        raise ValueError("observation is not bound to the run session")


def _validate_contract(
    report: dict[str, object], expected: tuple[str, str, str]
) -> None:
    _closed(
        report,
        {
            "schema_version",
            "scenario",
            "evidence_kind",
            "case",
            "accepted",
            "outcome",
            "error_category",
            "success_observation",
        },
        "contract report",
    )
    if (
        not _is_int(report["schema_version"], 1)
        or report["scenario"] != SCENARIO
        or report["evidence_kind"] != "deterministic-contract"
        or report["case"] != expected[0]
        or report["accepted"] is not True
        or report["outcome"] != expected[1]
        or report["error_category"] != expected[2]
        or report["success_observation"] is not False
    ):
        raise ValueError("contract report does not match its frozen case")


def _validate_privacy(value: object, parent: str = "report") -> None:
    if isinstance(value, dict):
        forbidden = {
            "stdout",
            "stderr",
            "source",
            "source_text",
            "receipt",
            "receipt_path",
            "runtime_events",
            "runtime_payload",
            "timestamp",
            "environment",
            "executable",
            "machine_identity",
            "token",
        }
        for key, child in value.items():
            normalized = str(key).lower()
            if (
                normalized in forbidden
                or "secret" in normalized
                or "password" in normalized
            ):
                raise ValueError(f"{parent} contains a forbidden evidence field")
            _validate_privacy(child, f"{parent}.{key}")
    elif isinstance(value, list):
        for child in value:
            _validate_privacy(child, parent)
    elif isinstance(value, str):
        if len(value.encode("utf-8")) > PROJECTED_STRING_LIMIT:
            raise ValueError(f"{parent} exceeds the projected string limit")
        if Path(value).is_absolute() or PureWindowsPath(value).is_absolute():
            raise ValueError(f"{parent} exposes an absolute path")


def _payload(
    *,
    platform: str,
    required: bool,
    process: ProcessResult | None,
    scenarios: list[dict[str, object]],
    contracts: list[dict[str, object]],
    failure: str | None,
    skipped: bool,
) -> dict[str, object]:
    valid = (
        process is not None
        and process.returncode == 0
        and process.failure_category is None
        and failure is None
        and len(scenarios) == 1
        and len(contracts) == 3
    )
    return {
        "schema_version": 1,
        "gate": GATE_ID,
        "platform": platform,
        "capability": CAPABILITY,
        "evidence_kind": "real-pinned-matrix",
        "ok": valid,
        "required": required,
        "skipped": skipped,
        "failure_category": None if valid else failure,
        "steps": [
            {
                "name": "product-process",
                "ok": bool(
                    process
                    and process.returncode == 0
                    and process.failure_category is None
                ),
            },
            {"name": "real-scenario", "ok": len(scenarios) == 1 and valid},
            {
                "name": "deterministic-contract-cases",
                "ok": len(contracts) == 3 and valid,
            },
        ],
        "report": {
            "scenario_count": len(scenarios),
            "scenarios": scenarios,
            "contract_case_count": len(contracts),
            "contract_cases": contracts,
        },
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", choices=("linux", "windows", "macos"))
    parser.add_argument("--styio-bin", type=Path)
    parser.add_argument("--pafio-bin", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--require-real-matrix", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(sys.argv[1:] if argv is None else argv)

    required = args.require_real_matrix or running_in_ci()
    requested_platform = args.platform or os.environ.get("VITYO_PRODUCT_PLATFORM")
    platform = (
        requested_platform if requested_platform in PLATFORMS else host_platform()
    )
    styio = args.styio_bin or _env_path("VITYO_STYIO_BIN")
    pafio = args.pafio_bin or _env_path("VITYO_PAFIO_BIN")
    output = args.output or _env_path("VITYO_PRODUCT_GATE_OUTPUT")
    missing = (
        requested_platform not in PLATFORMS
        or styio is None
        or not styio.is_file()
        or pafio is None
        or not pafio.is_file()
    )
    if missing:
        payload = _payload(
            platform=platform,
            required=required,
            process=None,
            scenarios=[],
            contracts=[],
            failure="matrix_inputs_unavailable",
            skipped=True,
        )
    else:
        try:
            with tempfile.TemporaryDirectory(prefix="vityo_product_gate_") as name:
                environment = build_product_environment(
                    temp_root=Path(name),
                    styio_bin=styio.resolve(),
                    pafio_bin=pafio.resolve(),
                )
                process = run_bounded_process(
                    ["flutter", "test", str(PRODUCT_TEST)],
                    cwd=ROOT / "products/vityo_app",
                    env=environment,
                )
            failure = process.failure_category
            if failure is None and process.returncode != 0:
                failure = "product_test_failed"
            if failure is None:
                try:
                    scenarios, contracts = parse_product_reports(process.stdout)
                    validate_product_reports(scenarios, contracts)
                except (KeyError, TypeError, ValueError):
                    failure = "product_report_invalid"
                    scenarios, contracts = [], []
            else:
                scenarios, contracts = [], []
            if failure is not None:
                # Invalid, partial, stale, or failed child reports are untrusted
                # input. Never copy their fields into the machine report.
                scenarios = []
                contracts = []
            payload = _payload(
                platform=platform,
                required=required,
                process=process,
                scenarios=scenarios,
                contracts=contracts,
                failure=failure,
                skipped=False,
            )
        except (OSError, UnicodeError, ValueError, json.JSONDecodeError):
            payload = _payload(
                platform=platform,
                required=required,
                process=None,
                scenarios=[],
                contracts=[],
                failure="product_report_invalid",
                skipped=False,
            )

    _write_payload(output, payload)
    print(json.dumps(payload, sort_keys=True) if args.json else _human_summary(payload))
    return 0 if payload["ok"] or (payload["skipped"] and not required) else 1


def _closed(value: dict[str, object], keys: set[str], name: str) -> None:
    if set(value) != keys:
        raise ValueError(f"{name} is not a closed schema")


def _object(value: object, name: str) -> dict[str, object]:
    if not isinstance(value, dict) or not all(isinstance(key, str) for key in value):
        raise ValueError(f"{name} must be a JSON object")
    return value


def _array(value: object, name: str) -> list[object]:
    if not isinstance(value, list):
        raise ValueError(f"{name} must be a JSON array")
    return value


def _is_digest(value: object) -> bool:
    return isinstance(value, str) and DIGEST.fullmatch(value) is not None


def _is_int(value: object, expected: int) -> bool:
    return type(value) is int and value == expected


def _unique_json_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    value: dict[str, object] = {}
    for key, child in pairs:
        if key in value:
            raise ValueError("product marker contains duplicate JSON fields")
        value[key] = child
    return value


def _reject_json_constant(value: str) -> None:
    raise ValueError(f"product marker contains invalid JSON constant: {value}")


def _env_path(name: str) -> Path | None:
    value = os.environ.get(name)
    return Path(value) if value else None


def _write_payload(path: Path | None, payload: dict[str, object]) -> None:
    if path is None:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def _human_summary(payload: dict[str, object]) -> str:
    status = "PASS" if payload["ok"] is True else "FAIL"
    return f"[{status}] {GATE_ID} ({payload['platform']})"


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from types import ModuleType


ROOT = Path(__file__).resolve().parents[1]
PRODUCT_TEST = ROOT / "products" / "vityo_app" / "test" / "local_product_workflow_test.dart"
REPORT_MARKER = "VITYO_PRODUCT_REPORT "
GATE_ID = "vityo-ecosystem-owner-gate"
CAPABILITY = "pafio-styio-owner-composition"


def enabled(value: str | None) -> bool:
    return (value or "").strip().lower() in {"1", "true", "yes", "on"}


def running_in_ci(environment: dict[str, str] | None = None) -> bool:
    env = os.environ if environment is None else environment
    return enabled(env.get("CI")) or enabled(env.get("GITHUB_ACTIONS"))


def parse_product_reports(text: str) -> list[dict[str, object]]:
    reports: list[dict[str, object]] = []
    for line in text.splitlines():
        marker_index = line.find(REPORT_MARKER)
        if marker_index < 0:
            continue
        raw = line[marker_index + len(REPORT_MARKER) :].strip()
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if isinstance(payload, dict):
            reports.append(payload)
    return reports


def load_pafio_workspace_factory(pafio_root: Path) -> ModuleType:
    script = pafio_root / "scripts" / "ecosystem-product-gate.py"
    if not script.is_file():
        raise ValueError("Pafio product workspace factory is unavailable")
    spec = importlib.util.spec_from_file_location("pafio_product_workspace_factory", script)
    if spec is None or spec.loader is None:
        raise ValueError("Pafio product workspace factory cannot be loaded")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    required = ("write_hosted_workspace",)
    if any(not callable(getattr(module, name, None)) for name in required):
        raise ValueError("Pafio product workspace factory contract is incomplete")
    return module


def build_product_environment(
    *,
    factory: ModuleType,
    temp_root: Path,
    styio_bin: Path,
    pafio_bin: Path,
) -> dict[str, str]:
    single_root = temp_root / "desktop-single"
    single_manifest = factory.write_hosted_workspace(single_root)

    environment = os.environ.copy()
    environment.update(
        {
            "VITYO_PRODUCT_GATE": "1",
            "VITYO_PAFIO_BIN": str(pafio_bin),
            "VITYO_STYIO_BIN": str(styio_bin),
            "VITYO_PRODUCT_WORKSPACE_ROOT": str(single_root),
            "VITYO_PRODUCT_MANIFEST_PATH": str(single_manifest),
        }
    )
    return environment


def result_payload(
    *, platform: str, ok: bool, returncode: int, reports: list[dict[str, object]]
) -> dict[str, object]:
    return {
        "gate": GATE_ID,
        "platform": platform,
        "capability": CAPABILITY,
        "ok": ok,
        "steps": [
            {
                "name": "pafio-metadata-and-system-styio",
                "ok": returncode == 0,
                "returncode": returncode,
            },
            {
                "name": "structured-owner-adapter-scenarios",
                "ok": bool(reports),
                "scenario_count": len(reports),
            },
        ],
        "report": {"scenario_count": len(reports), "scenarios": reports},
    }


def skipped_payload(*, platform: str, required: bool, reason: str) -> dict[str, object]:
    return {
        "gate": GATE_ID,
        "platform": platform,
        "capability": CAPABILITY,
        "ok": False,
        "skipped": True,
        "required": required,
        "reason": reason,
        "report": {"scenario_count": 0, "scenarios": []},
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", choices=("linux", "windows", "macos"))
    parser.add_argument("--styio-bin", type=Path)
    parser.add_argument("--pafio-bin", type=Path)
    parser.add_argument("--pafio-root", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--require-real-matrix", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(sys.argv[1:] if argv is None else argv)

    required = args.require_real_matrix or running_in_ci()
    platform = args.platform or os.environ.get("VITYO_PRODUCT_PLATFORM", "unknown")
    styio_bin = args.styio_bin or _env_path("VITYO_STYIO_BIN")
    pafio_bin = args.pafio_bin or _env_path("VITYO_PAFIO_BIN")
    pafio_root = args.pafio_root or _env_path("VITYO_PAFIO_ROOT")
    output_path = args.output or _env_path("VITYO_PRODUCT_GATE_OUTPUT")
    missing = [
        name
        for name, value in (
            ("platform", platform if platform in {"linux", "windows", "macos"} else None),
            ("Styio binary", styio_bin if styio_bin and styio_bin.is_file() else None),
            ("Pafio binary", pafio_bin if pafio_bin and pafio_bin.is_file() else None),
            ("Pafio repository", pafio_root if pafio_root and pafio_root.is_dir() else None),
        )
        if value is None
    ]
    if missing:
        payload = skipped_payload(
            platform=platform,
            required=required,
            reason="real product matrix inputs unavailable: " + ", ".join(missing),
        )
        _write_payload(output_path, payload)
        print(json.dumps(payload, sort_keys=True) if args.json else payload["reason"])
        return 1 if required else 0

    assert styio_bin is not None and pafio_bin is not None and pafio_root is not None
    try:
        factory = load_pafio_workspace_factory(pafio_root)
        with tempfile.TemporaryDirectory(prefix="vityo_product_gate_") as temp_name:
            environment = build_product_environment(
                factory=factory,
                temp_root=Path(temp_name),
                styio_bin=styio_bin.resolve(),
                pafio_bin=pafio_bin.resolve(),
            )
            process = subprocess.run(
                ["flutter", "test", str(PRODUCT_TEST)],
                cwd=ROOT / "products" / "vityo_app",
                capture_output=True,
                text=True,
                env=environment,
            )
        reports = parse_product_reports(process.stdout)
        ok = process.returncode == 0 and bool(reports)
        payload = result_payload(
            platform=platform,
            ok=ok,
            returncode=process.returncode,
            reports=reports,
        )
    except (OSError, ValueError) as error:
        payload = skipped_payload(
            platform=platform,
            required=required,
            reason=str(error),
        )
        payload["skipped"] = False

    _write_payload(output_path, payload)
    print(json.dumps(payload, sort_keys=True) if args.json else _human_summary(payload))
    return 0 if payload.get("ok") is True else 1


def _env_path(name: str) -> Path | None:
    value = os.environ.get(name)
    return Path(value) if value else None


def _write_payload(path: Path | None, payload: dict[str, object]) -> None:
    if path is None:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _human_summary(payload: dict[str, object]) -> str:
    status = "PASS" if payload.get("ok") is True else "FAIL"
    return f"[{status}] {GATE_ID} ({payload.get('platform', 'unknown')})"


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_FLUTTER_DIR = Path("frontend/vityo_app")

REQUIRED_RELEASE_FILES = (
    Path("scripts/delivery-gate.sh"),
    Path("scripts/checkpoint-health.sh"),
    Path(".github/workflows/local-ci-gate.yml"),
    Path("frontend/vityo_app/README.md"),
    Path("frontend/vityo_app/pubspec.yaml"),
)

REQUIRED_README_MARKERS = (
    "## Release readiness gate",
    "python3 scripts/release-readiness-gate.py",
    "flutter build web --release",
)

REQUIRED_IDE_CAPABILITY_TESTS = {
    "app smoke": (
        Path("frontend/vityo_app/test/vityo_app_smoke_test.dart"),
        Path("frontend/vityo_app/test/app_bootstrap_test.dart"),
    ),
    "editor model and binding": (
        Path("frontend/vityo_app/test/editor_controller_editing_test.dart"),
        Path("frontend/vityo_app/test/document_resource_binding_test.dart"),
        Path("frontend/vityo_app/test/workspace_document_store_io_test.dart"),
        Path("frontend/vityo_app/test/hosted_workspace_document_store_test.dart"),
    ),
    "language service": (
        Path("frontend/vityo_app/test/local_styio_language_service_test.dart"),
        Path("frontend/vityo_app/test/styio_service_connector_test.dart"),
        Path("frontend/vityo_app/test/styio_syntax_validation_test.dart"),
        Path("frontend/vityo_app/test/styio_completion_feature_test.dart"),
        Path("frontend/vityo_app/test/styio_hover_feature_test.dart"),
        Path("frontend/vityo_app/test/styio_semantic_token_feature_test.dart"),
        Path("frontend/vityo_app/test/styio_navigation_feature_test.dart"),
        Path("frontend/vityo_app/test/styio_refactor_feature_test.dart"),
        Path("frontend/vityo_app/test/language_fixture_confidence_matrix_test.dart"),
    ),
    "runtime and toolchain": (
        Path("frontend/vityo_app/test/shell_runtime_file_binding_test.dart"),
        Path("frontend/vityo_app/test/execution_adapter_test.dart"),
        Path("frontend/vityo_app/test/toolchain_management_adapter_test.dart"),
        Path("frontend/vityo_app/test/toolchain_provenance_verifier_test.dart"),
        Path("frontend/vityo_app/test/toolchain_status_surface_test.dart"),
    ),
    "environment and persistence": (
        Path("frontend/vityo_app/test/file_system_manager_test.dart"),
        Path("frontend/vityo_app/test/platform_context_test.dart"),
        Path("frontend/vityo_app/test/system_compatibility_managers_test.dart"),
        Path("frontend/vityo_app/test/configuration_toolchain_test.dart"),
        Path("frontend/vityo_app/test/credential_data_store_test.dart"),
        Path("frontend/vityo_app/test/editor_session_data_store_test.dart"),
    ),
}


@dataclass(frozen=True)
class CheckResult:
    name: str
    ok: bool
    detail: str


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def parse_pubspec_fields(pubspec_text: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    for raw_line in pubspec_text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or ":" not in line:
            continue
        key, value = line.split(":", 1)
        if not raw_line.startswith(" ") and key:
            fields[key] = value.strip().strip("\"'")
    return fields


def check_required_files(repo_root: Path) -> list[CheckResult]:
    results: list[CheckResult] = []
    for relative_path in REQUIRED_RELEASE_FILES:
        path = repo_root / relative_path
        results.append(
            CheckResult(
                name=f"required file: {relative_path}",
                ok=path.is_file(),
                detail="present" if path.is_file() else "missing",
            )
        )
    return results


def check_pubspec(repo_root: Path, flutter_dir: Path) -> list[CheckResult]:
    pubspec_path = repo_root / flutter_dir / "pubspec.yaml"
    if not pubspec_path.is_file():
        return [CheckResult("pubspec metadata", False, f"missing: {pubspec_path}")]

    fields = parse_pubspec_fields(read_text(pubspec_path))
    checks = [
        ("pubspec name", fields.get("name") == "vityo_app", fields.get("name", "")),
        (
            "pubspec description",
            fields.get("description", "").startswith("Vityo IDE editor shell"),
            fields.get("description", ""),
        ),
        ("pubspec publish_to", fields.get("publish_to") == "none", fields.get("publish_to", "")),
        (
            "pubspec version",
            bool(re.fullmatch(r"\d+\.\d+\.\d+\+\d+", fields.get("version", ""))),
            fields.get("version", ""),
        ),
    ]
    return [
        CheckResult(name=name, ok=ok, detail=detail or "missing")
        for name, ok, detail in checks
    ]


def check_readme(repo_root: Path, flutter_dir: Path) -> list[CheckResult]:
    readme_path = repo_root / flutter_dir / "README.md"
    if not readme_path.is_file():
        return [CheckResult("release README markers", False, f"missing: {readme_path}")]

    text = read_text(readme_path)
    return [
        CheckResult(
            name=f"release README marker: {marker}",
            ok=marker in text,
            detail="present" if marker in text else "missing",
        )
        for marker in REQUIRED_README_MARKERS
    ]


def check_capability_tests(repo_root: Path) -> list[CheckResult]:
    results: list[CheckResult] = []
    for capability, paths in REQUIRED_IDE_CAPABILITY_TESTS.items():
        missing = [str(path) for path in paths if not (repo_root / path).is_file()]
        results.append(
            CheckResult(
                name=f"IDE capability test coverage: {capability}",
                ok=not missing,
                detail="present" if not missing else "missing: " + ", ".join(missing),
            )
        )
    return results


def collect_static_checks(repo_root: Path, flutter_dir: Path) -> list[CheckResult]:
    return [
        *check_required_files(repo_root),
        *check_pubspec(repo_root, flutter_dir),
        *check_readme(repo_root, flutter_dir),
        *check_capability_tests(repo_root),
    ]


def run_release_build(repo_root: Path, flutter_dir: Path) -> CheckResult:
    app_dir = repo_root / flutter_dir
    if not app_dir.is_dir():
        return CheckResult("flutter release build", False, f"missing: {app_dir}")

    proc = subprocess.run(
        ["flutter", "build", "web", "--release"],
        cwd=app_dir,
        check=False,
    )
    return CheckResult(
        name="flutter release build",
        ok=proc.returncode == 0,
        detail="flutter build web --release"
        if proc.returncode == 0
        else f"exit code {proc.returncode}",
    )


def result_payload(results: list[CheckResult]) -> dict[str, object]:
    failures = [result for result in results if not result.ok]
    return {
        "ok": not failures,
        "checks": [
            {
                "name": result.name,
                "ok": result.ok,
                "detail": result.detail,
            }
            for result in results
        ],
    }


def print_human(results: list[CheckResult]) -> None:
    for result in results:
        status = "ok" if result.ok else "error"
        print(f"[release-readiness] {status}: {result.name} ({result.detail})")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Vityo release readiness gate")
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    parser.add_argument("--flutter-dir", type=Path, default=DEFAULT_FLUTTER_DIR)
    parser.add_argument(
        "--skip-build",
        action="store_true",
        help="Only check static release evidence; skip flutter build web --release.",
    )
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON.")
    args = parser.parse_args(argv)

    repo_root = args.repo_root.resolve()
    results = collect_static_checks(repo_root, args.flutter_dir)
    if not args.skip_build:
        results.append(run_release_build(repo_root, args.flutter_dir))

    if args.json:
        print(json.dumps(result_payload(results), sort_keys=True))
    else:
        print_human(results)

    return 0 if all(result.ok for result in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())

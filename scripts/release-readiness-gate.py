#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import date
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_FLUTTER_DIR = Path("products/vityo_app")
TOOLING_MANIFEST_PATH = Path("toolchain/maintenance-tools.json")
TOOLING_POLICY_MIN_UPDATED = date(2026, 6, 19)
NIGHTLY_PLATFORMS = ("linux", "windows", "macos")
NIGHTLY_PACKAGE_FORMATS = {
    "linux": "deb",
    "windows": "zip-powershell",
    "macos": "dmg",
}
NIGHTLY_WORKFLOW_MARKERS = {
    "linux": ("package-nightly.py --platform linux", "sudo dpkg -i", "xvfb-run -a vityo"),
    "windows": ("package-nightly.py --platform windows", "install.ps1", "Start-Process"),
    "macos": ("package-nightly.py --platform macos", "hdiutil attach", "Contents/MacOS/Vityo"),
}
PRODUCT_MATRIX_WORKFLOW_MARKERS = {
    "linux": (
        "VITYO_PRODUCT_PLATFORM: linux",
        "product-gate-linux.json",
        "scripts/run-native-pty-matrix.py",
        "--platform linux",
        "--pty-report build/evidence/native-pty-linux.json",
        "product-matrix-linux.json",
    ),
    "windows": (
        "VITYO_PRODUCT_PLATFORM: windows",
        "product-gate-windows.json",
        "scripts/run-native-pty-matrix.py",
        "--platform windows",
        "--pty-report build/evidence/native-pty-windows.json",
        "product-matrix-windows.json",
    ),
    "macos": (
        "VITYO_PRODUCT_PLATFORM: macos",
        "product-gate-macos.json",
        "scripts/run-native-pty-matrix.py",
        "--platform macos",
        "--pty-report build/evidence/native-pty-macos.json",
        "product-matrix-macos.json",
    ),
}
RELEASE_VERSION_PATTERN = re.compile(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?")

REQUIRED_RELEASE_FILES = (
    Path("scripts/delivery-gate.sh"),
    Path("scripts/checkpoint-health.sh"),
    Path(".github/workflows/local-ci-gate.yml"),
    Path(".github/workflows/project-coverage-gate.yml"),
    Path("products/vityo_app/README.md"),
    Path("products/vityo_app/pubspec.yaml"),
    Path("scripts/package-nightly.py"),
    Path("scripts/ecosystem-product-gate.py"),
    Path("scripts/run-native-pty-matrix.py"),
    Path("scripts/record-product-matrix-evidence.py"),
    Path("packaging/README.md"),
    Path("toolchain/product-matrix.json"),
    TOOLING_MANIFEST_PATH,
)

REQUIRED_README_MARKERS = (
    "## Release readiness gate",
    "python3 scripts/release-readiness-gate.py",
    "flutter build web --release",
)

REQUIRED_IDE_CAPABILITY_TESTS = {
    "app smoke": (
        Path("products/vityo_app/test/vityo_app_smoke_test.dart"),
        Path("products/vityo_app/test/app_bootstrap_test.dart"),
    ),
    "editor model and binding": (
        Path("products/vityo_app/test/editor_controller_editing_test.dart"),
        Path("products/vityo_app/test/document_resource_binding_test.dart"),
        Path("products/vityo_app/test/workspace_document_store_io_test.dart"),
        Path("products/vityo_app/test/hosted_workspace_document_store_test.dart"),
    ),
    "language service": (
        Path("products/vityo_app/test/local_styio_language_service_test.dart"),
        Path("products/vityo_app/test/styio_service_connector_test.dart"),
        Path("products/vityo_app/test/styio_syntax_validation_test.dart"),
        Path("products/vityo_app/test/styio_completion_feature_test.dart"),
        Path("products/vityo_app/test/styio_hover_feature_test.dart"),
        Path("products/vityo_app/test/styio_semantic_token_feature_test.dart"),
        Path("products/vityo_app/test/styio_navigation_feature_test.dart"),
        Path("products/vityo_app/test/styio_refactor_feature_test.dart"),
        Path("products/vityo_app/test/language_fixture_confidence_matrix_test.dart"),
    ),
    "runtime and toolchain": (
        Path("products/vityo_app/test/shell_runtime_file_binding_test.dart"),
        Path("products/vityo_app/test/execution_adapter_test.dart"),
        Path("products/vityo_app/test/toolchain_controller_test.dart"),
        Path("products/vityo_app/test/toolchain_provenance_verifier_test.dart"),
        Path("products/vityo_app/test/toolchain_status_surface_test.dart"),
    ),
    "environment and persistence": (
        Path("products/vityo_app/test/file_system_manager_test.dart"),
        Path("products/vityo_app/test/platform_context_test.dart"),
        Path("products/vityo_app/test/system_compatibility_managers_test.dart"),
        Path("products/vityo_app/test/configuration_toolchain_test.dart"),
        Path("products/vityo_app/test/credential_data_store_test.dart"),
        Path("products/vityo_app/test/editor_session_data_store_test.dart"),
    ),
}

REQUIRED_MAINTENANCE_MODULES = {
    "adapter-contracts",
    "coordination",
    "docs-delivery",
    "foundation-environment",
    "module-platform",
    "runtime-agent",
    "shell-editor",
    "theme-ux",
}

STALE_TOOLING_TEXT = re.compile(
    r"\blegacy\b|\bold\b|\bdeprecated\b|\bv[0-9]+\b|"
    r"backward[-_ ]?compat|compatibility[-_ ]?mode",
    re.IGNORECASE,
)


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
            fields.get("description", "").startswith(
                "Vityo, the agent-native IDE for Styio"
            ),
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


def parse_policy_date(raw: object) -> date | None:
    if not isinstance(raw, str):
        return None
    try:
        return date.fromisoformat(raw)
    except ValueError:
        return None


def is_safe_relative_path(raw: object) -> bool:
    if not isinstance(raw, str) or not raw:
        return False
    normalized = raw.replace("\\", "/")
    if normalized.startswith("/"):
        return False
    path = Path(raw)
    return not path.is_absolute() and not path.drive and ".." not in normalized.split("/")


def string_list(raw: object) -> list[str]:
    if not isinstance(raw, list):
        return []
    return [item for item in raw if isinstance(item, str) and item]


def entry_text_fields(entry: dict[str, object]) -> list[str]:
    values: list[str] = []
    for key in ("id", "kind", "status", "path", "command"):
        value = entry.get(key)
        if isinstance(value, str):
            values.append(value)
    for key in ("scope", "owned_paths"):
        values.extend(string_list(entry.get(key)))
    return values


def has_stale_tooling_marker(entry: dict[str, object]) -> bool:
    return any(STALE_TOOLING_TEXT.search(value) for value in entry_text_fields(entry))


def load_tooling_manifest(path: Path) -> tuple[dict[str, object] | None, str | None]:
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        return None, str(exc)
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as exc:
        return None, f"invalid JSON: {exc}"
    if not isinstance(payload, dict):
        return None, "manifest root must be an object"
    return payload, None


def check_tooling_manifest(repo_root: Path) -> list[CheckResult]:
    manifest_path = repo_root / TOOLING_MANIFEST_PATH
    if not manifest_path.is_file():
        return [
            CheckResult(
                "maintenance tooling manifest",
                False,
                f"missing: {TOOLING_MANIFEST_PATH}",
            )
        ]

    manifest, error = load_tooling_manifest(manifest_path)
    if manifest is None:
        return [CheckResult("maintenance tooling manifest", False, error or "invalid")]

    results: list[CheckResult] = []
    policy = manifest.get("policy")
    policy = policy if isinstance(policy, dict) else {}
    tools = manifest.get("tools")
    tools = tools if isinstance(tools, list) else []
    skills = manifest.get("skills")
    skills = skills if isinstance(skills, list) else []
    modules = manifest.get("modules")
    modules = modules if isinstance(modules, list) else []

    updated = parse_policy_date(manifest.get("last_updated"))
    results.extend(
        [
            CheckResult(
                "maintenance tooling schema",
                manifest.get("schema") == 1,
                str(manifest.get("schema", "missing")),
            ),
            CheckResult(
                "maintenance tooling project",
                manifest.get("project") == "Vityo",
                str(manifest.get("project", "missing")),
            ),
            CheckResult(
                "maintenance tooling updated",
                updated is not None and updated >= TOOLING_POLICY_MIN_UPDATED,
                str(manifest.get("last_updated", "missing")),
            ),
            CheckResult(
                "maintenance tooling policy: current state",
                policy.get("current_state") == "current-only",
                str(policy.get("current_state", "missing")),
            ),
            CheckResult(
                "maintenance tooling policy: stale support",
                policy.get("stale_support") == "forbidden",
                str(policy.get("stale_support", "missing")),
            ),
            CheckResult(
                "maintenance tooling release gate",
                manifest.get("release_gate") == "scripts/release-readiness-gate.py",
                str(manifest.get("release_gate", "missing")),
            ),
            CheckResult(
                "maintenance tooling tools section",
                bool(tools),
                "present" if tools else "missing",
            ),
            CheckResult(
                "maintenance tooling skills section",
                bool(skills),
                "present" if skills else "missing",
            ),
            CheckResult(
                "maintenance tooling modules section",
                bool(modules),
                "present" if modules else "missing",
            ),
        ]
    )

    tool_ids: set[str] = set()
    duplicate_tool_ids: set[str] = set()
    for tool in tools:
        if not isinstance(tool, dict):
            results.append(CheckResult("maintenance tool entry", False, "tool must be an object"))
            continue
        tool_id = tool.get("id")
        if not isinstance(tool_id, str) or not tool_id:
            results.append(CheckResult("maintenance tool id", False, "missing"))
            continue
        if tool_id in tool_ids:
            duplicate_tool_ids.add(tool_id)
        tool_ids.add(tool_id)

        path = tool.get("path")
        safe_path = is_safe_relative_path(path)
        path_exists = safe_path and (repo_root / Path(str(path))).is_file()
        command = tool.get("command")
        results.extend(
            [
                CheckResult(
                    f"maintenance tool status: {tool_id}",
                    tool.get("status") == "current",
                    str(tool.get("status", "missing")),
                ),
                CheckResult(
                    f"maintenance tool path: {tool_id}",
                    path_exists,
                    str(path) if safe_path else "invalid path",
                ),
                CheckResult(
                    f"maintenance tool command: {tool_id}",
                    isinstance(command, str) and bool(command.strip()),
                    "present" if isinstance(command, str) and command.strip() else "missing",
                ),
                CheckResult(
                    f"maintenance tool current-only text: {tool_id}",
                    not has_stale_tooling_marker(tool),
                    "current" if not has_stale_tooling_marker(tool) else "stale marker",
                ),
            ]
        )

    results.append(
        CheckResult(
            "maintenance tool ids unique",
            not duplicate_tool_ids,
            "unique" if not duplicate_tool_ids else ", ".join(sorted(duplicate_tool_ids)),
        )
    )
    results.append(
        CheckResult(
            "maintenance tool release-readiness-gate registered",
            "release-readiness-gate" in tool_ids,
            "present" if "release-readiness-gate" in tool_ids else "missing",
        )
    )

    skill_ids: set[str] = set()
    duplicate_skill_ids: set[str] = set()
    for skill in skills:
        if not isinstance(skill, dict):
            results.append(CheckResult("maintenance skill entry", False, "skill must be an object"))
            continue
        skill_id = skill.get("id")
        if not isinstance(skill_id, str) or not skill_id:
            results.append(CheckResult("maintenance skill id", False, "missing"))
            continue
        if skill_id in skill_ids:
            duplicate_skill_ids.add(skill_id)
        skill_ids.add(skill_id)

        backing_tools = string_list(skill.get("backing_tools"))
        missing_tools = [tool_id for tool_id in backing_tools if tool_id not in tool_ids]
        results.extend(
            [
                CheckResult(
                    f"maintenance skill status: {skill_id}",
                    skill.get("status") == "current",
                    str(skill.get("status", "missing")),
                ),
                CheckResult(
                    f"maintenance skill tools: {skill_id}",
                    bool(backing_tools) and not missing_tools,
                    "present" if backing_tools and not missing_tools else "missing: " + ", ".join(missing_tools or ["backing_tools"]),
                ),
                CheckResult(
                    f"maintenance skill current-only text: {skill_id}",
                    not has_stale_tooling_marker(skill),
                    "current" if not has_stale_tooling_marker(skill) else "stale marker",
                ),
            ]
        )

    results.append(
        CheckResult(
            "maintenance skill ids unique",
            not duplicate_skill_ids,
            "unique" if not duplicate_skill_ids else ", ".join(sorted(duplicate_skill_ids)),
        )
    )

    module_ids: set[str] = set()
    duplicate_module_ids: set[str] = set()
    for module in modules:
        if not isinstance(module, dict):
            results.append(CheckResult("maintenance module entry", False, "module must be an object"))
            continue
        module_id = module.get("id")
        if not isinstance(module_id, str) or not module_id:
            results.append(CheckResult("maintenance module id", False, "missing"))
            continue
        if module_id in module_ids:
            duplicate_module_ids.add(module_id)
        module_ids.add(module_id)

        maintenance_tools = string_list(module.get("maintenance_tools"))
        missing_tools = [tool_id for tool_id in maintenance_tools if tool_id not in tool_ids]
        module_skills = string_list(module.get("skills"))
        missing_skills = [skill_id for skill_id in module_skills if skill_id not in skill_ids]
        runbook = module.get("runbook")
        runbook_exists = is_safe_relative_path(runbook) and (repo_root / Path(str(runbook))).is_file()
        results.extend(
            [
                CheckResult(
                    f"maintenance module status: {module_id}",
                    module.get("status") == "current",
                    str(module.get("status", "missing")),
                ),
                CheckResult(
                    f"maintenance module runbook: {module_id}",
                    runbook_exists,
                    str(runbook) if is_safe_relative_path(runbook) else "invalid runbook",
                ),
                CheckResult(
                    f"maintenance module tools: {module_id}",
                    bool(maintenance_tools) and not missing_tools,
                    "present" if maintenance_tools and not missing_tools else "missing: " + ", ".join(missing_tools or ["maintenance_tools"]),
                ),
                CheckResult(
                    f"maintenance module skills: {module_id}",
                    bool(module_skills) and not missing_skills,
                    "present" if module_skills and not missing_skills else "missing: " + ", ".join(missing_skills or ["skills"]),
                ),
                CheckResult(
                    f"maintenance module current-only text: {module_id}",
                    not has_stale_tooling_marker(module),
                    "current" if not has_stale_tooling_marker(module) else "stale marker",
                ),
            ]
        )

    missing_modules = sorted(REQUIRED_MAINTENANCE_MODULES - module_ids)
    results.extend(
        [
            CheckResult(
                "maintenance module ids unique",
                not duplicate_module_ids,
                "unique" if not duplicate_module_ids else ", ".join(sorted(duplicate_module_ids)),
            ),
            CheckResult(
                "maintenance module coverage",
                not missing_modules,
                "present" if not missing_modules else "missing: " + ", ".join(missing_modules),
            ),
        ]
    )

    return results


def load_json_object(path: Path) -> tuple[dict[str, object] | None, str | None]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return None, str(exc)
    if not isinstance(payload, dict):
        return None, "root must be an object"
    return payload, None


def check_nightly_packaging(repo_root: Path) -> list[CheckResult]:
    versions_path = repo_root / "packaging/release-versions.json"
    versions, versions_error = load_json_object(versions_path)
    if versions is None:
        return [CheckResult("Nightly release versions", False, versions_error or "invalid")]

    adapters = versions.get("platform_adapters")
    adapters = adapters if isinstance(adapters, dict) else {}
    core_version = versions.get("core_version")
    results = [
        CheckResult("Nightly release versions schema", versions.get("schema_version") == 1, str(versions.get("schema_version", "missing"))),
        CheckResult("Nightly core version", isinstance(core_version, str) and bool(RELEASE_VERSION_PATTERN.fullmatch(core_version)), str(core_version or "missing")),
    ]

    workflow_path = repo_root / ".github/workflows/local-ci-gate.yml"
    workflow_text = read_text(workflow_path) if workflow_path.is_file() else ""
    matrix, matrix_error = load_json_object(repo_root / "toolchain/product-matrix.json")
    matrix = matrix if matrix is not None else {}
    repositories = matrix.get("repositories")
    repositories = repositories if isinstance(repositories, dict) else {}
    fixed_commits_ok = all(
        isinstance(repositories.get(name), str)
        and bool(re.fullmatch(r"[0-9a-f]{40}", str(repositories.get(name))))
        for name in ("styio", "pafio")
    )
    results.extend(
        [
            CheckResult(
                "Product matrix schema",
                matrix.get("schema_version") == 1,
                matrix_error or str(matrix.get("schema_version", "missing")),
            ),
            CheckResult(
                "Product matrix capability",
                matrix.get("capability") == "trusted-desktop-ide-loop",
                str(matrix.get("capability", "missing")),
            ),
            CheckResult(
                "Product matrix fixed upstream commits",
                fixed_commits_ok,
                "fixed" if fixed_commits_ok else "missing or mutable",
            ),
            CheckResult(
                "Product matrix pinned checkouts",
                "steps.product-matrix.outputs.styio" in workflow_text
                and "steps.product-matrix.outputs.pafio" in workflow_text,
                "present" if "steps.product-matrix.outputs.styio" in workflow_text
                and "steps.product-matrix.outputs.pafio" in workflow_text else "missing",
            ),
            CheckResult(
                "Independent platform jobs",
                all(f"  {job}:" in workflow_text for job in ("local-ci-gate", "windows-native", "macos-native"))
                and "needs:" not in workflow_text,
                "independent" if "needs:" not in workflow_text else "cross-platform dependency present",
            ),
        ]
    )
    for platform in NIGHTLY_PLATFORMS:
        adapter_version = adapters.get(platform)
        results.append(
            CheckResult(
                f"Nightly {platform} adapter version",
                isinstance(adapter_version, str) and bool(RELEASE_VERSION_PATTERN.fullmatch(adapter_version)),
                str(adapter_version or "missing"),
            )
        )
        missing_workflow_markers = [
            marker
            for marker in (*NIGHTLY_WORKFLOW_MARKERS[platform], *PRODUCT_MATRIX_WORKFLOW_MARKERS[platform])
            if marker not in workflow_text
        ]
        results.append(
            CheckResult(
                f"Nightly {platform} install/start workflow",
                not missing_workflow_markers,
                "present" if not missing_workflow_markers else "missing: " + ", ".join(missing_workflow_markers),
            )
        )
        config_path = repo_root / f"packaging/{platform}/nightly.json"
        config, error = load_json_object(config_path)
        if config is None:
            results.append(CheckResult(f"Nightly {platform} package definition", False, error or "invalid"))
            continue

        signing = config.get("signing")
        signing = signing if isinstance(signing, dict) else {}
        signing_status = signing.get("status")
        signing_reason = signing.get("reason")
        automatic_updates = config.get("automatic_updates")
        source_keys = ["icon_relative_path", "installer_definition"]
        if platform == "windows":
            source_keys.append("uninstaller_definition")
        sources_ok = True
        source_detail: list[str] = []
        for key in source_keys:
            relative = config.get(key)
            valid = is_safe_relative_path(relative) and (repo_root / Path(str(relative))).is_file()
            sources_ok = sources_ok and valid
            if not valid:
                source_detail.append(f"{key}={relative or 'missing'}")
        build_path = config.get("build_relative_path")
        signing_ok = signing_status in {"configured", "explicit-gap"} and (
            signing_status == "configured" or isinstance(signing_reason, str) and bool(signing_reason.strip())
        )
        update_policy_ok = isinstance(automatic_updates, bool) and (
            signing_status == "configured" or automatic_updates is False
        )
        results.extend(
            [
                CheckResult(f"Nightly {platform} package schema", config.get("schema_version") == 1 and config.get("platform") == platform, str(config.get("schema_version", "missing"))),
                CheckResult(f"Nightly {platform} package format", config.get("package_format") == NIGHTLY_PACKAGE_FORMATS[platform], str(config.get("package_format", "missing"))),
                CheckResult(f"Nightly {platform} build path", is_safe_relative_path(build_path), str(build_path or "missing")),
                CheckResult(f"Nightly {platform} package sources", sources_ok, "present" if sources_ok else ", ".join(source_detail)),
                CheckResult(f"Nightly {platform} signing policy", signing_ok, str(signing_status or "missing")),
                CheckResult(f"Nightly {platform} automatic update policy", update_policy_ok, str(automatic_updates).lower()),
            ]
        )

    return results


def collect_static_checks(repo_root: Path, flutter_dir: Path) -> list[CheckResult]:
    return [
        *check_required_files(repo_root),
        *check_pubspec(repo_root, flutter_dir),
        *check_readme(repo_root, flutter_dir),
        *check_capability_tests(repo_root),
        *check_tooling_manifest(repo_root),
        *check_nightly_packaging(repo_root),
    ]


def run_release_build(repo_root: Path, flutter_dir: Path) -> CheckResult:
    app_dir = repo_root / flutter_dir
    if not app_dir.is_dir():
        return CheckResult("flutter release build", False, f"missing: {app_dir}")

    try:
        proc = subprocess.run(
            ["flutter", "build", "web", "--release"],
            cwd=app_dir,
            check=False,
        )
    except FileNotFoundError:
        return CheckResult(
            name="flutter release build",
            ok=False,
            detail="flutter executable not found in PATH",
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

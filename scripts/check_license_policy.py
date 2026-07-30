#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
PUBSPEC = REPO_ROOT / "products/vityo_app/pubspec.yaml"

ALLOWED_EXTERNAL_DART_PACKAGES = {
    "flutter",
    "crypto",
    "cupertino_icons",
    "shared_preferences",
    "path_provider",
    "pty2",
    "cryptography",
    "web",
    "flutter_test",
    "flutter_lints",
    "test",
}

FIRST_PARTY_DART_PACKAGE_PATHS = {
    "vityo_agent_protocol": "../../packages/vityo_agent_protocol",
}

FORBIDDEN_LICENSE_MARKERS = (
    "GPL-2.0",
    "GPL-3.0",
    "AGPL",
    "SSPL",
)


def parse_pubspec_dependencies() -> tuple[set[str], dict[str, str]]:
    if not PUBSPEC.is_file():
        return set(), {}
    packages: set[str] = set()
    local_paths: dict[str, str] = {}
    in_dependency_block = False
    current_package: str | None = None
    for line in PUBSPEC.read_text(encoding="utf-8").splitlines():
        if re.match(r"^(dependencies|dev_dependencies):\s*$", line):
            in_dependency_block = True
            current_package = None
            continue
        if in_dependency_block and line and not line.startswith(" "):
            in_dependency_block = False
            current_package = None
        if not in_dependency_block:
            continue
        match = re.match(r"^\s{2}([A-Za-z0-9_]+):", line)
        if match:
            current_package = match.group(1)
            packages.add(current_package)
            continue
        path_match = re.match(r"^\s{4}path:\s*(\S.*?)\s*$", line)
        if current_package is not None and path_match:
            local_paths[current_package] = path_match.group(1).strip("\"'")
    return packages, local_paths


def check_license_policy() -> list[str]:
    errors: list[str] = []
    if not PUBSPEC.is_file():
        return [f"missing pubspec: {PUBSPEC.relative_to(REPO_ROOT).as_posix()}"]
    packages, local_paths = parse_pubspec_dependencies()
    extra = sorted(
        packages
        - ALLOWED_EXTERNAL_DART_PACKAGES
        - FIRST_PARTY_DART_PACKAGE_PATHS.keys()
    )
    if extra:
        errors.append("pubspec contains packages outside license allowlist: " + ", ".join(extra))
    for package, expected_path in FIRST_PARTY_DART_PACKAGE_PATHS.items():
        if package not in packages:
            continue
        actual_path = local_paths.get(package)
        if actual_path != expected_path:
            errors.append(
                f"first-party package `{package}` must use repository path `{expected_path}`"
            )
            continue
        package_pubspec = (PUBSPEC.parent / actual_path / "pubspec.yaml").resolve()
        if not package_pubspec.is_file():
            errors.append(
                f"first-party package `{package}` is missing its repository pubspec"
            )

    third_party = REPO_ROOT / "docs/specs/THIRD-PARTY.md"
    if not third_party.is_file():
        errors.append("missing docs/specs/THIRD-PARTY.md")
        return errors

    for path in (third_party, REPO_ROOT / "DEPENDENCY-USAGE.md"):
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        for marker in FORBIDDEN_LICENSE_MARKERS:
            if marker in text:
                errors.append(f"{path.relative_to(REPO_ROOT).as_posix()}: forbidden license marker `{marker}`")
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Check Vityo license allowlist policy.")
    parser.add_argument("--json", action="store_true", help="Emit JSON.")
    args = parser.parse_args(argv)
    errors = check_license_policy()
    if args.json:
        print(json.dumps({"ok": not errors, "errors": errors}, indent=2, sort_keys=True))
    elif errors:
        print("[license-policy] FAILED", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
    else:
        print("[license-policy] OK")
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())

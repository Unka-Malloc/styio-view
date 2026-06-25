#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
PUBSPEC = REPO_ROOT / "frontend/vityo_app/pubspec.yaml"

ALLOWED_DART_PACKAGES = {
    "flutter",
    "crypto",
    "cupertino_icons",
    "shared_preferences",
    "path_provider",
    "cryptography",
    "web",
    "flutter_test",
    "flutter_lints",
}

FORBIDDEN_LICENSE_MARKERS = (
    "GPL-2.0",
    "GPL-3.0",
    "AGPL",
    "SSPL",
)


def parse_pubspec_dependencies() -> set[str]:
    if not PUBSPEC.is_file():
        return set()
    packages: set[str] = set()
    in_dependency_block = False
    for line in PUBSPEC.read_text(encoding="utf-8").splitlines():
        if re.match(r"^(dependencies|dev_dependencies):\s*$", line):
            in_dependency_block = True
            continue
        if in_dependency_block and line and not line.startswith(" "):
            in_dependency_block = False
        if not in_dependency_block:
            continue
        match = re.match(r"^\s{2}([A-Za-z0-9_]+):", line)
        if match:
            packages.add(match.group(1))
    return packages


def check_license_policy() -> list[str]:
    errors: list[str] = []
    if not PUBSPEC.is_file():
        return [f"missing pubspec: {PUBSPEC.relative_to(REPO_ROOT).as_posix()}"]
    packages = parse_pubspec_dependencies()
    extra = sorted(packages - ALLOWED_DART_PACKAGES)
    if extra:
        errors.append("pubspec contains packages outside license allowlist: " + ", ".join(extra))

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

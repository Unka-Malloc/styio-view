#!/usr/bin/env python3
"""Dependency Policy Gate — enforce that every pubspec.yaml dependency is registered in DEPENDENCY-USAGE.md.

Usage:
    python3 scripts/dependency-policy-gate.py              # check mode (default)
    python3 scripts/dependency-policy-gate.py --json       # machine-readable JSON output
    python3 scripts/dependency-policy-gate.py --help       # show help

Exit codes:
    0 — all dependencies registered
    1 — one or more unregistered dependencies found
    2 — configuration or parse error
"""

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUBSPEC_PATH = ROOT / "frontend" / "vityo_app" / "pubspec.yaml"
POLICY_PATH = ROOT / "DEPENDENCY-USAGE.md"

# Dependencies that are part of the Flutter/Dart SDK — always allowed without explicit registration.
SDK_DEPENDENCIES = {
    "flutter",
    "flutter_test",
    "flutter_driver",
    "flutter_web_plugins",
    "flutter_plugin_android_lifecycle",
    "dart",
    "meta",
    "collection",
    "async",
    "convert",
    "typed_data",
    "vector_math",
    "sky_engine",
    "characters",
    "material_color_utilities",
}


def parse_pubspec_dependencies(path: Path) -> dict[str, list[str]]:
    """Parse pubspec.yaml and return {section: [package_names]}.

    Sections returned: 'dependencies', 'dev_dependencies'.
    SDK dependencies (where version is omitted or 'sdk: flutter') are excluded.
    """
    if not path.exists():
        print(f"ERROR: pubspec.yaml not found at {path}", file=sys.stderr)
        sys.exit(2)

    text = path.read_text(encoding="utf-8")
    result: dict[str, list[str]] = {"dependencies": [], "dev_dependencies": []}

    in_section = None
    for line in text.splitlines():
        stripped = line.strip()
        indent = len(line) - len(line.lstrip())

        # Only top-level keys (zero indent) switch sections.
        # Nested indented lines (2+ spaces) are package entries or their properties.
        if indent == 0:
            if stripped == "dependencies:":
                in_section = "dependencies"
                continue
            elif stripped == "dev_dependencies:":
                in_section = "dev_dependencies"
                continue
            elif stripped.startswith("flutter:") or stripped.startswith("environment:"):
                in_section = None
                continue

        if in_section is None:
            continue

        # Match package entries at indent level 2 (normal deps) or 4 (nested under a dep).
        # We only care about entries at indent 2 — indent 4 means a property of a parent entry.
        # Properties like "sdk: flutter" at indent 4 should NOT be treated as package names.
        if indent > 2:
            continue

        match = re.match(r"^\s{2}(\w[\w\d_]*)\s*:", line)
        if match:
            pkg = match.group(1)
            # Only include if the version is on the same line (not an SDK reference)
            rest = line[match.end():].strip()
            if rest and rest != "":
                # Has an inline version specifier
                result[in_section].append(pkg)
            # If no inline version, it might be an SDK dep (e.g. "flutter:\n    sdk: flutter") — skip

    return result


def parse_policy_registered_deps(path: Path) -> set[str]:
    """Parse DEPENDENCY-USAGE.md and extract all registered package names from markdown tables."""
    if not path.exists():
        print(f"ERROR: DEPENDENCY-USAGE.md not found at {path}", file=sys.stderr)
        sys.exit(2)

    text = path.read_text(encoding="utf-8")
    registered = set()

    # Find table rows with backtick-quoted package names: | `package_name` | ...
    # Pattern matches the first column of a markdown table row containing a backtick-quoted name
    for line in text.splitlines():
        match = re.match(r"^\|\s*`([^`]+)`\s*\|", line)
        if match:
            name = match.group(1)
            # Skip header rows and placeholder entries
            if name.lower() in ("dependency", "---", "", "flutter (sdk)", "flutter_test (sdk)"):
                continue
            registered.add(name)

    return registered


def run_gate(json_output: bool = False) -> tuple[bool, list[str], list[str], list[dict]]:
    """Run the dependency policy gate.

    Returns: (passed, registered, unregistered, details_for_json)
    """
    pubspec = parse_pubspec_dependencies(PUBSPEC_PATH)
    policy = parse_policy_registered_deps(POLICY_PATH)

    all_deps = set(pubspec.get("dependencies", [])) | set(pubspec.get("dev_dependencies", []))
    registered_deps = sorted(all_deps & policy)
    unregistered_deps = sorted(all_deps - policy - SDK_DEPENDENCIES)
    sdk_deps_seen = sorted(all_deps & SDK_DEPENDENCIES)

    passed = len(unregistered_deps) == 0

    details = [
        {"status": "registered", "package": p, "section": _find_section(p, pubspec)}
        for p in registered_deps
    ] + [
        {"status": "unregistered", "package": p, "section": _find_section(p, pubspec)}
        for p in unregistered_deps
    ] + [
        {"status": "sdk_exempt", "package": p, "section": _find_section(p, pubspec)}
        for p in sdk_deps_seen
    ]

    if json_output:
        output = {
            "gate": "dependency-policy",
            "passed": passed,
            "pubspec_path": str(PUBSPEC_PATH),
            "policy_path": str(POLICY_PATH),
            "total_dependencies": len(all_deps),
            "registered": len(registered_deps),
            "unregistered": len(unregistered_deps),
            "sdk_exempt": len(sdk_deps_seen),
            "details": sorted(details, key=lambda d: d["package"]),
        }
        print(json.dumps(output, indent=2))
    else:
        print(f"[dependency-policy-gate] pubspec: {PUBSPEC_PATH}")
        print(f"[dependency-policy-gate] policy:  {POLICY_PATH}")
        print(f"[dependency-policy-gate] total dependencies found: {len(all_deps)}")
        print(f"[dependency-policy-gate] registered: {len(registered_deps)}")
        if registered_deps:
            for p in registered_deps:
                print(f"  ✓ {p}")
        print(f"[dependency-policy-gate] sdk/exempt: {len(sdk_deps_seen)}")
        if sdk_deps_seen:
            for p in sdk_deps_seen:
                print(f"  - {p} (SDK)")
        print(f"[dependency-policy-gate] unregistered: {len(unregistered_deps)}")
        if unregistered_deps:
            for p in unregistered_deps:
                print(f"  ✗ {p} — NOT in DEPENDENCY-USAGE.md")
        print(f"[dependency-policy-gate] result: {'PASS' if passed else 'FAIL'}")

    return passed, registered_deps, unregistered_deps, details


def _find_section(pkg: str, pubspec: dict[str, list[str]]) -> str:
    if pkg in pubspec.get("dependencies", []):
        return "dependencies"
    if pkg in pubspec.get("dev_dependencies", []):
        return "dev_dependencies"
    return "unknown"


def main():
    parser = argparse.ArgumentParser(description="Dependency Policy Gate")
    parser.add_argument("--json", action="store_true", help="Output machine-readable JSON")
    args = parser.parse_args()

    passed, _, unregistered, _ = run_gate(json_output=args.json)

    if not passed:
        print(
            "\nAction: Add the unregistered dependencies above to DEPENDENCY-USAGE.md "
            "with license evidence, source boundary, and usage boundary.",
            file=sys.stderr,
        )
        sys.exit(1)

    sys.exit(0)


if __name__ == "__main__":
    main()

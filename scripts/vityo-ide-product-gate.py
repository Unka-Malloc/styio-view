#!/usr/bin/env python3
"""Vityo IDE Product Gate.

Checks that Vityo's IDE capability upgrade baseline is present and correctly
structured.  This is a product-level gate, not a build gate — it verifies
documentation, test anchors, architecture boundaries, and hygiene invariants.

Usage:
    python3 scripts/vityo-ide-product-gate.py
    python3 scripts/vityo-ide-product-gate.py --mode checkpoint

Returns 0 when all checks pass.
"""

import argparse
import json
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


def fail(reason: str) -> None:
    print(f"FAIL: {reason}", file=sys.stderr)


def ok(message: str) -> None:
    print(f"  OK  {message}")


def check_file_exists(rel_path: str, description: str) -> bool:
    path = REPO_ROOT / rel_path
    if not path.is_file():
        fail(f"{description} — missing at {rel_path}")
        return False
    ok(f"{description} — {rel_path}")
    return True


def check_docs_index_ref(rel_path: str, description: str) -> bool:
    """Check that a document path is referenced in the appropriate docs index.
    For docs/design/ files, checks docs/design/INDEX.md.
    For docs/contracts/ files, checks docs/contracts/INDEX.md.
    Otherwise falls back to docs/INDEX.md."""
    # Determine the correct index
    if rel_path.startswith("docs/design/"):
        index_rel = "docs/design/INDEX.md"
    elif rel_path.startswith("docs/contracts/"):
        index_rel = "docs/contracts/INDEX.md"
    elif rel_path.startswith("docs/external/"):
        index_rel = "docs/external/INDEX.md"
    else:
        index_rel = "docs/INDEX.md"

    index_path = REPO_ROOT / index_rel
    if not index_path.is_file():
        fail(f"{index_rel} missing — cannot verify references for {description}")
        return False
    text = index_path.read_text(encoding="utf-8")
    # Normalize path: for sub-indexes, strip the subdirectory prefix
    # e.g. "docs/design/foo.md" → "foo.md" when checking docs/design/INDEX.md
    docs_rel = rel_path
    if docs_rel.startswith("docs/"):
        docs_rel = docs_rel[5:]
    # Remove the subdirectory prefix that matches the index location
    if index_rel.startswith("docs/") and index_rel.endswith("/INDEX.md"):
        subdir = index_rel[5:].removesuffix("/INDEX.md") + "/"
        if docs_rel.startswith(subdir):
            docs_rel = docs_rel[len(subdir):]
    if docs_rel not in text:
        fail(f"{description} — not referenced in {index_rel} ({docs_rel})")
        return False
    ok(f"{description} — referenced in {index_rel}")
    return True


def check_test_anchor(rel_glob: str, description: str) -> bool:
    """Check that at least one test file exists matching the glob."""
    import glob as gmod
    matches = gmod.glob(str(REPO_ROOT / rel_glob))
    if not matches:
        fail(f"{description} — no test file matching {rel_glob}")
        return False
    ok(f"{description} — found {len(matches)} test file(s)")
    return True


def check_view_ide_no_flutter_presentation() -> bool:
    """view_ide must not import Flutter Material presentation APIs."""
    view_ide_dir = REPO_ROOT / "frontend" / "vityo_app" / "lib" / "src" / "view_ide"
    if not view_ide_dir.is_dir():
        fail("view_ide directory missing")
        return False

    flutter_material_imports = [
        "package:flutter/material.dart",
        "package:flutter/widgets.dart",
        "package:flutter/cupertino.dart",
    ]

    violations = []
    for dart_file in view_ide_dir.rglob("*.dart"):
        content = dart_file.read_text(encoding="utf-8")
        for imp in flutter_material_imports:
            if imp in content:
                # Allow view_ide.dart barrel file and foundation/interaction wrappers
                # that coordinate but do not own presentation
                if "view_ide.dart" in str(dart_file):
                    continue
                # Check if the import is in a comment
                lines = content.split("\n")
                for line in lines:
                    line_stripped = line.strip()
                    if imp in line_stripped and not line_stripped.startswith("//"):
                        violations.append(
                            f"  {dart_file.relative_to(REPO_ROOT)}: "
                            f"imports '{imp}'"
                        )
                        break

    if violations:
        fail(
            f"view_ide imports Flutter presentation APIs "
            f"({len(violations)} violation(s)):"
        )
        for v in violations:
            print(v, file=sys.stderr)
        return False
    ok("view_ide does not import Flutter presentation APIs")
    return True


def check_view_render_imports_view_ide() -> bool:
    """view_render may import view_ide; this just confirms view_render exists."""
    view_render_dir = (
        REPO_ROOT / "frontend" / "vityo_app" / "lib" / "src" / "view_render"
    )
    if not view_render_dir.is_dir():
        fail("view_render directory missing")
        return False
    ok("view_render directory present")
    return True


def check_no_legacy_implementation() -> bool:
    """integration/, legacy backend_toolchain/, legacy language/ must not have
    new real business implementations."""
    legacy_dirs = [
        "frontend/vityo_app/lib/src/integration/",
        "frontend/vityo_app/lib/src/backend_toolchain/",
        "frontend/vityo_app/lib/src/language/",
    ]

    all_ok = True
    for legacy_dir in legacy_dirs:
        path = REPO_ROOT / legacy_dir
        if not path.is_dir():
            continue
        dart_files = list(path.rglob("*.dart"))
        # Legacy facades are allowed if they only re-export
        for dart_file in dart_files:
            content = dart_file.read_text(encoding="utf-8")
            non_export_lines = [
                l.strip()
                for l in content.split("\n")
                if l.strip()
                and not l.strip().startswith("//")
                and not l.strip().startswith("export ")
                and not l.strip().startswith("import ")
                and not l.strip().startswith("library ")
                and not l.strip() == ""
            ]
            if non_export_lines:
                # Check if it's just a class/enum definition for compatibility
                # Allow simple compatibility wrappers
                if any("class " in l or "enum " in l or "typedef " in l or "extension " in l for l in non_export_lines):
                    # Has real definitions — flag if not a simple re-export
                    if any(
                        "{" in l or "=>" in l
                        for l in non_export_lines
                        if not l.startswith("//")
                    ):
                        fail(
                            f"Legacy directory {legacy_dir} contains "
                            f"non-facade code: {dart_file.name}"
                        )
                        all_ok = False

    if all_ok:
        ok("No new real business implementations in legacy directories")
    return all_ok


def check_no_secrets_in_tracked() -> bool:
    """No API keys, tokens, or absolute home paths in tracked files."""
    secret_patterns = [
        r"sk-[a-zA-Z0-9]{20,}",
        r"OPENAI_API_KEY\s*=\s*[a-zA-Z0-9_-]{10,}",
        r"ANTHROPIC_API_KEY\s*=\s*[a-zA-Z0-9_-]{10,}",
    ]
    # Only check specific shared config / doc directories
    search_dirs = [
        "docs/",
        "scripts/",
        "toolchain/",
        "frontend/vityo_app/lib/src/view_ide/",
    ]

    all_ok = True
    import re

    for search_dir in search_dirs:
        path = REPO_ROOT / search_dir
        if not path.is_dir():
            continue
        for f in path.rglob("*"):
            if not f.is_file():
                continue
            if f.suffix in {".dart_tool", ".gitkeep"}:
                continue
            try:
                content = f.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue
            for pattern in secret_patterns:
                if re.search(pattern, content):
                    fail(f"Secret pattern found in {f.relative_to(REPO_ROOT)}")
                    all_ok = False

    # Also check for platform-specific home paths in source code only
    # (docs and scripts may intentionally document workspace paths)
    home_patterns = [
        r"/home/[a-zA-Z0-9_-]+/",  # Linux
        r"/Users/[a-zA-Z0-9_-]+/",  # macOS
        r"C:\\Users\\[a-zA-Z0-9_-]+\\",  # Windows
    ]
    exclude_dirs = {
        ".git",
        ".dart_tool",
        "build",
        "node_modules",
        "coverage",
        ".claude",
    }
    # Only check source code directories for home paths
    source_search_dirs = [
        "frontend/vityo_app/lib/src/view_ide/",
        "frontend/vityo_app/lib/src/view_render/",
    ]
    for search_dir in source_search_dirs:
        path = REPO_ROOT / search_dir
        if not path.is_dir():
            continue
        for f in path.rglob("*"):
            if not f.is_file():
                continue
            if any(ex in f.parts for ex in exclude_dirs):
                continue
            try:
                content = f.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue
            for pattern in home_patterns:
                for match in re.finditer(pattern, content):
                    matched = match.group()
                    # Allow known toolchain paths
                    if "linuxbrew" in matched or ".linuxbrew" in matched:
                        continue
                    if "brew" in matched.lower():
                        continue
                    # Allow intentional documentation examples
                    ctx_start = max(0, match.start() - 20)
                    ctx = content[ctx_start:match.end() + 5]
                    if "example" in ctx.lower() or "placeholder" in ctx.lower():
                        continue
                    fail(
                        f"Possible home path in {f.relative_to(REPO_ROOT)}: "
                        f"{matched}"
                    )
                    all_ok = False

    if all_ok:
        ok("No secrets or personal paths in tracked files")
    return all_ok


def check_no_tracked_build_output() -> bool:
    """No tracked build/cache/coverage/.dart_tool/node_modules output."""
    forbidden = [
        "build/",
        ".dart_tool/",
        "node_modules/",
        "coverage/",
        "__pycache__/",
        ".pytest_cache/",
    ]
    # Use git ls-files to check tracked files
    import subprocess
    try:
        result = subprocess.run(
            ["git", "-C", str(REPO_ROOT), "ls-files"],
            capture_output=True,
            text=True,
            check=True,
        )
        tracked = result.stdout.strip().split("\n")
    except (subprocess.CalledProcessError, FileNotFoundError):
        ok("Skipping build output check — git not available")
        return True

    violations = []
    for f in tracked:
        if not f:
            continue
        for forbidden_dir in forbidden:
            if f.startswith(forbidden_dir) or f"/{forbidden_dir}" in f:
                violations.append(f)

    if violations:
        for v in violations:
            fail(f"Tracked build output: {v}")
        return False
    ok("No tracked build/cache/coverage output")
    return True


def check_maintenance_tools_registered() -> bool:
    """This gate must be registered in toolchain/maintenance-tools.json."""
    tools_path = REPO_ROOT / "toolchain" / "maintenance-tools.json"
    if not tools_path.is_file():
        fail("toolchain/maintenance-tools.json missing")
        return False
    try:
        data = json.loads(tools_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        fail(f"maintenance-tools.json invalid JSON: {e}")
        return False

    tools = data.get("tools", [])
    gate_registered = any(
        t.get("id") == "vityo-ide-product-gate" for t in tools
    )
    if not gate_registered:
        fail("vityo-ide-product-gate not registered in maintenance-tools.json")
        return False
    ok("vityo-ide-product-gate registered in maintenance-tools.json")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="Vityo IDE Product Gate")
    parser.add_argument(
        "--mode",
        choices=["checkpoint", "strict"],
        default="checkpoint",
        help="Gate mode (default: checkpoint)",
    )
    parser.add_argument(
        "--verbose", action="store_true", help="Verbose output"
    )
    args = parser.parse_args()

    print("=== Vityo IDE Product Gate ===")
    print(f"Mode: {args.mode}")
    print()

    failures = 0

    # ── 1. Core design documents ───────────────────────────────────
    print("── Core Design Documents ──")
    if not check_file_exists(
        "docs/design/Vityo-IDE-Benchmark-Matrix.md",
        "IDE Benchmark Matrix",
    ):
        failures += 1
    else:
        failures += 0 if check_docs_index_ref(
            "docs/design/Vityo-IDE-Benchmark-Matrix.md",
            "Benchmark Matrix in docs index",
        ) else 1

    if not check_file_exists(
        "docs/design/Vityo-IDE-Capability-Maturity.md",
        "IDE Capability Maturity Model",
    ):
        failures += 1
    else:
        failures += 0 if check_docs_index_ref(
            "docs/design/Vityo-IDE-Capability-Maturity.md",
            "Maturity Model in docs index",
        ) else 1

    if not check_file_exists(
        "docs/design/Vityo-IDE-Interaction-Quality-Bar.md",
        "Interaction Quality Bar",
    ):
        failures += 1
    else:
        failures += 0 if check_docs_index_ref(
            "docs/design/Vityo-IDE-Interaction-Quality-Bar.md",
            "Quality Bar in docs index",
        ) else 1

    # ── 2. Test anchors ────────────────────────────────────────────
    print()
    print("── Test Anchors ──")
    if not check_test_anchor(
        "frontend/vityo_app/test/*command*",
        "Command registry tests",
    ):
        failures += 1
    if not check_test_anchor(
        "frontend/vityo_app/test/*agent*",
        "Agent context/permission/patch tests",
    ):
        failures += 1
    if not check_test_anchor(
        "frontend/vityo_app/test/*diagnostic*",
        "Diagnostic/project graph/runtime surface tests",
    ):
        failures += 1

    # ── 3. Architecture boundaries ─────────────────────────────────
    print()
    print("── Architecture Boundaries ──")
    if not check_view_ide_no_flutter_presentation():
        failures += 1
    if not check_view_render_imports_view_ide():
        failures += 1
    if not check_no_legacy_implementation():
        failures += 1

    # ── 4. Hygiene ─────────────────────────────────────────────────
    print()
    print("── Hygiene ──")
    if not check_no_secrets_in_tracked():
        failures += 1
    if not check_no_tracked_build_output():
        failures += 1

    # ── 5. Maintenance registration ────────────────────────────────
    print()
    print("── Maintenance Registration ──")
    if not check_maintenance_tools_registered():
        failures += 1

    # ── Summary ────────────────────────────────────────────────────
    print()
    print(f"=== {'PASS' if failures == 0 else 'FAIL'} ===")
    if failures > 0:
        print(f"{failures} check(s) failed.")
    else:
        print("All Vityo IDE product gate checks passed.")

    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

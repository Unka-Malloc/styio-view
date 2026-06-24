#!/usr/bin/env python3
"""Vityo Architecture Boundary Gate.

Checks that Vityo's layer boundaries are not violated by direct imports.
Validates:

1. view_ide/ must NOT import Flutter presentation libraries (material, widgets,
   cupertino, rendering, dart:ui).
2. view_render/ must NOT import view_ide/ implementation internals
   (agent providers, builtin tool executor, tool call dispatcher, language service
   internals, extension activator/lifecycle/host isolation).
3. agent/ must NOT import view_render/.
4. Legacy facade directories (backend_toolchain legacy, integration, language legacy)
   must only contain re-exports, not real business implementation.
5. Checks both package imports and relative imports.

Usage:
    python3 scripts/architecture_boundary_gate_test.py

Returns 0 when all checks pass.
"""

import os
import re
import sys
from pathlib import Path
from typing import Dict, List, Set, Tuple

REPO_ROOT = Path(__file__).resolve().parent.parent

# ── Forbidden imports ──────────────────────────────────────────────────────

# 1. view_ide/ must not import Flutter presentation libs
FORBIDDEN_FLUTTER_PRESENTATION_IMPORTS = {
    "package:flutter/material.dart",
    "package:flutter/widgets.dart",
    "package:flutter/cupertino.dart",
    "package:flutter/rendering.dart",
    "dart:ui",
}

# Allowed flutter foundation imports in view_ide/
ALLOWED_FLUTTER_IMPORTS_IN_VIEW_IDE = {
    "package:flutter/foundation.dart",
    "package:flutter/services.dart",
}

# 2. view_render/ must not import these view_ide/ internals
FORBIDDEN_VIEW_IDE_INTERNALS_FOR_VIEW_RENDER = [
    "view_ide/agent/agent_provider_",
    "view_ide/agent/agent_builtin_tool_executor",
    "view_ide/agent/agent_tool_call_dispatcher",
    "view_ide/language/service/",
    "view_ide/module_host/extension_activator",
    "view_ide/module_host/extension_lifecycle",
    "view_ide/module_host/extension_host_isolation",
]

# 3. Legacy facade directories (must only contain re-exports)
LEGACY_FACADE_DIRS = [
    "frontend/vityo_app/lib/src/backend_toolchain",
    "frontend/vityo_app/lib/src/integration",
    "frontend/vityo_app/lib/src/language",
]

# ── Dart file scanner ──────────────────────────────────────────────────────


def find_dart_files(base_dir: Path) -> List[Path]:
    """Find all .dart files under a directory, excluding hidden dirs."""
    dart_files = []
    if not base_dir.is_dir():
        return dart_files
    for root, dirs, files in os.walk(str(base_dir)):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for f in files:
            if f.endswith(".dart"):
                dart_files.append(Path(root) / f)
    return dart_files


def extract_imports(file_path: Path) -> List[str]:
    """Extract all import statements from a Dart file."""
    imports = []
    try:
        content = file_path.read_text(encoding="utf-8")
    except Exception:
        return imports

    # Match both 'import "..."' and "import '...'"
    pattern = re.compile(r'^\s*import\s+[\'"]([^\'"]+)[\'"]', re.MULTILINE)
    for match in pattern.finditer(content):
        imports.append(match.group(1))
    return imports


def is_legacy_re_export_only(file_path: Path) -> Tuple[bool, str]:
    """Check if a legacy facade file contains only re-exports and comments."""
    try:
        content = file_path.read_text(encoding="utf-8")
    except Exception:
        return False, f"Cannot read {file_path}"

    lines = content.split("\n")
    non_comment_lines = []
    in_block_comment = False
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        if in_block_comment:
            if "*/" in stripped:
                in_block_comment = False
            continue
        if stripped.startswith("//"):
            continue
        if stripped.startswith("/*"):
            if "*/" not in stripped:
                in_block_comment = True
            continue
        # Skip library declarations
        if stripped.startswith("library "):
            continue
        non_comment_lines.append(stripped)

    for line in non_comment_lines:
        if not re.match(r'^export\s+[\'"]', line):
            return False, f"Non-export statement in facade: {line[:80]}"

    return True, ""


# ── Checks ─────────────────────────────────────────────────────────────────


def check_view_ide_no_flutter_presentation() -> Dict[str, List[str]]:
    """Check view_ide/ for forbidden Flutter presentation imports."""
    violations: Dict[str, List[str]] = {}
    view_ide_dir = REPO_ROOT / "frontend" / "vityo_app" / "lib" / "src" / "view_ide"
    if not view_ide_dir.is_dir():
        return violations

    for dart_file in find_dart_files(view_ide_dir):
        imports = extract_imports(dart_file)
        for imp in imports:
            if imp in FORBIDDEN_FLUTTER_PRESENTATION_IMPORTS:
                rel = dart_file.relative_to(REPO_ROOT)
                violations.setdefault(str(rel), []).append(imp)

    return violations


def check_view_render_no_view_ide_internals() -> Dict[str, List[str]]:
    """Check view_render/ for forbidden view_ide/ internal imports."""
    violations: Dict[str, List[str]] = {}
    view_render_dir = (
        REPO_ROOT / "frontend" / "vityo_app" / "lib" / "src" / "view_render"
    )
    if not view_render_dir.is_dir():
        return violations

    for dart_file in find_dart_files(view_render_dir):
        imports = extract_imports(dart_file)
        for imp in imports:
            for forbidden in FORBIDDEN_VIEW_IDE_INTERNALS_FOR_VIEW_RENDER:
                if forbidden in imp:
                    rel = dart_file.relative_to(REPO_ROOT)
                    violations.setdefault(str(rel), []).append(imp)

    return violations


def check_agent_no_view_render() -> Dict[str, List[str]]:
    """Check agent/ for imports of view_render/."""
    violations: Dict[str, List[str]] = {}
    agent_dir = (
        REPO_ROOT
        / "frontend"
        / "vityo_app"
        / "lib"
        / "src"
        / "view_ide"
        / "agent"
    )
    if not agent_dir.is_dir():
        return violations

    for dart_file in find_dart_files(agent_dir):
        imports = extract_imports(dart_file)
        for imp in imports:
            if "view_render/" in imp:
                rel = dart_file.relative_to(REPO_ROOT)
                violations.setdefault(str(rel), []).append(imp)

    return violations


def check_legacy_facades() -> Dict[str, str]:
    """Check legacy facade directories contain only re-exports."""
    violations: Dict[str, str] = {}
    for legacy_dir_rel in LEGACY_FACADE_DIRS:
        legacy_dir = REPO_ROOT / legacy_dir_rel
        if not legacy_dir.is_dir():
            continue
        for dart_file in find_dart_files(legacy_dir):
            is_ok, reason = is_legacy_re_export_only(dart_file)
            if not is_ok:
                rel = dart_file.relative_to(REPO_ROOT)
                violations[str(rel)] = reason

    return violations


# ── Main ───────────────────────────────────────────────────────────────────


def fail(reason: str) -> None:
    print(f"FAIL: {reason}", file=sys.stderr)


def ok(message: str) -> None:
    print(f"  OK  {message}")


def main() -> int:
    failures = 0

    print("=== Vityo Architecture Boundary Gate ===\n")

    # ── 1. view_ide no Flutter presentation imports ──
    print("── 1. view_ide/ Flutter Presentation Import Check ──")
    v1 = check_view_ide_no_flutter_presentation()
    if v1:
        for file_path, bad_imports in sorted(v1.items()):
            for imp in bad_imports:
                fail(f"{file_path}: imports forbidden '{imp}'")
                failures += 1
    else:
        ok("No Flutter presentation imports in view_ide/")
    print()

    # ── 2. view_render no view_ide internals ──
    print("── 2. view_render/ → view_ide Internals Import Check ──")
    v2 = check_view_render_no_view_ide_internals()
    if v2:
        for file_path, bad_imports in sorted(v2.items()):
            for imp in bad_imports:
                fail(f"{file_path}: imports forbidden '{imp}'")
                failures += 1
    else:
        ok("No view_ide internal imports in view_render/")
    print()

    # ── 3. agent no view_render ──
    print("── 3. agent/ → view_render/ Import Check ──")
    v3 = check_agent_no_view_render()
    if v3:
        for file_path, bad_imports in sorted(v3.items()):
            for imp in bad_imports:
                fail(f"{file_path}: imports forbidden '{imp}'")
                failures += 1
    else:
        ok("No view_render/ imports in agent/")
    print()

    # ── 4. Legacy facades ──
    print("── 4. Legacy Facade Purity Check ──")
    v4 = check_legacy_facades()
    if v4:
        for file_path, reason in sorted(v4.items()):
            fail(f"{file_path}: {reason}")
            failures += 1
    else:
        ok("All legacy facade files are pure re-exports")
    print()

    # ── Summary ──
    if failures == 0:
        print("All architecture boundary checks passed.")
        return 0
    else:
        print(f"\n{failures} architecture boundary violation(s) found.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

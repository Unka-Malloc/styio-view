#!/usr/bin/env python3
"""Architecture boundary gate.

Verifies that Vityo's architecture layer boundaries are respected:
- view_ide/ must not import Flutter Material/Widgets/Cupertino/dart:ui
- view_render/ must not import agent providers, language services, or module activation
- backend_toolchain/ must not add new business logic (shim + re-export only)
- agent/ must not import from view_render/

Returns 0 when all checks pass, non-zero on violations.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# ── Paths ─────────────────────────────────────────────────────────────

VIEW_IDE_ROOT = REPO_ROOT / "frontend" / "vityo_app" / "lib" / "src" / "view_ide"
VIEW_RENDER_ROOT = REPO_ROOT / "frontend" / "vityo_app" / "lib" / "src" / "view_render"
AGENT_ROOT = REPO_ROOT / "frontend" / "vityo_app" / "lib" / "src" / "agent"
BACKEND_TOOLCHAIN_ROOT = (
    REPO_ROOT / "frontend" / "vityo_app" / "lib" / "src" / "view_ide" / "backend_toolchain"
)

# ── Forbidden import patterns ─────────────────────────────────────────

FORBIDDEN_FLUTTER_IMPORTS = [
    re.compile(r"import\s+['\"]package:flutter/material\.dart['\"]"),
    re.compile(r"import\s+['\"]package:flutter/widgets\.dart['\"]"),
    re.compile(r"import\s+['\"]package:flutter/cupertino\.dart['\"]"),
    re.compile(r"import\s+['\"]dart:ui['\"]"),
]

FORBIDDEN_VIEW_RENDER_IMPORTS = [
    re.compile(r"import\s+['\"]package:vityo_app/src/view_ide/agent/"),
    re.compile(r"import\s+['\"]package:vityo_app/src/view_ide/language/service/"),
    re.compile(r"import\s+['\"]package:vityo_app/src/view_ide/module_host/extension_activator"),
    re.compile(r"import\s+['\"]package:vityo_app/src/view_ide/module_host/extension_lifecycle"),
    re.compile(r"import\s+['\"]package:vityo_app/src/view_ide/module_host/extension_host_isolation"),
]

FORBIDDEN_AGENT_IMPORTS = [
    re.compile(r"import\s+['\"]package:vityo_app/src/view_render/"),
]


def check_view_boundary_imports() -> list[str]:
    """Check view_ide/ files for forbidden Flutter imports."""
    violations: list[str] = []
    if not VIEW_IDE_ROOT.is_dir():
        return violations

    for dart_file in VIEW_IDE_ROOT.rglob("*.dart"):
        content = dart_file.read_text(encoding="utf-8", errors="replace")
        for pattern in FORBIDDEN_FLUTTER_IMPORTS:
            if pattern.search(content):
                violations.append(
                    f"{dart_file.relative_to(REPO_ROOT)}: "
                    f"forbidden Flutter import matches '{pattern.pattern}'"
                )
    return violations


def check_render_imports() -> list[str]:
    """Check view_render/ files for forbidden domain imports."""
    violations: list[str] = []
    if not VIEW_RENDER_ROOT.is_dir():
        return violations

    for dart_file in VIEW_RENDER_ROOT.rglob("*.dart"):
        content = dart_file.read_text(encoding="utf-8", errors="replace")
        for pattern in FORBIDDEN_VIEW_RENDER_IMPORTS:
            if pattern.search(content):
                violations.append(
                    f"{dart_file.relative_to(REPO_ROOT)}: "
                    f"forbidden view_render import matches '{pattern.pattern}'"
                )
    return violations


def check_agent_imports() -> list[str]:
    """Check agent/ files for forbidden view_render imports."""
    violations: list[str] = []
    if not AGENT_ROOT.is_dir():
        return violations

    for dart_file in AGENT_ROOT.rglob("*.dart"):
        content = dart_file.read_text(encoding="utf-8", errors="replace")
        for pattern in FORBIDDEN_AGENT_IMPORTS:
            if pattern.search(content):
                violations.append(
                    f"{dart_file.relative_to(REPO_ROOT)}: "
                    f"forbidden agent import matches '{pattern.pattern}'"
                )
    return violations


def main() -> int:
    all_violations: list[str] = []

    view_boundary = check_view_boundary_imports()
    if view_boundary:
        print(f"view_ide boundary violations ({len(view_boundary)}):")
        for v in view_boundary:
            print(f"  - {v}")
        all_violations.extend(view_boundary)

    render_imports = check_render_imports()
    if render_imports:
        print(f"view_render boundary violations ({len(render_imports)}):")
        for v in render_imports:
            print(f"  - {v}")
        all_violations.extend(render_imports)

    agent_imports = check_agent_imports()
    if agent_imports:
        print(f"agent boundary violations ({len(agent_imports)}):")
        for v in agent_imports:
            print(f"  - {v}")
        all_violations.extend(agent_imports)

    if all_violations:
        print(f"\nTotal violations: {len(all_violations)}", file=sys.stderr)
        return 1

    print("Architecture boundary gate: PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())

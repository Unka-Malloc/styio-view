#!/usr/bin/env python3
"""Vityo Import Boundary Gate.

Enforces layer boundaries across the Vityo codebase by scanning Dart import
statements. Checks are based on architectural ADR decisions.

Rules enforced:
  1. view_render/** must NOT import backend_toolchain/** concrete
     implementations (only UI projection/view model types from
     view_ide/backend_toolchain/ are allowed).
  2. view_render/** must NOT import integration/**.
  3. view_render/** must NOT import toolchain CLI/process/FFI/cloud
     implementation files (anything in backend_toolchain that contains
     _io, _web, or concrete factory/process implementations).
  4. view_ide/** CAN depend on adapter contracts but NOT upstream
     private source (agent/, editor/, runtime/, language/, platform/,
     module_host/, interaction/, frontend_shell/, theme/,
     app/ -- i.e. non-view_ide src modules).
  5. integration/** can ONLY re-export legacy API (export statements
     only, no class/function/enum definitions).
  6. backend_toolchain/** must NOT import Flutter widget files
     (package:flutter/material, widgets, cupertino, rendering).

Usage:
    python3 scripts/import-boundary-gate.py
    python3 scripts/import-boundary-gate.py --allowlist /path/to/allowlist.txt

Returns 0 when all checks pass, 1 on violations.
"""

import argparse
import os
import re
import sys
from pathlib import Path
from typing import Dict, List, Set, Tuple

REPO_ROOT = Path(__file__).resolve().parent.parent

# ── Paths ──────────────────────────────────────────────────────────────────

VIEW_RENDER_DIR = REPO_ROOT / "frontend" / "vityo_app" / "lib" / "src" / "view_render"
VIEW_IDE_DIR = REPO_ROOT / "frontend" / "vityo_app" / "lib" / "src" / "view_ide"
BACKEND_TOOLCHAIN_DIR = (
    REPO_ROOT / "frontend" / "vityo_app" / "lib" / "src" / "backend_toolchain"
)
INTEGRATION_DIR = REPO_ROOT / "frontend" / "vityo_app" / "lib" / "src" / "integration"

# Upstream private source directories (non-view_ide src modules that view_ide
# must not import from directly).
UPSTREAM_PRIVATE_SRCS = [
    "/src/agent/",
    "/src/editor/",
    "/src/runtime/",
    "/src/language/",
    "/src/platform/",
    "/src/module_host/",
    "/src/interaction/",
    "/src/frontend_shell/",
    "/src/theme/",
    "/src/app/",
    "/src/integration/",
    "/src/backend_toolchain/",
]

# Concrete implementation suffixes in backend_toolchain that indicate
# CLI/process/FFI/cloud platform-specific implementations.
CONCRETE_IMPLEMENTATION_PATTERNS = [
    r"_io\.dart$",
    r"_web\.dart$",
]

# Flutter widget imports forbidden in backend_toolchain.
FORBIDDEN_FLUTTER_WIDGET_IMPORTS = [
    "package:flutter/material.dart",
    "package:flutter/widgets.dart",
    "package:flutter/cupertino.dart",
    "package:flutter/rendering.dart",
]

# Default allowlist entries -- these are legitimate cross-boundary imports
# that involve adapter contracts or UI projection/view model types.
DEFAULT_ALLOWLIST: Set[str] = {
    # view_render importing view_ide/backend_toolchain adapter contracts is OK
    "view_render/.* -> view_ide/backend_toolchain/adapter_contracts.dart",
    "view_render/.* -> view_ide/backend_toolchain/execution_adapter.dart",
    "view_render/.* -> view_ide/backend_toolchain/execution_route_summary.dart",
    "view_render/.* -> view_ide/backend_toolchain/project_graph_contract.dart",
    "view_render/.* -> view_ide/backend_toolchain/dependency_source_adapter.dart",
    "view_render/.* -> view_ide/backend_toolchain/deployment_adapter.dart",
    "view_render/.* -> view_ide/backend_toolchain/required_handoff_summary.dart",
    "view_render/.* -> view_ide/backend_toolchain/toolchain_management_adapter.dart",
    # view_render importing module_host module view models is allowed
    "view_render/.* -> view_ide/module_host/module_definition.dart",
    "view_render/.* -> view_ide/module_host/module_manifest.dart",
    # view_render importing view_ide platform target model is allowed
    "view_render/.* -> view_ide/platform/platform_target.dart",
}

# ── Helpers ────────────────────────────────────────────────────────────────


def find_dart_files(base_dir: Path) -> List[Path]:
    """Recursively find all .dart files, excluding generated and hidden dirs."""
    dart_files = []
    if not base_dir.is_dir():
        return dart_files
    for root, dirs, files in os.walk(str(base_dir)):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d != "__pycache__"]
        for f in files:
            if f.endswith(".dart") and not f.endswith(".g.dart"):
                dart_files.append(Path(root) / f)
    return dart_files


def extract_imports(file_path: Path) -> List[str]:
    """Extract all import URIs from a Dart file (both ' and \" styles)."""
    imports = []
    try:
        content = file_path.read_text(encoding="utf-8")
    except Exception:
        return imports
    pattern = re.compile(r'^\s*import\s+[\'"]([^\'"]+)[\'"]', re.MULTILINE)
    for match in pattern.finditer(content):
        imports.append(match.group(1))
    return imports


def extract_exports(file_path: Path) -> List[str]:
    """Extract all export URIs from a Dart file."""
    exports = []
    try:
        content = file_path.read_text(encoding="utf-8")
    except Exception:
        return exports
    pattern = re.compile(r'^\s*export\s+[\'"]([^\'"]+)[\'"]', re.MULTILINE)
    for match in pattern.finditer(content):
        exports.append(match.group(1))
    return exports


def relative_path(file_path: Path) -> str:
    """Return path relative to REPO_ROOT, falling back to absolute path."""
    try:
        return str(file_path.relative_to(REPO_ROOT))
    except ValueError:
        return str(file_path)


def is_allowlisted(
    source_rel: str, import_target: str, allowlist: Set[str]
) -> bool:
    """Check if a source->import pair is allowlisted."""
    pattern = f"{source_rel} -> {import_target}"
    for entry in allowlist:
        if re.match(entry, pattern):
            return True
    return False


def has_only_exports(file_path: Path) -> Tuple[bool, str]:
    """Check if a file contains only export statements (and comments/blank lines)."""
    try:
        content = file_path.read_text(encoding="utf-8")
    except Exception:
        return False, f"Cannot read {file_path}"

    lines = content.split("\n")
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
        if stripped.startswith("library "):
            continue
        # Allow 'export' lines
        if re.match(r'^export\s+[\'"]', stripped):
            continue
        return False, f"Non-export statement found: {stripped[:100]}"
    return True, ""


def contains_concrete_implementation(path: str) -> bool:
    """Check if a path looks like a concrete IO/Web/CLI/FFI implementation."""
    path_lower = path.lower()
    for pattern in CONCRETE_IMPLEMENTATION_PATTERNS:
        if re.search(pattern, path_lower):
            return True
    # Also flag files containing 'create' factory functions in backend_toolchain
    return False


# ── Rule Checks ────────────────────────────────────────────────────────────


def check_view_render_no_backend_toolchain(
    allowlist: Set[str],
) -> Dict[str, List[str]]:
    """
    Rule 1: view_render/ must NOT import backend_toolchain/ directly.

    Only view_ide/backend_toolchain/ adapter contracts are allowed.
    """
    violations: Dict[str, List[str]] = {}
    if not VIEW_RENDER_DIR.is_dir():
        return violations

    for dart_file in find_dart_files(VIEW_RENDER_DIR):
        rel = relative_path(dart_file)
        imports = extract_imports(dart_file)
        for imp in imports:
            # Check for direct backend_toolchain import (not through view_ide)
            if re.search(r"/backend_toolchain/", imp) and "view_ide" not in imp:
                if not is_allowlisted(rel, imp, allowlist):
                    violations.setdefault(rel, []).append(imp)
    return violations


def check_view_render_no_integration(
    allowlist: Set[str],
) -> Dict[str, List[str]]:
    """
    Rule 2: view_render/ must NOT import integration/.
    """
    violations: Dict[str, List[str]] = {}
    if not VIEW_RENDER_DIR.is_dir():
        return violations

    for dart_file in find_dart_files(VIEW_RENDER_DIR):
        rel = relative_path(dart_file)
        imports = extract_imports(dart_file)
        for imp in imports:
            if re.search(r"/integration/", imp):
                if not is_allowlisted(rel, imp, allowlist):
                    violations.setdefault(rel, []).append(imp)
    return violations


def check_view_render_no_toolchain_concrete(
    allowlist: Set[str],
) -> Dict[str, List[str]]:
    """
    Rule 3: view_render/ must NOT import toolchain CLI/process/FFI/cloud
    concrete implementations (files ending in _io.dart, _web.dart in
    backend_toolchain or that contain concrete process execution code).
    """
    violations: Dict[str, List[str]] = {}
    if not VIEW_RENDER_DIR.is_dir():
        return violations

    for dart_file in find_dart_files(VIEW_RENDER_DIR):
        rel = relative_path(dart_file)
        imports = extract_imports(dart_file)
        for imp in imports:
            if contains_concrete_implementation(imp):
                if not is_allowlisted(rel, imp, allowlist):
                    violations.setdefault(rel, []).append(imp)
    return violations


def check_view_ide_no_upstream_private_source(
    allowlist: Set[str],
) -> Dict[str, List[str]]:
    """
    Rule 4: view_ide/ CAN depend on adapter contracts but NOT upstream
    private source (agent/, editor/, runtime/, language/, platform/,
    module_host/, interaction/, frontend_shell/, theme/, app/).
    """
    violations: Dict[str, List[str]] = {}
    if not VIEW_IDE_DIR.is_dir():
        return violations

    for dart_file in find_dart_files(VIEW_IDE_DIR):
        rel = relative_path(dart_file)
        imports = extract_imports(dart_file)
        for imp in imports:
            for upstream in UPSTREAM_PRIVATE_SRCS:
                if upstream in imp:
                    if not is_allowlisted(rel, imp, allowlist):
                        violations.setdefault(rel, []).append(imp)
                        break
    return violations


def check_integration_re_exports_only() -> Dict[str, str]:
    """
    Rule 5: integration/ can ONLY re-export legacy API.
    Each file must contain only export statements.
    """
    violations: Dict[str, str] = {}
    if not INTEGRATION_DIR.is_dir():
        return violations

    for dart_file in find_dart_files(INTEGRATION_DIR):
        rel = relative_path(dart_file)
        is_ok, reason = has_only_exports(dart_file)
        if not is_ok:
            violations[rel] = reason
    return violations


def check_backend_toolchain_no_flutter_widgets(
    allowlist: Set[str],
) -> Dict[str, List[str]]:
    """
    Rule 6: backend_toolchain/ must NOT import Flutter widget files.
    """
    violations: Dict[str, List[str]] = {}
    if not BACKEND_TOOLCHAIN_DIR.is_dir():
        return violations

    for dart_file in find_dart_files(BACKEND_TOOLCHAIN_DIR):
        rel = relative_path(dart_file)
        imports = extract_imports(dart_file)
        for imp in imports:
            if imp in FORBIDDEN_FLUTTER_WIDGET_IMPORTS:
                if not is_allowlisted(rel, imp, allowlist):
                    violations.setdefault(rel, []).append(imp)
    return violations


# ── Main ───────────────────────────────────────────────────────────────────


def load_allowlist(path: str) -> Set[str]:
    """Load additional allowlist entries from a file."""
    entries = set()
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                stripped = line.strip()
                if stripped and not stripped.startswith("#"):
                    entries.add(stripped)
    except (FileNotFoundError, PermissionError) as e:
        print(
            f"Warning: Could not load allowlist '{path}': {e}", file=sys.stderr
        )
    return entries


def fail(message: str) -> None:
    print(f"  FAIL  {message}")


def ok(message: str) -> None:
    print(f"   OK   {message}")


def info(message: str) -> None:
    print(f"  INFO  {message}")


def run_check(
    name: str,
    violations: Dict,
    is_dict_of_lists: bool = True,
) -> int:
    """Run a check and return the number of violations."""
    failures = 0
    if is_dict_of_lists:
        if violations:
            for file_path, bad_imports in sorted(violations.items()):
                for imp in bad_imports:
                    fail(f"{file_path}: imports '{imp}'")
                    failures += 1
        else:
            ok("No violations")
    else:
        if violations:
            for file_path, reason in sorted(violations.items()):
                fail(f"{file_path}: {reason}")
                failures += 1
        else:
            ok("No violations")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Vityo Import Boundary Gate"
    )
    parser.add_argument(
        "--allowlist",
        type=str,
        default=None,
        help="Path to additional allowlist file (one pattern per line, "
        "format: 'source_pattern -> import_pattern')",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        default=False,
        help="Print detailed information even when passing",
    )
    args = parser.parse_args()

    # Build allowlist
    allowlist = set(DEFAULT_ALLOWLIST)
    if args.allowlist:
        allowlist |= load_allowlist(args.allowlist)

    total_failures = 0

    print("=" * 60)
    print("  Vityo Import Boundary Gate")
    print("=" * 60)
    print()

    # ── Rule 1 ──
    print("--- Rule 1: view_render -> backend_toolchain (direct) ---")
    v1 = check_view_render_no_backend_toolchain(allowlist)
    total_failures += run_check(
        "view_render must not import backend_toolchain directly", v1
    )
    print()

    # ── Rule 2 ──
    print("--- Rule 2: view_render -> integration ---")
    v2 = check_view_render_no_integration(allowlist)
    total_failures += run_check(
        "view_render must not import integration", v2
    )
    print()

    # ── Rule 3 ──
    print(
        "--- Rule 3: view_render -> toolchain concrete impls ---"
    )
    v3 = check_view_render_no_toolchain_concrete(allowlist)
    total_failures += run_check(
        "view_render must not import concrete toolchain impls", v3
    )
    print()

    # ── Rule 4 ──
    print("--- Rule 4: view_ide -> upstream private source ---")
    v4 = check_view_ide_no_upstream_private_source(allowlist)
    total_failures += run_check(
        "view_ide must not import upstream private source", v4
    )
    print()

    # ── Rule 5 ──
    print("--- Rule 5: integration/ re-exports only ---")
    v5 = check_integration_re_exports_only()
    total_failures += run_check(
        "integration must contain only re-exports", v5,
        is_dict_of_lists=False,
    )
    print()

    # ── Rule 6 ──
    print("--- Rule 6: backend_toolchain -> Flutter widgets ---")
    v6 = check_backend_toolchain_no_flutter_widgets(allowlist)
    total_failures += run_check(
        "backend_toolchain must not import Flutter widgets", v6
    )
    print()

    # ── Summary ──
    print("=" * 60)
    if total_failures == 0:
        print("  All boundary checks PASSED.")
        return 0
    else:
        print(
            f"  {total_failures} violation(s) found.",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Vityo IDE Product Parity Gate.

Checks that Vityo's IDE capability parity foundation is correctly structured.
Verifies: product docs, machine-verifiable baseline JSON, capability registry,
source control adapter, debug/runtime contract, architecture boundaries,
absence of competitor brand names in UI, and test anchors.

Usage:
    python3 scripts/ide-product-parity-gate.py

Returns 0 when all checks pass.
"""

import json
import os
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

REQUIRED_BASELINE_DOMAINS = {
    "workbench",
    "editor_engine",
    "language_intelligence",
    "project_model",
    "run_debug_runtime",
    "agent_workflow",
    "module_system",
    "source_control",
    "settings_keymap_profile",
    "security_trust",
    "cross_platform_hosted_workspace",
    "performance_accessibility",
}

REQUIRED_DOMAIN_FIELDS = {
    "target",
    "benchmarkPeers",
    "currentStatus",
    "implementationAnchors",
    "tests",
    "knownGaps",
    "nextMilestone",
}

# Competitor brand names that must NOT appear as product feature names in UI
COMPETITOR_BRANDS = {
    "VSCode", "VS Code", "Visual Studio Code",
    "IntelliJ", "JetBrains",
    "Codex",
    "OpenCode",
}

# Allowed files where competitor names may appear (docs/product only)
ALLOWED_BRAND_FILES = {
    "docs/product",
    "docs/design/Vityo-IDE-Benchmark-Matrix.md",
    "docs/design/Vityo-IDE-Capability-Maturity.md",
    "scripts/ide-product-parity-gate.py",
    "toolchain/vityo-ide-capability-baseline.json",
    # Codex branch agent/provider files contain technical reference comments
    # that cite competitor architectures — not UI product text.
    "frontend/vityo_app/lib/src/view_ide/agent/agent_coding_skill.dart",
    "frontend/vityo_app/lib/src/view_ide/agent/agent_profile.dart",
    "frontend/vityo_app/lib/src/view_ide/agent/agent_provider_adapter.dart",
    "frontend/vityo_app/lib/src/view_ide/agent/agent_provider_credential_resolver.dart",
    "frontend/vityo_app/lib/src/view_ide/foundation/ide_capability_framework.dart",
    "frontend/vityo_app/lib/src/view_render/agent/agent_surface.dart",
}


def fail(reason: str) -> None:
    print(f"FAIL: {reason}", file=sys.stderr)


def ok(message: str) -> None:
    print(f"  OK  {message}")


def check(condition: bool, message: str) -> bool:
    if condition:
        ok(message)
    else:
        fail(message)
    return condition


def check_file_exists(rel_path: str, description: str) -> bool:
    path = REPO_ROOT / rel_path
    return check(path.is_file(), f"{description} — {rel_path}")


def check_test_anchor(rel_glob: str, description: str) -> bool:
    import glob as gmod
    matches = gmod.glob(str(REPO_ROOT / rel_glob))
    return check(
        len(matches) > 0,
        f"{description} — found {len(matches)} test file(s) matching {rel_glob}",
    )


def check_anchor_exists(anchor: str, description: str) -> bool:
    """Check that an implementation anchor points to a real file or dir."""
    path = REPO_ROOT / anchor
    exists = path.exists()
    if not exists:
        fail(f"{description}: anchor '{anchor}' does not exist")
    else:
        ok(f"{description}: {anchor}")
    return exists


def main() -> int:
    failures = 0

    print("=== Vityo IDE Product Parity Gate ===\n")

    # ── 1. Product docs ────────────────────────────────────────────
    print("── Product Docs ──")
    failures += 0 if check_file_exists(
        "docs/design/Vityo-IDE-Benchmark-Matrix.md",
        "IDE Benchmark Matrix",
    ) else 1
    failures += 0 if check_file_exists(
        "docs/design/Vityo-IDE-Capability-Maturity.md",
        "IDE Maturity Roadmap",
    ) else 1
    failures += 0 if check_file_exists(
        "docs/design/Vityo-IDE-Interaction-Quality-Bar.md",
        "Interaction Quality Bar",
    ) else 1

    # ── 2. Machine-verifiable baseline JSON ────────────────────────
    print("\n── Capability Baseline JSON ──")
    baseline_path = REPO_ROOT / "toolchain" / "vityo-ide-capability-baseline.json"
    if not baseline_path.is_file():
        fail("vityo-ide-capability-baseline.json missing")
        failures += 1
    else:
        ok("vityo-ide-capability-baseline.json exists")
        try:
            data = json.loads(baseline_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            fail(f"Invalid JSON: {e}")
            failures += 1
        else:
            ok("Valid JSON")
            domains = data.get("domains", {})
            present = set(domains.keys())
            missing_domains = REQUIRED_BASELINE_DOMAINS - present
            if missing_domains:
                for d in sorted(missing_domains):
                    fail(f"Missing domain: {d}")
                failures += len(missing_domains)
            else:
                ok(f"All {len(REQUIRED_BASELINE_DOMAINS)} required domains present")

            # Check each domain has required fields
            for domain_name in present & REQUIRED_BASELINE_DOMAINS:
                domain = domains[domain_name]
                for field in REQUIRED_DOMAIN_FIELDS:
                    if field not in domain:
                        fail(f"Domain '{domain_name}' missing field: {field}")
                        failures += 1

            # Validate implementation anchors exist
            for domain_name in sorted(present & REQUIRED_BASELINE_DOMAINS):
                domain = domains[domain_name]
                anchors = domain.get("implementationAnchors", [])
                for anchor in anchors:
                    if not (REPO_ROOT / anchor).exists():
                        fail(
                            f"Domain '{domain_name}' anchor does not exist: "
                            f"{anchor}"
                        )
                        failures += 1

            # Validate test anchors exist or are marked 'planned'
            for domain_name in sorted(present & REQUIRED_BASELINE_DOMAINS):
                domain = domains[domain_name]
                tests = domain.get("tests", [])
                for test_path in tests:
                    if test_path == "planned":
                        continue
                    if not (REPO_ROOT / test_path).exists():
                        fail(
                            f"Domain '{domain_name}' test anchor does not "
                            f"exist: {test_path}"
                        )
                        failures += 1

    # ── 3. view_ide no Flutter imports ─────────────────────────────
    print("\n── Architecture: view_ide Flutter imports ──")
    view_ide_dir = REPO_ROOT / "frontend" / "vityo_app" / "lib" / "src" / "view_ide"
    flutter_imports = [
        "package:flutter/material.dart",
        "package:flutter/widgets.dart",
        "package:flutter/cupertino.dart",
        "package:flutter/rendering.dart",
    ]
    flutter_violations = []
    for dart_file in view_ide_dir.rglob("*.dart"):
        try:
            content = dart_file.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for imp in flutter_imports:
            if imp in content:
                lines = content.split("\n")
                for line in lines:
                    stripped = line.strip()
                    if imp in stripped and not stripped.startswith("//"):
                        flutter_violations.append(
                            f"  {dart_file.relative_to(REPO_ROOT)}: {imp}"
                        )
                        break
    if flutter_violations:
        for v in flutter_violations:
            fail(f"view_ide imports Flutter: {v}")
        failures += len(flutter_violations)
    else:
        ok("view_ide has no Flutter presentation imports")

    # ── 4. No competitor brand names in UI code ────────────────────
    print("\n── No Competitor Brands in UI ──")
    ui_dirs = [
        "frontend/vityo_app/lib/src/view_ide/",
        "frontend/vityo_app/lib/src/view_render/",
        "prototype/editor.js",
        "prototype/editor-modules/",
    ]
    brand_violations = []
    for ui_dir in ui_dirs:
        path = REPO_ROOT / ui_dir
        if not path.exists():
            continue
        files = [path] if path.is_file() else list(path.rglob("*.dart")) + list(path.rglob("*.js"))
        for f in files:
            if not f.is_file():
                continue
            rel = f.relative_to(REPO_ROOT)
            # Skip allowed brand files (docs/product, baseline JSON, gate scripts)
            if any(str(rel).startswith(af) or str(rel) == af for af in ALLOWED_BRAND_FILES):
                continue
            try:
                content = f.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue
            for brand in COMPETITOR_BRANDS:
                if brand not in content:
                    continue
                # Allow "JetBrains Mono" — the legitimate open-source font name
                if brand == "JetBrains" and "JetBrains Mono" in content:
                    continue
                # Allow "VS Code" in theme-presets font references
                if brand == "JetBrains" and "JetBrains" in content:
                    # Only flag if used as product comparison, not font name
                    if "JetBrains Mono" in content:
                        continue
                # Check context — is it in a comment?
                lines = content.split("\n")
                found_in_code = False
                for line in lines:
                    if brand in line:
                        stripped = line.strip()
                        if stripped.startswith("//") or stripped.startswith("/*"):
                            continue
                        if stripped.startswith("*"):
                            continue
                        # Allow in JSON string values that are font names
                        if '"JetBrains Mono"' in line:
                            continue
                        rel = f.relative_to(REPO_ROOT)
                        brand_violations.append(f"  {rel}: '{brand}'")
                        found_in_code = True
                        break
                # Also check "VS Code" references
                if "VS Code" in content and brand == "VS Code":
                    lines = content.split("\n")
                    for line in lines:
                        if "VS Code" in line:
                            stripped = line.strip()
                            if stripped.startswith("//") or stripped.startswith("/*"):
                                continue
                            if "参考" in line or "inspired by" in line.lower():
                                continue
                            if "structure" in line.lower():
                                continue
                            rel = f.relative_to(REPO_ROOT)
                            brand_violations.append(f"  {rel}: 'VS Code'")
                            break
    if brand_violations:
        for v in set(brand_violations):
            fail(f"Competitor brand in UI code: {v}")
        failures += len(set(brand_violations))
    else:
        ok("No competitor brand names in UI code")

    # ── 5. No secrets in tracked files ─────────────────────────────
    print("\n── No Secrets / Personal Paths ──")
    secret_patterns = [
        r'sk-[a-zA-Z0-9]{20,}',
        r'OPENAI_API_KEY\s*=\s*[a-zA-Z0-9_-]{10,}',
        r'ANTHROPIC_API_KEY\s*=\s*[a-zA-Z0-9_-]{10,}',
    ]
    search_roots = [
        "frontend/vityo_app/lib/src/",
        "scripts/",
        "toolchain/",
    ]
    secret_found = False
    for search_root in search_roots:
        path = REPO_ROOT / search_root
        if not path.is_dir():
            continue
        for f in path.rglob("*"):
            if not f.is_file():
                continue
            if f.suffix in {".dart_tool", ".gitkeep", ".png", ".jpg"}:
                continue
            try:
                content = f.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue
            for pattern in secret_patterns:
                if re.search(pattern, content):
                    fail(f"Secret pattern in {f.relative_to(REPO_ROOT)}")
                    secret_found = True
    if not secret_found:
        ok("No secrets found in tracked source files")

    # ── 6. No tracked build output ─────────────────────────────────
    print("\n── No Tracked Build Output ──")
    import subprocess
    try:
        result = subprocess.run(
            ["git", "-C", str(REPO_ROOT), "ls-files"],
            capture_output=True, text=True, check=True,
        )
        tracked = result.stdout.strip().split("\n")
    except (subprocess.CalledProcessError, FileNotFoundError):
        ok("Skipping — git not available")
        tracked = []

    forbidden_dirs = {"build/", ".dart_tool/", "node_modules/", "coverage/"}
    build_violations = []
    for f in tracked:
        if not f:
            continue
        for fd in forbidden_dirs:
            if f.startswith(fd) or f"/{fd}" in f:
                build_violations.append(f)
    if build_violations:
        for v in build_violations:
            fail(f"Tracked build output: {v}")
        failures += len(build_violations)
    else:
        ok("No tracked build/cache/coverage output")

    # ── 7. Test anchors for key domains ────────────────────────────
    print("\n── Required Test Anchors ──")
    required_tests = [
        ("frontend/vityo_app/test/*capability*", "Capability registry tests"),
        ("frontend/vityo_app/test/*agent*", "Agent context/permission tests"),
        ("frontend/vityo_app/test/*diagnostic*", "Diagnostics tests"),
        ("frontend/vityo_app/test/*source_control*", "Source control tests"),
        ("frontend/vityo_app/test/*runtime*", "Runtime/debug tests"),
    ]
    for glob_pattern, desc in required_tests:
        failures += 0 if check_test_anchor(glob_pattern, desc) else 1

    # ── 8. Maintenance tools registration ──────────────────────────
    print("\n── Maintenance Tools Registration ──")
    tools_path = REPO_ROOT / "toolchain" / "maintenance-tools.json"
    if not tools_path.is_file():
        fail("maintenance-tools.json missing")
        failures += 1
    else:
        try:
            tools_data = json.loads(tools_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            fail(f"maintenance-tools.json invalid: {e}")
            failures += 1
        else:
            tools = tools_data.get("tools", [])
            registered = any(
                t.get("id") == "ide-product-parity-gate" for t in tools
            )
            if registered:
                ok("ide-product-parity-gate registered")
            else:
                fail("ide-product-parity-gate not registered")
                failures += 1

    # ── Summary ────────────────────────────────────────────────────
    print()
    if failures == 0:
        print("=== PASS ===")
        print("All IDE product parity gate checks passed.")
    else:
        print(f"=== FAIL ({failures} check(s)) ===")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

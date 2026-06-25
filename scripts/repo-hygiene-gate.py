#!/usr/bin/env python3
from __future__ import annotations

import argparse
import codecs
import fnmatch
import subprocess
import sys
from pathlib import Path, PurePosixPath

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MAX_FILE_BYTES = 20 * 1024 * 1024

FORBIDDEN_PATH_PARTS = {
    ".artifacts",
    ".dart_tool",
    ".git",
    ".gradle",
    ".next",
    ".nuxt",
    ".pytest_cache",
    ".ruff_cache",
    ".turbo",
    "__pycache__",
    "build",
    "coverage",
    "dist",
    "node_modules",
}

FORBIDDEN_FILE_SUFFIXES = (
    ".a",
    ".aar",
    ".apk",
    ".app",
    ".bin",
    ".class",
    ".dll",
    ".dmg",
    ".dylib",
    ".egg",
    ".exe",
    ".gz",
    ".ipa",
    ".jar",
    ".lib",
    ".nar",
    ".o",
    ".obj",
    ".out",
    ".pdb",
    ".pyc",
    ".pyo",
    ".rar",
    ".so",
    ".tar",
    ".tgz",
    ".war",
    ".whl",
    ".zip",
    ".7z",
)

ALLOWED_BINARY_GLOBS = (
    "docs/assets/*.gif",
    "docs/assets/*.jpeg",
    "docs/assets/*.jpg",
    "docs/assets/*.png",
    "docs/assets/*.svg",
    "docs/assets/*.webp",
    "docs/assets/**/*.gif",
    "docs/assets/**/*.jpeg",
    "docs/assets/**/*.jpg",
    "docs/assets/**/*.png",
    "docs/assets/**/*.svg",
    "docs/assets/**/*.webp",
    "frontend/vityo_app/android/app/src/main/res/**/*.png",
    "frontend/vityo_app/ios/Runner/Assets.xcassets/**/*.png",
    "frontend/vityo_app/macos/Runner/Assets.xcassets/**/*.png",
    "frontend/vityo_app/web/*.png",
    "frontend/vityo_app/web/**/*.png",
    "frontend/vityo_app/windows/runner/resources/*.ico",
)

REQUIRED_GITIGNORE_PATTERNS = (
    ".DS_Store",
    ".cursor/",
    ".idea/",
    ".vscode/",
    ".cache/",
    "__pycache__/",
    ".pytest_cache/",
    ".mypy_cache/",
    ".ruff_cache/",
    ".venv/",
    "venv/",
    "node_modules/",
    "build/",
    "build-*/",
    "tmp/",
    "*.tmp",
    "*.log",
    "docs/audit/defects/",
    "!docs/**/build/",
    "!docs/**/build/**",
    "!docs/**/build-*/",
    "!docs/**/build-*/**",
    "!docs/**/tmp/",
    "!docs/**/tmp/**",
    "!docs/**/*.tmp",
    "!docs/**/*.log",
    "!frontend/vityo_app/test/**/build/",
    "!frontend/vityo_app/test/**/build/**",
    "!frontend/vityo_app/test/**/build-*/",
    "!frontend/vityo_app/test/**/build-*/**",
    "!frontend/vityo_app/test/**/tmp/",
    "!frontend/vityo_app/test/**/tmp/**",
    "!frontend/vityo_app/test/**/*.tmp",
    "!frontend/vityo_app/test/**/*.log",
)

REQUIRED_DOC_REFERENCES = {
    Path("docs/README.md"): (
        "scripts/docs-index.py",
        "scripts/docs-lifecycle.py",
        "scripts/docs-audit.py",
    ),
    Path("docs/assets/workflow/REPO-HYGIENE.md"): (
        "scripts/repo-hygiene-gate.py",
        "scripts/delivery-gate.sh",
    ),
    Path("docs/teams/DOCS-DELIVERY-RUNBOOK.md"): (
        "scripts/repo-hygiene-gate.py",
        "scripts/docs-gate.sh",
        "scripts/delivery-gate.sh",
    ),
}

REQUIRED_PROJECT_BRAND_HEADINGS = {
    Path("README.md"): "# Vityo",
    Path("docs/README.md"): "# Vityo Docs",
    Path("frontend/vityo_app/README.md"): "# Vityo Flutter Shell",
}
REQUIRED_PROJECT_BRAND_METADATA = {
    Path("frontend/vityo_app/android/app/src/main/AndroidManifest.xml"): 'android:label="Vityo"',
    Path("frontend/vityo_app/ios/Runner/Info.plist"): (
        "<key>CFBundleDisplayName</key>\n\t<string>Vityo</string>",
        "<key>CFBundleName</key>\n\t<string>Vityo</string>",
    ),
    Path("frontend/vityo_app/linux/runner/my_application.cc"): 'gtk_window_set_title(window, "Vityo");',
    Path("frontend/vityo_app/macos/Runner/Configs/AppInfo.xcconfig"): "PRODUCT_NAME = Vityo",
    Path("frontend/vityo_app/pubspec.yaml"): "description: Vityo IDE editor shell",
    Path("frontend/vityo_app/windows/runner/Runner.rc"): (
        'VALUE "FileDescription", "Vityo"',
        'VALUE "InternalName", "Vityo"',
        'VALUE "ProductName", "Vityo"',
    ),
}
VIEW_IDE_ROOT = REPO_ROOT / "frontend" / "vityo_app" / "lib" / "src" / "view_ide"
VIEW_RENDER_ROOT = REPO_ROOT / "frontend" / "vityo_app" / "lib" / "src" / "view_render"
VIEW_IDE_BACKEND_TOOLCHAIN_ROOT = VIEW_IDE_ROOT / "backend_toolchain"
VIEW_IDE_COMMANDS_ROOT = VIEW_IDE_ROOT / "commands"
VIEW_IDE_EDITOR_ROOT = VIEW_IDE_ROOT / "editor"
VIEW_IDE_LANGUAGE_ROOT = VIEW_IDE_ROOT / "language"
VIEW_IDE_WORKSPACE_ROOT = VIEW_IDE_ROOT / "workspace"
VIEW_IDE_MODULE_HOST_ROOT = VIEW_IDE_ROOT / "module_host"
VIEW_IDE_RUNTIME_ROOT = VIEW_IDE_ROOT / "runtime"
VIEW_IDE_SHELL_RUNTIME_ROOT = VIEW_IDE_ROOT / "shell_runtime"
VIEW_IDE_AGENT_ROOT = VIEW_IDE_ROOT / "agent"
VIEW_IDE_PLATFORM_ROOT = VIEW_IDE_ROOT / "platform"
VIEW_RENDER_SHELL_ROOT = VIEW_RENDER_ROOT / "shell"
VIEW_RENDER_AGENT_ROOT = VIEW_RENDER_ROOT / "agent"
VIEW_RENDER_EDITOR_ROOT = VIEW_RENDER_ROOT / "editor"
VIEW_RENDER_RUNTIME_ROOT = VIEW_RENDER_ROOT / "runtime"
VIEW_RENDER_THEME_ROOT = VIEW_RENDER_ROOT / "theme"
VIEW_RENDER_PLATFORM_ROOT = VIEW_RENDER_ROOT / "platform"
LEGACY_BACKEND_TOOLCHAIN_ROOT = (
    REPO_ROOT / "frontend" / "vityo_app" / "lib" / "src" / "backend_toolchain"
)
LEGACY_COMMANDS_ROOT = (
    REPO_ROOT / "frontend" / "vityo_app" / "lib" / "src" / "app" / "commands"
)
LEGACY_EDITOR_ROOT = (
    REPO_ROOT / "frontend" / "vityo_app" / "lib" / "src" / "editor"
)
LEGACY_LANGUAGE_ROOT = (
    REPO_ROOT / "frontend" / "vityo_app" / "lib" / "src" / "language"
)
LEGACY_WORKSPACE_ROOT = (
    REPO_ROOT / "frontend" / "vityo_app" / "lib" / "src" / "app" / "state"
)
LEGACY_APP_LAYOUT_ROOT = (
    REPO_ROOT / "frontend" / "vityo_app" / "lib" / "src" / "app" / "layout"
)
LEGACY_MODULE_HOST_ROOT = (
    REPO_ROOT / "frontend" / "vityo_app" / "lib" / "src" / "module_host"
)
LEGACY_RUNTIME_ROOT = (
    REPO_ROOT / "frontend" / "vityo_app" / "lib" / "src" / "runtime"
)
LEGACY_AGENT_ROOT = (
    REPO_ROOT / "frontend" / "vityo_app" / "lib" / "src" / "agent"
)
LEGACY_PLATFORM_ROOT = (
    REPO_ROOT / "frontend" / "vityo_app" / "lib" / "src" / "platform"
)
LEGACY_THEME_ROOT = (
    REPO_ROOT / "frontend" / "vityo_app" / "lib" / "src" / "theme"
)
LEGACY_EDITOR_FACADE_FILES = (
    "document_state.dart",
    "editor_controller.dart",
    "editor_render_layers.dart",
    "selection_state.dart",
)
LEGACY_WORKSPACE_FACADE_FILES = (
    "workspace_controller.dart",
    "workspace_document_store.dart",
    "workspace_document_store_io.dart",
    "workspace_document_store_types.dart",
    "workspace_document_store_web.dart",
)
LEGACY_RUNTIME_FACADE_FILES = ("runtime_replay_summary.dart",)
LEGACY_AGENT_FACADE_FILES = ("agent_profile.dart",)
LEGACY_PLATFORM_FACADE_FILES = ("native_module_loader.dart", "platform_target.dart")
VIEW_IDE_FORBIDDEN_IMPORTS = (
    "package:flutter/cupertino.dart",
    "package:flutter/material.dart",
    "package:flutter/widgets.dart",
    "dart:ui",
)
VIEW_IDE_LANGUAGE_SUBMODULES = (
    "contract",
    "diagnostics",
    "syntax",
    "semantic",
    "service",
    "features",
    "syntax_validation",
    "cache",
)
VIEW_IDE_EDITOR_SUBMODULES = (
    "document",
    "selection",
    "controller",
    "transactions",
    "render_plan",
    "performance",
    "actions",
    "session",
)
VIEW_IDE_EDITOR_FACADES = {
    "document_state.dart": "document/document_state.dart",
    "selection_state.dart": "selection/selection_state.dart",
    "editor_controller.dart": "controller/editor_controller.dart",
    "editor_render_layers.dart": "render_plan/editor_render_layers.dart",
}
VIEW_IDE_EDITOR_BARREL = (
    "export 'actions/actions.dart';",
    "export 'controller/controller.dart';",
    "export 'document/document.dart';",
    "export 'performance/performance.dart';",
    "export 'render_plan/render_plan.dart';",
    "export 'selection/selection.dart';",
    "export 'session/session.dart';",
    "export 'transactions/transactions.dart';",
)
VIEW_IDE_LANGUAGE_FACADES = {
    "language_contract.dart": "contract/language_contract.dart",
    "diagnostic_revision_gate.dart": "diagnostics/diagnostic_revision_gate.dart",
    "styio_syntax_highlighter.dart": "syntax/styio_syntax_highlighter.dart",
    "styio_symbol_index.dart": "semantic/styio_symbol_index.dart",
    "styio_language_service.dart": "service/styio_language_service.dart",
    "simple_styio_language_service.dart": "service/simple_styio_language_service.dart",
    "local_styio_language_service.dart": "service/local_styio_language_service.dart",
}
VIEW_IDE_LANGUAGE_BARREL = (
    "export 'cache/cache.dart';",
    "export 'contract/language_contract.dart';",
    "export 'diagnostic_revision_gate.dart';",
    "export 'semantic_snapshot_panel.dart';",
    "export 'diagnostics/diagnostics.dart';",
    "export 'features/features.dart';",
    "export 'semantic/styio_symbol_index.dart';",
    "export 'service/language_analysis_scheduler.dart';",
    "export 'service/legacy_project_document_rule_provider.dart';",
    "export 'service/project_document_diagnostics.dart';",
    "export 'service/project_document_quick_fixes.dart';",
    "export 'service/project_document_rule_registry.dart';",
    "export 'service/project_document_rule_provider.dart';",
    "export 'service/project_styio_language_service.dart';",
    "export 'service/project_styio_document_service.dart';",
    "export 'service/semantic_snapshot_event_bridge.dart';",
    "export 'service/semantic_snapshot_provider.dart';",
    "export 'service/language_service_foundation.dart';",
    "export 'service/local_styio_language_service.dart';",
    "export 'service/styio_service_capability.dart';",
    "export 'service/styio_service_capability_detector.dart';",
    "export 'service/styio_service_capability_profile.dart';",
    "export 'service/styio_service_connector.dart';",
    "export 'service/styio_service_daemon_process_adapter.dart';",
    "export 'service/styio_service_manager_connector.dart';",
    "export 'service/styio_service_project_document_rule_provider.dart';",
    "export 'service/styio_service_runtime.dart';",
    "export 'service/styio_service_subscription.dart';",
    "export 'service/styio_language_service.dart';",
    "export 'service/styio_language_provider_registry.dart';",
    "export 'service/styio_workspace_diagnostics_provider.dart';",
    "export 'syntax/styio_syntax_highlighter.dart';",
    "export 'syntax_validation/syntax_validation.dart';",
)


def run_git(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
    )


def tracked_files() -> list[str]:
    proc = run_git("ls-files", "-z")
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or "git ls-files failed")
    return [path for path in proc.stdout.split("\0") if path]


def staged_files() -> list[str]:
    proc = run_git("diff", "--cached", "--name-only", "--diff-filter=ACMR")
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or "git diff --cached failed")
    return [line for line in proc.stdout.splitlines() if line]


def default_push_range() -> str:
    proc = run_git("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}")
    if proc.returncode == 0:
        return "@{upstream}..HEAD"
    return "HEAD"


def has_forbidden_path_part(rel_path: str) -> bool:
    return any(part in FORBIDDEN_PATH_PARTS for part in PurePosixPath(rel_path).parts)


def has_forbidden_file_suffix(rel_path: str) -> bool:
    return rel_path.lower().endswith(FORBIDDEN_FILE_SUFFIXES)


def is_allowed_binary(rel_path: str) -> bool:
    return any(fnmatch.fnmatchcase(rel_path, pattern) for pattern in ALLOWED_BINARY_GLOBS)


def is_binary_file(rel_path: str) -> bool:
    file_path = REPO_ROOT / rel_path
    sample = file_path.read_bytes()[:8192]
    if not sample:
        return False
    if b"\0" in sample:
        return True
    try:
        text = codecs.getincrementaldecoder("utf-8")().decode(sample, final=False)
    except UnicodeDecodeError:
        return True
    return any(ord(char) < 32 and char not in "\n\r\t\f\b" for char in text)


def check_gitignore() -> list[str]:
    gitignore = REPO_ROOT / ".gitignore"
    if not gitignore.exists():
        return [".gitignore is missing"]
    patterns = {
        line.strip()
        for line in gitignore.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    }
    return [f".gitignore must include: {required}" for required in REQUIRED_GITIGNORE_PATTERNS if required not in patterns]


def check_doc_references() -> list[str]:
    errors: list[str] = []
    for relative_path, needles in REQUIRED_DOC_REFERENCES.items():
        path = REPO_ROOT / relative_path
        if not path.exists():
            errors.append(f"required documentation file is missing: {relative_path.as_posix()}")
            continue
        text = path.read_text(encoding="utf-8")
        for needle in needles:
            if needle not in text:
                errors.append(f"{relative_path.as_posix()} must document {needle}")
    return errors


def check_project_branding() -> list[str]:
    errors: list[str] = []
    for relative_path, heading in REQUIRED_PROJECT_BRAND_HEADINGS.items():
        path = REPO_ROOT / relative_path
        if not path.exists():
            errors.append(f"required project branding file is missing: {relative_path.as_posix()}")
            continue
        lines = path.read_text(encoding="utf-8").splitlines()
        if not lines or lines[0].strip() != heading:
            errors.append(f"{relative_path.as_posix()} must use project heading: {heading}")
    for relative_path, markers in REQUIRED_PROJECT_BRAND_METADATA.items():
        path = REPO_ROOT / relative_path
        if not path.exists():
            errors.append(f"required project metadata file is missing: {relative_path.as_posix()}")
            continue
        text = path.read_text(encoding="utf-8")
        if isinstance(markers, str):
            markers = (markers,)
        for marker in markers:
            if marker not in text:
                errors.append(f"{relative_path.as_posix()} must use project metadata marker: {marker}")
    return errors


def check_view_boundary_imports() -> list[str]:
    errors: list[str] = []

    for root in (
        VIEW_IDE_ROOT,
        VIEW_RENDER_ROOT,
        VIEW_IDE_BACKEND_TOOLCHAIN_ROOT,
        VIEW_IDE_COMMANDS_ROOT,
        VIEW_IDE_EDITOR_ROOT,
        VIEW_IDE_LANGUAGE_ROOT,
        VIEW_IDE_WORKSPACE_ROOT,
        VIEW_IDE_MODULE_HOST_ROOT,
        VIEW_IDE_RUNTIME_ROOT,
        VIEW_IDE_SHELL_RUNTIME_ROOT,
        VIEW_IDE_AGENT_ROOT,
        VIEW_IDE_PLATFORM_ROOT,
        VIEW_RENDER_SHELL_ROOT,
        VIEW_RENDER_AGENT_ROOT,
        VIEW_RENDER_EDITOR_ROOT,
        VIEW_RENDER_RUNTIME_ROOT,
        VIEW_RENDER_THEME_ROOT,
        VIEW_RENDER_PLATFORM_ROOT,
    ):
        if not root.exists():
            errors.append(f"required view boundary directory is missing: {root.relative_to(REPO_ROOT).as_posix()}")

    if not VIEW_IDE_ROOT.exists():
        return errors

    for path in sorted(VIEW_IDE_ROOT.rglob("*.dart")):
        relative_path = path.relative_to(REPO_ROOT).as_posix()
        text = path.read_text(encoding="utf-8")
        for line_number, line in enumerate(text.splitlines(), start=1):
            stripped = line.strip()
            if not stripped.startswith(("import ", "export ")):
                continue
            if "view_render/" in stripped or "/view_render" in stripped:
                errors.append(
                    f"{relative_path}:{line_number}: view_ide must not depend on view_render"
                )
            for forbidden in VIEW_IDE_FORBIDDEN_IMPORTS:
                if forbidden in stripped:
                    errors.append(
                        f"{relative_path}:{line_number}: view_ide must not import presentation API {forbidden}"
                    )

    return errors


def check_legacy_backend_toolchain_facades() -> list[str]:
    return check_legacy_view_ide_facades(
        legacy_root=LEGACY_BACKEND_TOOLCHAIN_ROOT,
        migrated_root=VIEW_IDE_BACKEND_TOOLCHAIN_ROOT,
        legacy_name="backend_toolchain",
    )


def check_legacy_language_facades() -> list[str]:
    return check_legacy_view_ide_facades(
        legacy_root=LEGACY_LANGUAGE_ROOT,
        migrated_root=VIEW_IDE_LANGUAGE_ROOT,
        legacy_name="language",
    )


def check_legacy_editor_facades() -> list[str]:
    return check_legacy_view_ide_facades(
        legacy_root=LEGACY_EDITOR_ROOT,
        migrated_root=VIEW_IDE_EDITOR_ROOT,
        legacy_name="editor",
        file_names=LEGACY_EDITOR_FACADE_FILES,
    )


def check_legacy_workspace_facades() -> list[str]:
    return check_legacy_view_ide_facades(
        legacy_root=LEGACY_WORKSPACE_ROOT,
        migrated_root=VIEW_IDE_WORKSPACE_ROOT,
        legacy_name="workspace",
        file_names=LEGACY_WORKSPACE_FACADE_FILES,
        export_prefix="../../view_ide/workspace",
    )


def check_legacy_module_host_facades() -> list[str]:
    return check_legacy_view_ide_facades(
        legacy_root=LEGACY_MODULE_HOST_ROOT,
        migrated_root=VIEW_IDE_MODULE_HOST_ROOT,
        legacy_name="module_host",
    )


def check_legacy_runtime_facades() -> list[str]:
    return check_legacy_view_ide_facades(
        legacy_root=LEGACY_RUNTIME_ROOT,
        migrated_root=VIEW_IDE_RUNTIME_ROOT,
        legacy_name="runtime",
        file_names=LEGACY_RUNTIME_FACADE_FILES,
    )


def check_legacy_agent_facades() -> list[str]:
    return check_legacy_view_ide_facades(
        legacy_root=LEGACY_AGENT_ROOT,
        migrated_root=VIEW_IDE_AGENT_ROOT,
        legacy_name="agent",
        file_names=LEGACY_AGENT_FACADE_FILES,
    )


def check_legacy_platform_facades() -> list[str]:
    return check_legacy_view_ide_facades(
        legacy_root=LEGACY_PLATFORM_ROOT,
        migrated_root=VIEW_IDE_PLATFORM_ROOT,
        legacy_name="platform",
        file_names=LEGACY_PLATFORM_FACADE_FILES,
    )


def check_legacy_render_shell_facades() -> list[str]:
    facades = (
        (
            LEGACY_WORKSPACE_ROOT / "shell_model.dart",
            VIEW_RENDER_SHELL_ROOT / "shell_model.dart",
            "../../view_render/shell/shell_model.dart",
        ),
        (
            LEGACY_WORKSPACE_ROOT / "shell_scope.dart",
            VIEW_RENDER_SHELL_ROOT / "shell_scope.dart",
            "../../view_render/shell/shell_scope.dart",
        ),
        (
            LEGACY_APP_LAYOUT_ROOT / "vityo_shell_scaffold.dart",
            VIEW_RENDER_SHELL_ROOT / "vityo_shell_scaffold.dart",
            "../../view_render/shell/vityo_shell_scaffold.dart",
        ),
    )
    errors: list[str] = []
    for legacy_path, target_path, export_target in facades:
        relative_path = legacy_path.relative_to(REPO_ROOT).as_posix()
        if not legacy_path.exists():
            errors.append(f"required legacy render shell facade is missing: {relative_path}")
            continue
        lines = [
            line.strip()
            for line in legacy_path.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
        if lines != [f"export '{export_target}';"]:
            errors.append(
                f"{relative_path}: legacy render shell files must stay one-line facades to view_render/shell"
            )
            continue
        if not target_path.exists():
            errors.append(
                f"{relative_path}: facade target is missing: {target_path.relative_to(REPO_ROOT).as_posix()}"
            )
    return errors


def check_legacy_view_render_facades() -> list[str]:
    facades = (
        (
            LEGACY_AGENT_ROOT / "agent_surface.dart",
            VIEW_RENDER_AGENT_ROOT / "agent_surface.dart",
            "../view_render/agent/agent_surface.dart",
        ),
        (
            LEGACY_EDITOR_ROOT / "editor_surface.dart",
            VIEW_RENDER_EDITOR_ROOT / "editor_surface.dart",
            "../view_render/editor/editor_surface.dart",
        ),
        (
            LEGACY_RUNTIME_ROOT / "runtime_surface.dart",
            VIEW_RENDER_RUNTIME_ROOT / "runtime_surface.dart",
            "../view_render/runtime/runtime_surface.dart",
        ),
        (
            LEGACY_RUNTIME_ROOT / "debug_console_surface.dart",
            VIEW_RENDER_RUNTIME_ROOT / "debug_console_surface.dart",
            "../view_render/runtime/debug_console_surface.dart",
        ),
        (
            LEGACY_THEME_ROOT / "vityo_theme.dart",
            VIEW_RENDER_THEME_ROOT / "vityo_theme.dart",
            "../view_render/theme/vityo_theme.dart",
        ),
        (
            LEGACY_PLATFORM_ROOT / "viewport_profile.dart",
            VIEW_RENDER_PLATFORM_ROOT / "viewport_profile.dart",
            "../view_render/platform/viewport_profile.dart",
        ),
    )
    errors: list[str] = []
    for legacy_path, target_path, export_target in facades:
        relative_path = legacy_path.relative_to(REPO_ROOT).as_posix()
        if not legacy_path.exists():
            errors.append(f"required legacy view_render facade is missing: {relative_path}")
            continue
        lines = [
            line.strip()
            for line in legacy_path.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
        if lines != [f"export '{export_target}';"]:
            errors.append(
                f"{relative_path}: legacy render surface files must stay one-line facades to view_render"
            )
            continue
        if not target_path.exists():
            errors.append(
                f"{relative_path}: facade target is missing: {target_path.relative_to(REPO_ROOT).as_posix()}"
            )
    return errors


def check_shell_runtime_boundary() -> list[str]:
    errors: list[str] = []
    runtime_model = VIEW_IDE_SHELL_RUNTIME_ROOT / "shell_runtime_model.dart"
    render_model = VIEW_RENDER_SHELL_ROOT / "shell_model.dart"

    if runtime_model.exists():
        text = runtime_model.read_text(encoding="utf-8")
        for needle in ("BottomSurfaceTab", "selectBottomTab("):
            if needle in text:
                errors.append(
                    f"{runtime_model.relative_to(REPO_ROOT).as_posix()}: shell runtime must not own render tab state marker {needle}"
                )
    if render_model.exists():
        text = render_model.read_text(encoding="utf-8")
        required_needles = (
            "enum BottomSurfaceTab",
            "class ShellModel extends ShellRuntimeModel",
        )
        for needle in required_needles:
            if needle not in text:
                errors.append(
                    f"{render_model.relative_to(REPO_ROOT).as_posix()} must preserve render shell marker: {needle}"
                )
    return errors


def check_legacy_command_adapter() -> list[str]:
    path = LEGACY_COMMANDS_ROOT / "app_commands.dart"
    if not path.exists():
        return [f"required legacy command adapter is missing: {path.relative_to(REPO_ROOT).as_posix()}"]
    text = path.read_text(encoding="utf-8")
    errors: list[str] = []
    required_needles = (
        "export '../../view_ide/commands/app_commands.dart';",
        "class AppCommandIntent extends Intent",
        "class AppCommandShortcutRegistry",
    )
    for needle in required_needles:
        if needle not in text:
            errors.append(f"{path.relative_to(REPO_ROOT).as_posix()} must preserve command render adapter marker: {needle}")
    return errors


def check_view_ide_language_layout() -> list[str]:
    errors: list[str] = []
    if not VIEW_IDE_LANGUAGE_ROOT.exists():
        return errors

    for submodule in VIEW_IDE_LANGUAGE_SUBMODULES:
        path = VIEW_IDE_LANGUAGE_ROOT / submodule
        if not path.exists():
            errors.append(
                f"required language submodule is missing: {path.relative_to(REPO_ROOT).as_posix()}"
            )

    for path in sorted(VIEW_IDE_LANGUAGE_ROOT.glob("*.dart")):
        relative_path = path.relative_to(REPO_ROOT).as_posix()
        lines = [
            line.strip()
            for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
        if path.name == "language.dart":
            if tuple(lines) != VIEW_IDE_LANGUAGE_BARREL:
                errors.append(
                    f"{relative_path}: language.dart must stay the canonical language barrel"
                )
            continue
        if path.name == "semantic_snapshot_panel.dart":
            # Public facade re-exporting view model types from service internals.
            # Allowed at top-level — not a one-line facade.
            continue
        target = VIEW_IDE_LANGUAGE_FACADES.get(path.name)
        if target is None:
            errors.append(
                f"{relative_path}: top-level view_ide/language files must be registered facades"
            )
            continue
        if lines != [f"export '{target}';"]:
            errors.append(
                f"{relative_path}: top-level language files must stay one-line facades to language submodules"
            )
            continue
        target_path = VIEW_IDE_LANGUAGE_ROOT / target
        if not target_path.exists():
            errors.append(
                f"{relative_path}: facade target is missing: {target_path.relative_to(REPO_ROOT).as_posix()}"
            )

    return errors


def check_view_ide_editor_layout() -> list[str]:
    errors: list[str] = []
    if not VIEW_IDE_EDITOR_ROOT.exists():
        return errors

    for submodule in VIEW_IDE_EDITOR_SUBMODULES:
        path = VIEW_IDE_EDITOR_ROOT / submodule
        if not path.exists():
            errors.append(
                f"required editor submodule is missing: {path.relative_to(REPO_ROOT).as_posix()}"
            )

    for path in sorted(VIEW_IDE_EDITOR_ROOT.glob("*.dart")):
        relative_path = path.relative_to(REPO_ROOT).as_posix()
        lines = [
            line.strip()
            for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
        if path.name == "editor.dart":
            if tuple(lines) != VIEW_IDE_EDITOR_BARREL:
                errors.append(
                    f"{relative_path}: editor.dart must stay the canonical editor barrel"
                )
            continue
        target = VIEW_IDE_EDITOR_FACADES.get(path.name)
        if target is None:
            errors.append(
                f"{relative_path}: top-level view_ide/editor files must be registered facades"
            )
            continue
        if lines != [f"export '{target}';"]:
            errors.append(
                f"{relative_path}: top-level editor files must stay one-line facades to editor submodules"
            )
            continue
        target_path = VIEW_IDE_EDITOR_ROOT / target
        if not target_path.exists():
            errors.append(
                f"{relative_path}: facade target is missing: {target_path.relative_to(REPO_ROOT).as_posix()}"
            )

    return errors


def check_legacy_view_ide_facades(
    *,
    legacy_root: Path,
    migrated_root: Path,
    legacy_name: str,
    file_names: tuple[str, ...] | None = None,
    export_prefix: str | None = None,
) -> list[str]:
    errors: list[str] = []
    if not legacy_root.exists():
        return [
            f"required legacy {legacy_name} facade directory is missing: {legacy_root.relative_to(REPO_ROOT).as_posix()}"
        ]
    if not migrated_root.exists():
        return errors

    paths = (
        [legacy_root / file_name for file_name in file_names]
        if file_names is not None
        else sorted(legacy_root.glob("*.dart"))
    )
    for path in paths:
        relative_path = path.relative_to(REPO_ROOT).as_posix()
        if not path.exists():
            errors.append(f"required legacy {legacy_name} facade is missing: {relative_path}")
            continue
        prefix = export_prefix or f"../view_ide/{legacy_name}"
        expected = f"export '{prefix}/{path.name}';"
        lines = [
            line.strip()
            for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
        if lines != [expected]:
            errors.append(
                f"{relative_path}: legacy {legacy_name} files must stay one-line facades to view_ide/{legacy_name}"
            )
            continue
        target = migrated_root / path.name
        if not target.exists():
            errors.append(
                f"{relative_path}: facade target is missing: {target.relative_to(REPO_ROOT).as_posix()}"
            )

    return errors


def check_worktree_files(files: list[str], max_file_bytes: int) -> list[str]:
    errors: list[str] = []
    for rel_path in files:
        path = REPO_ROOT / rel_path
        if not path.exists():
            continue
        if rel_path.startswith("docs/audit/defects/"):
            errors.append(f"{rel_path}: active audit defect records must stay untracked")
            continue
        if has_forbidden_path_part(rel_path):
            errors.append(f"{rel_path}: contains forbidden generated/dependency path part")
            continue
        if has_forbidden_file_suffix(rel_path):
            errors.append(f"{rel_path}: uses forbidden generated/binary suffix")
            continue
        if path.is_file() and path.stat().st_size > max_file_bytes:
            errors.append(f"{rel_path}: file size {path.stat().st_size} bytes exceeds soft limit {max_file_bytes} bytes")
            continue
        if path.is_file() and is_binary_file(rel_path) and not is_allowed_binary(rel_path):
            errors.append(f"{rel_path}: unexpected binary file; add a narrow allowlist only if intentional")
    return errors


def check_push_history(rev_range: str, max_file_bytes: int) -> list[str]:
    rev_list = subprocess.run(
        ["git", "-C", str(REPO_ROOT), "rev-list", "--objects", rev_range],
        check=True,
        text=True,
        capture_output=True,
    )
    if not rev_list.stdout.strip():
        return []
    batch = subprocess.run(
        [
            "git",
            "-C",
            str(REPO_ROOT),
            "cat-file",
            "--batch-check=%(objecttype) %(objectname) %(objectsize) %(rest)",
        ],
        input=rev_list.stdout,
        check=True,
        text=True,
        capture_output=True,
    )
    errors: list[str] = []
    for line in batch.stdout.splitlines():
        parts = line.split(" ", 3)
        if len(parts) != 4:
            continue
        object_type, _oid, object_size, rel_path = parts
        if object_type != "blob" or not rel_path:
            continue
        if rel_path.startswith("docs/audit/defects/"):
            errors.append(f"{rel_path}: appears in pushed history range {rev_range}; active audit defect records must stay untracked")
        if has_forbidden_path_part(rel_path):
            errors.append(f"{rel_path}: appears in pushed history range {rev_range} and contains a forbidden generated/dependency path part")
        if has_forbidden_file_suffix(rel_path):
            errors.append(f"{rel_path}: appears in pushed history range {rev_range} with a forbidden generated/binary suffix")
        try:
            size = int(object_size)
        except ValueError:
            continue
        if size > max_file_bytes:
            errors.append(f"{rel_path}: blob size {size} bytes in pushed history range {rev_range} exceeds soft limit {max_file_bytes} bytes")
    return errors


def print_report(header: str, errors: list[str]) -> int:
    if not errors:
        print(f"[repo-hygiene] {header}: OK")
        return 0
    print(f"[repo-hygiene] {header}: FAILED", file=sys.stderr)
    for error in sorted(set(errors)):
        print(f"  - {error}", file=sys.stderr)
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Vityo repository hygiene gate")
    parser.add_argument("--mode", choices=("tracked", "staged", "push"), default="staged")
    parser.add_argument("--range", dest="rev_range", help="Explicit revision range for --mode push")
    parser.add_argument("--max-file-bytes", type=int, default=DEFAULT_MAX_FILE_BYTES)
    args = parser.parse_args()

    errors = check_gitignore()
    errors.extend(check_doc_references())
    errors.extend(check_project_branding())
    errors.extend(check_view_boundary_imports())
    errors.extend(check_legacy_backend_toolchain_facades())
    errors.extend(check_legacy_command_adapter())
    errors.extend(check_legacy_editor_facades())
    errors.extend(check_legacy_language_facades())
    errors.extend(check_legacy_workspace_facades())
    errors.extend(check_legacy_module_host_facades())
    errors.extend(check_legacy_runtime_facades())
    errors.extend(check_legacy_render_shell_facades())
    errors.extend(check_legacy_view_render_facades())
    errors.extend(check_shell_runtime_boundary())
    errors.extend(check_legacy_agent_facades())
    errors.extend(check_legacy_platform_facades())
    errors.extend(check_view_ide_language_layout())
    errors.extend(check_view_ide_editor_layout())

    if args.mode == "push":
        rev_range = args.rev_range or default_push_range()
        errors.extend(check_push_history(rev_range, args.max_file_bytes))
        return print_report(f"push range {rev_range}", errors)

    files = staged_files() if args.mode == "staged" else tracked_files()
    if not files:
        if errors:
            return print_report(f"{args.mode} policy", errors)
        print(f"[repo-hygiene] {args.mode}: nothing to check")
        return 0
    errors.extend(check_worktree_files(files, args.max_file_bytes))
    return print_report(args.mode, errors)


if __name__ == "__main__":
    raise SystemExit(main())

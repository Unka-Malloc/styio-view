#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
GATE_PATH = REPO_ROOT / "scripts" / "repo-hygiene-gate.py"


def load_gate_module():
    spec = importlib.util.spec_from_file_location(
        "repo_hygiene_gate",
        GATE_PATH,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {GATE_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ViewBoundaryImportPolicyTest(unittest.TestCase):
    def setUp(self) -> None:
        self.gate = load_gate_module()

    def _check_source(self, source: str) -> list[str]:
        with tempfile.TemporaryDirectory(
            prefix="view-boundary-",
            dir=REPO_ROOT,
        ) as tmp_name:
            tmp_root = Path(tmp_name)
            view_ide = tmp_root / "view_ide"
            view_render = tmp_root / "view_render"
            view_ide.mkdir()
            view_render.mkdir()
            (view_ide / "sample.dart").write_text(source, encoding="utf-8")

            original_ide_root = self.gate.VIEW_IDE_ROOT
            original_render_root = self.gate.VIEW_RENDER_ROOT
            self.gate.VIEW_IDE_ROOT = view_ide
            self.gate.VIEW_RENDER_ROOT = view_render
            try:
                return self.gate.check_view_boundary_imports()
            finally:
                self.gate.VIEW_IDE_ROOT = original_ide_root
                self.gate.VIEW_RENDER_ROOT = original_render_root

    def test_view_ide_accepts_pure_dart_boundary_exports(self) -> None:
        errors = self._check_source(
            "export '../backend_toolchain/backend_toolchain.dart';\n"
            "class IdeStateSnapshot {}\n"
        )

        self.assertEqual(errors, [])

    def test_view_ide_rejects_view_render_dependency(self) -> None:
        errors = self._check_source(
            "export '../view_render/view_render.dart';\n"
        )

        self.assertTrue(
            any("view_ide must not depend on view_render" in error for error in errors),
            errors,
        )

    def test_view_ide_rejects_flutter_presentation_imports(self) -> None:
        errors = self._check_source(
            "import 'package:flutter/cupertino.dart';\n"
            "import 'package:flutter/material.dart';\n"
            "import 'package:flutter/widgets.dart';\n"
            "import 'dart:ui';\n"
        )
        joined = "\n".join(errors)

        self.assertIn("package:flutter/cupertino.dart", joined)
        self.assertIn("package:flutter/material.dart", joined)
        self.assertIn("package:flutter/widgets.dart", joined)
        self.assertIn("dart:ui", joined)

    def test_current_view_ide_language_layout_matches_registered_contract(self) -> None:
        self.assertEqual(self.gate.check_view_ide_language_layout(), [])

    def test_current_view_ide_editor_layout_matches_registered_contract(self) -> None:
        self.assertEqual(self.gate.check_view_ide_editor_layout(), [])

    def test_project_branding_accepts_vityo_entrypoints(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="project-branding-",
            dir=REPO_ROOT,
        ) as tmp_name:
            tmp_root = Path(tmp_name)
            root_readme = tmp_root / "README.md"
            docs_readme = tmp_root / "docs" / "README.md"
            app_readme = tmp_root / "frontend" / "vityo_app" / "README.md"
            pubspec = tmp_root / "frontend" / "vityo_app" / "pubspec.yaml"
            docs_readme.parent.mkdir(parents=True)
            app_readme.parent.mkdir(parents=True)
            root_readme.write_text("# Vityo\n", encoding="utf-8")
            docs_readme.write_text("# Vityo Docs\n", encoding="utf-8")
            app_readme.write_text("# Vityo Flutter Shell\n", encoding="utf-8")
            pubspec.write_text(
                "description: Vityo IDE editor shell for web, desktop, and mobile targets.\n",
                encoding="utf-8",
            )

            original_root = self.gate.REPO_ROOT
            original_headings = self.gate.REQUIRED_PROJECT_BRAND_HEADINGS
            original_metadata = self.gate.REQUIRED_PROJECT_BRAND_METADATA
            self.gate.REPO_ROOT = tmp_root
            self.gate.REQUIRED_PROJECT_BRAND_HEADINGS = {
                Path("README.md"): "# Vityo",
                Path("docs/README.md"): "# Vityo Docs",
                Path("frontend/vityo_app/README.md"): "# Vityo Flutter Shell",
            }
            self.gate.REQUIRED_PROJECT_BRAND_METADATA = {
                Path("frontend/vityo_app/pubspec.yaml"): "description: Vityo IDE editor shell",
            }
            try:
                errors = self.gate.check_project_branding()
            finally:
                self.gate.REPO_ROOT = original_root
                self.gate.REQUIRED_PROJECT_BRAND_HEADINGS = original_headings
                self.gate.REQUIRED_PROJECT_BRAND_METADATA = original_metadata

        self.assertEqual(errors, [])

    def test_project_branding_rejects_legacy_entrypoint_heading(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="project-branding-",
            dir=REPO_ROOT,
        ) as tmp_name:
            tmp_root = Path(tmp_name)
            root_readme = tmp_root / "README.md"
            docs_readme = tmp_root / "docs" / "README.md"
            app_readme = tmp_root / "frontend" / "vityo_app" / "README.md"
            pubspec = tmp_root / "frontend" / "vityo_app" / "pubspec.yaml"
            docs_readme.parent.mkdir(parents=True)
            app_readme.parent.mkdir(parents=True)
            root_readme.write_text("# " + "Styio" + " View\n", encoding="utf-8")
            docs_readme.write_text("# Vityo Docs\n", encoding="utf-8")
            app_readme.write_text("# Vityo Flutter Shell\n", encoding="utf-8")
            pubspec.write_text(
                "description: Vityo IDE editor shell for web, desktop, and mobile targets.\n",
                encoding="utf-8",
            )

            original_root = self.gate.REPO_ROOT
            original_headings = self.gate.REQUIRED_PROJECT_BRAND_HEADINGS
            original_metadata = self.gate.REQUIRED_PROJECT_BRAND_METADATA
            self.gate.REPO_ROOT = tmp_root
            self.gate.REQUIRED_PROJECT_BRAND_HEADINGS = {
                Path("README.md"): "# Vityo",
                Path("docs/README.md"): "# Vityo Docs",
                Path("frontend/vityo_app/README.md"): "# Vityo Flutter Shell",
            }
            self.gate.REQUIRED_PROJECT_BRAND_METADATA = {
                Path("frontend/vityo_app/pubspec.yaml"): "description: Vityo IDE editor shell",
            }
            try:
                errors = self.gate.check_project_branding()
            finally:
                self.gate.REPO_ROOT = original_root
                self.gate.REQUIRED_PROJECT_BRAND_HEADINGS = original_headings
                self.gate.REQUIRED_PROJECT_BRAND_METADATA = original_metadata

        self.assertTrue(
            any("README.md must use project heading: # Vityo" in error for error in errors),
            errors,
        )

    def test_project_branding_accepts_platform_display_names(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="platform-branding-",
            dir=REPO_ROOT,
        ) as tmp_name:
            tmp_root = Path(tmp_name)
            linux_title = tmp_root / "frontend" / "vityo_app" / "linux" / "runner" / "my_application.cc"
            ios_info = tmp_root / "frontend" / "vityo_app" / "ios" / "Runner" / "Info.plist"
            windows_rc = tmp_root / "frontend" / "vityo_app" / "windows" / "runner" / "Runner.rc"
            macos_config = (
                tmp_root
                / "frontend"
                / "vityo_app"
                / "macos"
                / "Runner"
                / "Configs"
                / "AppInfo.xcconfig"
            )
            for path in (linux_title, ios_info, windows_rc, macos_config):
                path.parent.mkdir(parents=True, exist_ok=True)
            linux_title.write_text('gtk_window_set_title(window, "Vityo");\n', encoding="utf-8")
            ios_info.write_text(
                "<key>CFBundleDisplayName</key>\n"
                "\t<string>Vityo</string>\n"
                "<key>CFBundleName</key>\n"
                "\t<string>Vityo</string>\n",
                encoding="utf-8",
            )
            windows_rc.write_text(
                'VALUE "FileDescription", "Vityo"\n'
                'VALUE "InternalName", "Vityo"\n'
                'VALUE "ProductName", "Vityo"\n',
                encoding="utf-8",
            )
            macos_config.write_text("PRODUCT_NAME = Vityo\n", encoding="utf-8")

            original_root = self.gate.REPO_ROOT
            original_headings = self.gate.REQUIRED_PROJECT_BRAND_HEADINGS
            original_metadata = self.gate.REQUIRED_PROJECT_BRAND_METADATA
            self.gate.REPO_ROOT = tmp_root
            self.gate.REQUIRED_PROJECT_BRAND_HEADINGS = {}
            self.gate.REQUIRED_PROJECT_BRAND_METADATA = {
                Path("frontend/vityo_app/ios/Runner/Info.plist"): (
                    "<key>CFBundleDisplayName</key>\n\t<string>Vityo</string>",
                    "<key>CFBundleName</key>\n\t<string>Vityo</string>",
                ),
                Path("frontend/vityo_app/linux/runner/my_application.cc"): 'gtk_window_set_title(window, "Vityo");',
                Path("frontend/vityo_app/windows/runner/Runner.rc"): (
                    'VALUE "FileDescription", "Vityo"',
                    'VALUE "InternalName", "Vityo"',
                    'VALUE "ProductName", "Vityo"',
                ),
                Path("frontend/vityo_app/macos/Runner/Configs/AppInfo.xcconfig"): "PRODUCT_NAME = Vityo",
            }
            try:
                errors = self.gate.check_project_branding()
            finally:
                self.gate.REPO_ROOT = original_root
                self.gate.REQUIRED_PROJECT_BRAND_HEADINGS = original_headings
                self.gate.REQUIRED_PROJECT_BRAND_METADATA = original_metadata

        self.assertEqual(errors, [])

    def test_project_branding_rejects_platform_display_name_regression(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="platform-branding-",
            dir=REPO_ROOT,
        ) as tmp_name:
            tmp_root = Path(tmp_name)
            linux_title = tmp_root / "frontend" / "vityo_app" / "linux" / "runner" / "my_application.cc"
            linux_title.parent.mkdir(parents=True, exist_ok=True)
            linux_title.write_text('gtk_window_set_title(window, "vityo_app");\n', encoding="utf-8")

            original_root = self.gate.REPO_ROOT
            original_headings = self.gate.REQUIRED_PROJECT_BRAND_HEADINGS
            original_metadata = self.gate.REQUIRED_PROJECT_BRAND_METADATA
            self.gate.REPO_ROOT = tmp_root
            self.gate.REQUIRED_PROJECT_BRAND_HEADINGS = {}
            self.gate.REQUIRED_PROJECT_BRAND_METADATA = {
                Path("frontend/vityo_app/linux/runner/my_application.cc"): 'gtk_window_set_title(window, "Vityo");',
            }
            try:
                errors = self.gate.check_project_branding()
            finally:
                self.gate.REPO_ROOT = original_root
                self.gate.REQUIRED_PROJECT_BRAND_HEADINGS = original_headings
                self.gate.REQUIRED_PROJECT_BRAND_METADATA = original_metadata

        self.assertTrue(
            any("must use project metadata marker" in error for error in errors),
            errors,
        )

    def test_legacy_backend_toolchain_accepts_one_line_facade(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="backend-facade-",
            dir=REPO_ROOT,
        ) as tmp_name:
            tmp_root = Path(tmp_name)
            legacy = tmp_root / "backend_toolchain"
            migrated = tmp_root / "view_ide" / "backend_toolchain"
            legacy.mkdir()
            migrated.mkdir(parents=True)
            (legacy / "execution_adapter.dart").write_text(
                "export '../view_ide/backend_toolchain/execution_adapter.dart';\n",
                encoding="utf-8",
            )
            (migrated / "execution_adapter.dart").write_text(
                "class ExecutionAdapter {}\n",
                encoding="utf-8",
            )

            original_legacy = self.gate.LEGACY_BACKEND_TOOLCHAIN_ROOT
            original_migrated = self.gate.VIEW_IDE_BACKEND_TOOLCHAIN_ROOT
            self.gate.LEGACY_BACKEND_TOOLCHAIN_ROOT = legacy
            self.gate.VIEW_IDE_BACKEND_TOOLCHAIN_ROOT = migrated
            try:
                errors = self.gate.check_legacy_backend_toolchain_facades()
            finally:
                self.gate.LEGACY_BACKEND_TOOLCHAIN_ROOT = original_legacy
                self.gate.VIEW_IDE_BACKEND_TOOLCHAIN_ROOT = original_migrated

        self.assertEqual(errors, [])

    def test_legacy_backend_toolchain_rejects_implementation_body(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="backend-facade-",
            dir=REPO_ROOT,
        ) as tmp_name:
            tmp_root = Path(tmp_name)
            legacy = tmp_root / "backend_toolchain"
            migrated = tmp_root / "view_ide" / "backend_toolchain"
            legacy.mkdir()
            migrated.mkdir(parents=True)
            (legacy / "execution_adapter.dart").write_text(
                "class ExecutionAdapter {}\n",
                encoding="utf-8",
            )
            (migrated / "execution_adapter.dart").write_text(
                "class ExecutionAdapter {}\n",
                encoding="utf-8",
            )

            original_legacy = self.gate.LEGACY_BACKEND_TOOLCHAIN_ROOT
            original_migrated = self.gate.VIEW_IDE_BACKEND_TOOLCHAIN_ROOT
            self.gate.LEGACY_BACKEND_TOOLCHAIN_ROOT = legacy
            self.gate.VIEW_IDE_BACKEND_TOOLCHAIN_ROOT = migrated
            try:
                errors = self.gate.check_legacy_backend_toolchain_facades()
            finally:
                self.gate.LEGACY_BACKEND_TOOLCHAIN_ROOT = original_legacy
                self.gate.VIEW_IDE_BACKEND_TOOLCHAIN_ROOT = original_migrated

        self.assertTrue(
            any("must stay one-line facades" in error for error in errors),
            errors,
        )

    def test_legacy_language_accepts_one_line_facade(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="language-facade-",
            dir=REPO_ROOT,
        ) as tmp_name:
            tmp_root = Path(tmp_name)
            legacy = tmp_root / "language"
            migrated = tmp_root / "view_ide" / "language"
            legacy.mkdir()
            migrated.mkdir(parents=True)
            (legacy / "styio_syntax_highlighter.dart").write_text(
                "export '../view_ide/language/styio_syntax_highlighter.dart';\n",
                encoding="utf-8",
            )
            (migrated / "styio_syntax_highlighter.dart").write_text(
                "class StyioSyntaxHighlighter {}\n",
                encoding="utf-8",
            )

            original_legacy = self.gate.LEGACY_LANGUAGE_ROOT
            original_migrated = self.gate.VIEW_IDE_LANGUAGE_ROOT
            self.gate.LEGACY_LANGUAGE_ROOT = legacy
            self.gate.VIEW_IDE_LANGUAGE_ROOT = migrated
            try:
                errors = self.gate.check_legacy_language_facades()
            finally:
                self.gate.LEGACY_LANGUAGE_ROOT = original_legacy
                self.gate.VIEW_IDE_LANGUAGE_ROOT = original_migrated

        self.assertEqual(errors, [])

    def test_legacy_language_rejects_implementation_body(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="language-facade-",
            dir=REPO_ROOT,
        ) as tmp_name:
            tmp_root = Path(tmp_name)
            legacy = tmp_root / "language"
            migrated = tmp_root / "view_ide" / "language"
            legacy.mkdir()
            migrated.mkdir(parents=True)
            (legacy / "styio_syntax_highlighter.dart").write_text(
                "class StyioSyntaxHighlighter {}\n",
                encoding="utf-8",
            )
            (migrated / "styio_syntax_highlighter.dart").write_text(
                "class StyioSyntaxHighlighter {}\n",
                encoding="utf-8",
            )

            original_legacy = self.gate.LEGACY_LANGUAGE_ROOT
            original_migrated = self.gate.VIEW_IDE_LANGUAGE_ROOT
            self.gate.LEGACY_LANGUAGE_ROOT = legacy
            self.gate.VIEW_IDE_LANGUAGE_ROOT = migrated
            try:
                errors = self.gate.check_legacy_language_facades()
            finally:
                self.gate.LEGACY_LANGUAGE_ROOT = original_legacy
                self.gate.VIEW_IDE_LANGUAGE_ROOT = original_migrated

        self.assertTrue(
            any("legacy language files must stay one-line facades" in error for error in errors),
            errors,
        )

    def test_legacy_workspace_accepts_custom_relative_facade(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="workspace-facade-",
            dir=REPO_ROOT,
        ) as tmp_name:
            tmp_root = Path(tmp_name)
            legacy = tmp_root / "app" / "state"
            migrated = tmp_root / "view_ide" / "workspace"
            legacy.mkdir(parents=True)
            migrated.mkdir(parents=True)
            (legacy / "workspace_controller.dart").write_text(
                "export '../../view_ide/workspace/workspace_controller.dart';\n",
                encoding="utf-8",
            )
            (migrated / "workspace_controller.dart").write_text(
                "class WorkspaceController {}\n",
                encoding="utf-8",
            )

            errors = self.gate.check_legacy_view_ide_facades(
                legacy_root=legacy,
                migrated_root=migrated,
                legacy_name="workspace",
                file_names=("workspace_controller.dart",),
                export_prefix="../../view_ide/workspace",
            )

        self.assertEqual(errors, [])

    def test_legacy_command_adapter_keeps_render_adapter_markers(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="commands-adapter-",
            dir=REPO_ROOT,
        ) as tmp_name:
            command_root = Path(tmp_name) / "app" / "commands"
            command_root.mkdir(parents=True)
            (command_root / "app_commands.dart").write_text(
                "import 'package:flutter/widgets.dart';\n"
                "export '../../view_ide/commands/app_commands.dart';\n"
                "class AppCommandIntent extends Intent { const AppCommandIntent(); }\n"
                "class AppCommandShortcutRegistry {}\n",
                encoding="utf-8",
            )

            original_root = self.gate.LEGACY_COMMANDS_ROOT
            self.gate.LEGACY_COMMANDS_ROOT = command_root
            try:
                errors = self.gate.check_legacy_command_adapter()
            finally:
                self.gate.LEGACY_COMMANDS_ROOT = original_root

        self.assertEqual(errors, [])

    def test_legacy_command_adapter_rejects_missing_shortcut_adapter(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="commands-adapter-",
            dir=REPO_ROOT,
        ) as tmp_name:
            command_root = Path(tmp_name) / "app" / "commands"
            command_root.mkdir(parents=True)
            (command_root / "app_commands.dart").write_text(
                "export '../../view_ide/commands/app_commands.dart';\n",
                encoding="utf-8",
            )

            original_root = self.gate.LEGACY_COMMANDS_ROOT
            self.gate.LEGACY_COMMANDS_ROOT = command_root
            try:
                errors = self.gate.check_legacy_command_adapter()
            finally:
                self.gate.LEGACY_COMMANDS_ROOT = original_root

        self.assertTrue(
            any("AppCommandShortcutRegistry" in error for error in errors),
            errors,
        )

    def test_legacy_render_shell_accepts_one_line_facades(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="render-shell-facade-",
            dir=REPO_ROOT,
        ) as tmp_name:
            tmp_root = Path(tmp_name)
            legacy_state = tmp_root / "app" / "state"
            legacy_layout = tmp_root / "app" / "layout"
            render_shell = tmp_root / "view_render" / "shell"
            legacy_state.mkdir(parents=True)
            legacy_layout.mkdir(parents=True)
            render_shell.mkdir(parents=True)
            (legacy_state / "shell_model.dart").write_text(
                "export '../../view_render/shell/shell_model.dart';\n",
                encoding="utf-8",
            )
            (legacy_state / "shell_scope.dart").write_text(
                "export '../../view_render/shell/shell_scope.dart';\n",
                encoding="utf-8",
            )
            (legacy_layout / "vityo_shell_scaffold.dart").write_text(
                "export '../../view_render/shell/vityo_shell_scaffold.dart';\n",
                encoding="utf-8",
            )
            for filename in (
                "shell_model.dart",
                "shell_scope.dart",
                "vityo_shell_scaffold.dart",
            ):
                (render_shell / filename).write_text(
                    "class Placeholder {}\n",
                    encoding="utf-8",
                )

            original_state = self.gate.LEGACY_WORKSPACE_ROOT
            original_layout = self.gate.LEGACY_APP_LAYOUT_ROOT
            original_render_shell = self.gate.VIEW_RENDER_SHELL_ROOT
            self.gate.LEGACY_WORKSPACE_ROOT = legacy_state
            self.gate.LEGACY_APP_LAYOUT_ROOT = legacy_layout
            self.gate.VIEW_RENDER_SHELL_ROOT = render_shell
            try:
                errors = self.gate.check_legacy_render_shell_facades()
            finally:
                self.gate.LEGACY_WORKSPACE_ROOT = original_state
                self.gate.LEGACY_APP_LAYOUT_ROOT = original_layout
                self.gate.VIEW_RENDER_SHELL_ROOT = original_render_shell

        self.assertEqual(errors, [])

    def test_legacy_render_shell_rejects_implementation_body(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="render-shell-facade-",
            dir=REPO_ROOT,
        ) as tmp_name:
            tmp_root = Path(tmp_name)
            legacy_state = tmp_root / "app" / "state"
            legacy_layout = tmp_root / "app" / "layout"
            render_shell = tmp_root / "view_render" / "shell"
            legacy_state.mkdir(parents=True)
            legacy_layout.mkdir(parents=True)
            render_shell.mkdir(parents=True)
            (legacy_state / "shell_model.dart").write_text(
                "class ShellModel {}\n",
                encoding="utf-8",
            )
            (legacy_state / "shell_scope.dart").write_text(
                "export '../../view_render/shell/shell_scope.dart';\n",
                encoding="utf-8",
            )
            (legacy_layout / "vityo_shell_scaffold.dart").write_text(
                "export '../../view_render/shell/vityo_shell_scaffold.dart';\n",
                encoding="utf-8",
            )
            for filename in (
                "shell_model.dart",
                "shell_scope.dart",
                "vityo_shell_scaffold.dart",
            ):
                (render_shell / filename).write_text(
                    "class Placeholder {}\n",
                    encoding="utf-8",
                )

            original_state = self.gate.LEGACY_WORKSPACE_ROOT
            original_layout = self.gate.LEGACY_APP_LAYOUT_ROOT
            original_render_shell = self.gate.VIEW_RENDER_SHELL_ROOT
            self.gate.LEGACY_WORKSPACE_ROOT = legacy_state
            self.gate.LEGACY_APP_LAYOUT_ROOT = legacy_layout
            self.gate.VIEW_RENDER_SHELL_ROOT = render_shell
            try:
                errors = self.gate.check_legacy_render_shell_facades()
            finally:
                self.gate.LEGACY_WORKSPACE_ROOT = original_state
                self.gate.LEGACY_APP_LAYOUT_ROOT = original_layout
                self.gate.VIEW_RENDER_SHELL_ROOT = original_render_shell

        self.assertTrue(
            any("legacy render shell files must stay one-line facades" in error for error in errors),
            errors,
        )

    def test_legacy_view_render_surfaces_accept_one_line_facades(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="view-render-facade-",
            dir=REPO_ROOT,
        ) as tmp_name:
            tmp_root = Path(tmp_name)
            legacy_agent = tmp_root / "agent"
            legacy_editor = tmp_root / "editor"
            legacy_runtime = tmp_root / "runtime"
            legacy_theme = tmp_root / "theme"
            legacy_platform = tmp_root / "platform"
            render_agent = tmp_root / "view_render" / "agent"
            render_editor = tmp_root / "view_render" / "editor"
            render_runtime = tmp_root / "view_render" / "runtime"
            render_theme = tmp_root / "view_render" / "theme"
            render_platform = tmp_root / "view_render" / "platform"
            for path in (
                legacy_agent,
                legacy_editor,
                legacy_runtime,
                legacy_theme,
                legacy_platform,
                render_agent,
                render_editor,
                render_runtime,
                render_theme,
                render_platform,
            ):
                path.mkdir(parents=True)
            (legacy_agent / "agent_surface.dart").write_text(
                "export '../view_render/agent/agent_surface.dart';\n",
                encoding="utf-8",
            )
            (legacy_editor / "editor_surface.dart").write_text(
                "export '../view_render/editor/editor_surface.dart';\n",
                encoding="utf-8",
            )
            (legacy_runtime / "runtime_surface.dart").write_text(
                "export '../view_render/runtime/runtime_surface.dart';\n",
                encoding="utf-8",
            )
            (legacy_runtime / "debug_console_surface.dart").write_text(
                "export '../view_render/runtime/debug_console_surface.dart';\n",
                encoding="utf-8",
            )
            (legacy_theme / "vityo_theme.dart").write_text(
                "export '../view_render/theme/vityo_theme.dart';\n",
                encoding="utf-8",
            )
            (legacy_platform / "viewport_profile.dart").write_text(
                "export '../view_render/platform/viewport_profile.dart';\n",
                encoding="utf-8",
            )
            for root, filename in (
                (render_agent, "agent_surface.dart"),
                (render_editor, "editor_surface.dart"),
                (render_runtime, "runtime_surface.dart"),
                (render_runtime, "debug_console_surface.dart"),
                (render_theme, "vityo_theme.dart"),
                (render_platform, "viewport_profile.dart"),
            ):
                (root / filename).write_text(
                    "class Placeholder {}\n",
                    encoding="utf-8",
                )

            originals = (
                self.gate.LEGACY_AGENT_ROOT,
                self.gate.LEGACY_EDITOR_ROOT,
                self.gate.LEGACY_RUNTIME_ROOT,
                self.gate.LEGACY_THEME_ROOT,
                self.gate.LEGACY_PLATFORM_ROOT,
                self.gate.VIEW_RENDER_AGENT_ROOT,
                self.gate.VIEW_RENDER_EDITOR_ROOT,
                self.gate.VIEW_RENDER_RUNTIME_ROOT,
                self.gate.VIEW_RENDER_THEME_ROOT,
                self.gate.VIEW_RENDER_PLATFORM_ROOT,
            )
            self.gate.LEGACY_AGENT_ROOT = legacy_agent
            self.gate.LEGACY_EDITOR_ROOT = legacy_editor
            self.gate.LEGACY_RUNTIME_ROOT = legacy_runtime
            self.gate.LEGACY_THEME_ROOT = legacy_theme
            self.gate.LEGACY_PLATFORM_ROOT = legacy_platform
            self.gate.VIEW_RENDER_AGENT_ROOT = render_agent
            self.gate.VIEW_RENDER_EDITOR_ROOT = render_editor
            self.gate.VIEW_RENDER_RUNTIME_ROOT = render_runtime
            self.gate.VIEW_RENDER_THEME_ROOT = render_theme
            self.gate.VIEW_RENDER_PLATFORM_ROOT = render_platform
            try:
                errors = self.gate.check_legacy_view_render_facades()
            finally:
                (
                    self.gate.LEGACY_AGENT_ROOT,
                    self.gate.LEGACY_EDITOR_ROOT,
                    self.gate.LEGACY_RUNTIME_ROOT,
                    self.gate.LEGACY_THEME_ROOT,
                    self.gate.LEGACY_PLATFORM_ROOT,
                    self.gate.VIEW_RENDER_AGENT_ROOT,
                    self.gate.VIEW_RENDER_EDITOR_ROOT,
                    self.gate.VIEW_RENDER_RUNTIME_ROOT,
                    self.gate.VIEW_RENDER_THEME_ROOT,
                    self.gate.VIEW_RENDER_PLATFORM_ROOT,
                ) = originals

        self.assertEqual(errors, [])

    def test_legacy_view_render_surfaces_reject_implementation_body(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="view-render-facade-",
            dir=REPO_ROOT,
        ) as tmp_name:
            tmp_root = Path(tmp_name)
            legacy_agent = tmp_root / "agent"
            render_agent = tmp_root / "view_render" / "agent"
            for path in (
                legacy_agent,
                tmp_root / "editor",
                tmp_root / "runtime",
                tmp_root / "theme",
                tmp_root / "platform",
                render_agent,
                tmp_root / "view_render" / "editor",
                tmp_root / "view_render" / "runtime",
                tmp_root / "view_render" / "theme",
                tmp_root / "view_render" / "platform",
            ):
                path.mkdir(parents=True)
            (legacy_agent / "agent_surface.dart").write_text(
                "class AgentSurface {}\n",
                encoding="utf-8",
            )
            for legacy_root, filename, export_target in (
                (tmp_root / "editor", "editor_surface.dart", "../view_render/editor/editor_surface.dart"),
                (tmp_root / "runtime", "runtime_surface.dart", "../view_render/runtime/runtime_surface.dart"),
                (tmp_root / "runtime", "debug_console_surface.dart", "../view_render/runtime/debug_console_surface.dart"),
                (tmp_root / "theme", "vityo_theme.dart", "../view_render/theme/vityo_theme.dart"),
                (tmp_root / "platform", "viewport_profile.dart", "../view_render/platform/viewport_profile.dart"),
            ):
                (legacy_root / filename).write_text(
                    f"export '{export_target}';\n",
                    encoding="utf-8",
                )
            for render_root, filename in (
                (render_agent, "agent_surface.dart"),
                (tmp_root / "view_render" / "editor", "editor_surface.dart"),
                (tmp_root / "view_render" / "runtime", "runtime_surface.dart"),
                (tmp_root / "view_render" / "runtime", "debug_console_surface.dart"),
                (tmp_root / "view_render" / "theme", "vityo_theme.dart"),
                (tmp_root / "view_render" / "platform", "viewport_profile.dart"),
            ):
                (render_root / filename).write_text(
                    "class Placeholder {}\n",
                    encoding="utf-8",
                )

            originals = (
                self.gate.LEGACY_AGENT_ROOT,
                self.gate.LEGACY_EDITOR_ROOT,
                self.gate.LEGACY_RUNTIME_ROOT,
                self.gate.LEGACY_THEME_ROOT,
                self.gate.LEGACY_PLATFORM_ROOT,
                self.gate.VIEW_RENDER_AGENT_ROOT,
                self.gate.VIEW_RENDER_EDITOR_ROOT,
                self.gate.VIEW_RENDER_RUNTIME_ROOT,
                self.gate.VIEW_RENDER_THEME_ROOT,
                self.gate.VIEW_RENDER_PLATFORM_ROOT,
            )
            self.gate.LEGACY_AGENT_ROOT = legacy_agent
            self.gate.LEGACY_EDITOR_ROOT = tmp_root / "editor"
            self.gate.LEGACY_RUNTIME_ROOT = tmp_root / "runtime"
            self.gate.LEGACY_THEME_ROOT = tmp_root / "theme"
            self.gate.LEGACY_PLATFORM_ROOT = tmp_root / "platform"
            self.gate.VIEW_RENDER_AGENT_ROOT = render_agent
            self.gate.VIEW_RENDER_EDITOR_ROOT = tmp_root / "view_render" / "editor"
            self.gate.VIEW_RENDER_RUNTIME_ROOT = tmp_root / "view_render" / "runtime"
            self.gate.VIEW_RENDER_THEME_ROOT = tmp_root / "view_render" / "theme"
            self.gate.VIEW_RENDER_PLATFORM_ROOT = tmp_root / "view_render" / "platform"
            try:
                errors = self.gate.check_legacy_view_render_facades()
            finally:
                (
                    self.gate.LEGACY_AGENT_ROOT,
                    self.gate.LEGACY_EDITOR_ROOT,
                    self.gate.LEGACY_RUNTIME_ROOT,
                    self.gate.LEGACY_THEME_ROOT,
                    self.gate.LEGACY_PLATFORM_ROOT,
                    self.gate.VIEW_RENDER_AGENT_ROOT,
                    self.gate.VIEW_RENDER_EDITOR_ROOT,
                    self.gate.VIEW_RENDER_RUNTIME_ROOT,
                    self.gate.VIEW_RENDER_THEME_ROOT,
                    self.gate.VIEW_RENDER_PLATFORM_ROOT,
                ) = originals

        self.assertTrue(
            any("legacy render surface files must stay one-line facades" in error for error in errors),
            errors,
        )

    def test_shell_runtime_boundary_accepts_runtime_render_split(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="shell-runtime-",
            dir=REPO_ROOT,
        ) as tmp_name:
            tmp_root = Path(tmp_name)
            runtime_root = tmp_root / "view_ide" / "shell_runtime"
            render_shell = tmp_root / "view_render" / "shell"
            runtime_root.mkdir(parents=True)
            render_shell.mkdir(parents=True)
            (runtime_root / "shell_runtime_model.dart").write_text(
                "class ShellRuntimeModel {}\n",
                encoding="utf-8",
            )
            (render_shell / "shell_model.dart").write_text(
                "enum BottomSurfaceTab { runtime }\n"
                "class ShellModel extends ShellRuntimeModel {}\n",
                encoding="utf-8",
            )

            original_runtime = self.gate.VIEW_IDE_SHELL_RUNTIME_ROOT
            original_render_shell = self.gate.VIEW_RENDER_SHELL_ROOT
            self.gate.VIEW_IDE_SHELL_RUNTIME_ROOT = runtime_root
            self.gate.VIEW_RENDER_SHELL_ROOT = render_shell
            try:
                errors = self.gate.check_shell_runtime_boundary()
            finally:
                self.gate.VIEW_IDE_SHELL_RUNTIME_ROOT = original_runtime
                self.gate.VIEW_RENDER_SHELL_ROOT = original_render_shell

        self.assertEqual(errors, [])

    def test_shell_runtime_boundary_rejects_render_tab_leak(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="shell-runtime-",
            dir=REPO_ROOT,
        ) as tmp_name:
            tmp_root = Path(tmp_name)
            runtime_root = tmp_root / "view_ide" / "shell_runtime"
            render_shell = tmp_root / "view_render" / "shell"
            runtime_root.mkdir(parents=True)
            render_shell.mkdir(parents=True)
            (runtime_root / "shell_runtime_model.dart").write_text(
                "class ShellRuntimeModel { void route() { selectBottomTab(BottomSurfaceTab.debug); } }\n",
                encoding="utf-8",
            )
            (render_shell / "shell_model.dart").write_text(
                "enum BottomSurfaceTab { debug }\n"
                "class ShellModel extends ShellRuntimeModel {}\n",
                encoding="utf-8",
            )

            original_runtime = self.gate.VIEW_IDE_SHELL_RUNTIME_ROOT
            original_render_shell = self.gate.VIEW_RENDER_SHELL_ROOT
            self.gate.VIEW_IDE_SHELL_RUNTIME_ROOT = runtime_root
            self.gate.VIEW_RENDER_SHELL_ROOT = render_shell
            try:
                errors = self.gate.check_shell_runtime_boundary()
            finally:
                self.gate.VIEW_IDE_SHELL_RUNTIME_ROOT = original_runtime
                self.gate.VIEW_RENDER_SHELL_ROOT = original_render_shell

        self.assertTrue(
            any("shell runtime must not own render tab state" in error for error in errors),
            errors,
        )

    def test_view_ide_editor_accepts_submodule_facade_layout(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="editor-layout-",
            dir=REPO_ROOT,
        ) as tmp_name:
            editor_root = Path(tmp_name) / "editor"
            self._write_editor_layout(editor_root)

            original_editor_root = self.gate.VIEW_IDE_EDITOR_ROOT
            self.gate.VIEW_IDE_EDITOR_ROOT = editor_root
            try:
                errors = self.gate.check_view_ide_editor_layout()
            finally:
                self.gate.VIEW_IDE_EDITOR_ROOT = original_editor_root

        self.assertEqual(errors, [])

    def test_view_ide_editor_rejects_top_level_implementation(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="editor-layout-",
            dir=REPO_ROOT,
        ) as tmp_name:
            editor_root = Path(tmp_name) / "editor"
            self._write_editor_layout(editor_root)
            (editor_root / "editor_controller.dart").write_text(
                "class EditorSessionController {}\n",
                encoding="utf-8",
            )

            original_editor_root = self.gate.VIEW_IDE_EDITOR_ROOT
            self.gate.VIEW_IDE_EDITOR_ROOT = editor_root
            try:
                errors = self.gate.check_view_ide_editor_layout()
            finally:
                self.gate.VIEW_IDE_EDITOR_ROOT = original_editor_root

        self.assertTrue(
            any("top-level editor files must stay one-line facades" in error for error in errors),
            errors,
        )

    def test_view_ide_language_accepts_submodule_facade_layout(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="language-layout-",
            dir=REPO_ROOT,
        ) as tmp_name:
            language_root = Path(tmp_name) / "language"
            self._write_language_layout(language_root)

            original_language_root = self.gate.VIEW_IDE_LANGUAGE_ROOT
            self.gate.VIEW_IDE_LANGUAGE_ROOT = language_root
            try:
                errors = self.gate.check_view_ide_language_layout()
            finally:
                self.gate.VIEW_IDE_LANGUAGE_ROOT = original_language_root

        self.assertEqual(errors, [])

    def test_view_ide_language_rejects_top_level_implementation(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="language-layout-",
            dir=REPO_ROOT,
        ) as tmp_name:
            language_root = Path(tmp_name) / "language"
            self._write_language_layout(language_root)
            (language_root / "styio_syntax_highlighter.dart").write_text(
                "class StyioSyntaxHighlighter {}\n",
                encoding="utf-8",
            )

            original_language_root = self.gate.VIEW_IDE_LANGUAGE_ROOT
            self.gate.VIEW_IDE_LANGUAGE_ROOT = language_root
            try:
                errors = self.gate.check_view_ide_language_layout()
            finally:
                self.gate.VIEW_IDE_LANGUAGE_ROOT = original_language_root

        self.assertTrue(
            any("must stay one-line facades to language submodules" in error for error in errors),
            errors,
        )

    def _write_editor_layout(self, editor_root: Path) -> None:
        for submodule in self.gate.VIEW_IDE_EDITOR_SUBMODULES:
            (editor_root / submodule).mkdir(parents=True, exist_ok=True)
        for filename, target in self.gate.VIEW_IDE_EDITOR_FACADES.items():
            (editor_root / filename).write_text(
                f"export '{target}';\n",
                encoding="utf-8",
            )
            (editor_root / target).write_text(
                "class Placeholder {}\n",
                encoding="utf-8",
            )
        for submodule, barrel_name in (
            ("actions", "actions.dart"),
            ("controller", "controller.dart"),
            ("document", "document.dart"),
            ("render_plan", "render_plan.dart"),
            ("selection", "selection.dart"),
            ("transactions", "transactions.dart"),
        ):
            (editor_root / submodule / barrel_name).write_text(
                "export 'placeholder.dart';\n",
                encoding="utf-8",
            )
        (editor_root / "editor.dart").write_text(
            "\n".join(self.gate.VIEW_IDE_EDITOR_BARREL) + "\n",
            encoding="utf-8",
        )

    def _write_language_layout(self, language_root: Path) -> None:
        for submodule in self.gate.VIEW_IDE_LANGUAGE_SUBMODULES:
            (language_root / submodule).mkdir(parents=True, exist_ok=True)
        for filename, target in self.gate.VIEW_IDE_LANGUAGE_FACADES.items():
            (language_root / filename).write_text(
                f"export '{target}';\n",
                encoding="utf-8",
            )
            (language_root / target).write_text(
                "class Placeholder {}\n",
                encoding="utf-8",
            )
        (language_root / "language.dart").write_text(
            "\n".join(self.gate.VIEW_IDE_LANGUAGE_BARREL) + "\n",
            encoding="utf-8",
        )


if __name__ == "__main__":
    unittest.main()

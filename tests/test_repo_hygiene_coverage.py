#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import io
import subprocess
import sys
import tempfile
import unittest
from contextlib import ExitStack, redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[1]
GATE_PATH = REPO_ROOT / "scripts" / "repo-hygiene-gate.py"


def load_gate_module():
    spec = importlib.util.spec_from_file_location("repo_hygiene_gate_coverage", GATE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {GATE_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class RepoHygieneCoverageTest(unittest.TestCase):
    def setUp(self) -> None:
        self.gate = load_gate_module()

    def test_run_git_invokes_git_in_repository_root(self) -> None:
        completed = subprocess.CompletedProcess([], 0, stdout="ok\n", stderr="")
        with mock.patch.object(self.gate.subprocess, "run", return_value=completed) as run:
            self.assertIs(self.gate.run_git("status", "--short"), completed)

        run.assert_called_once_with(
            ["git", "status", "--short"],
            cwd=self.gate.REPO_ROOT,
            text=True,
            capture_output=True,
        )

    def test_git_file_helpers_parse_success_and_raise_on_failure(self) -> None:
        with mock.patch.object(self.gate, "run_git") as run_git:
            run_git.return_value = subprocess.CompletedProcess([], 0, stdout="a.py\0b.txt\0", stderr="")
            self.assertEqual(self.gate.tracked_files(), ["a.py", "b.txt"])

            run_git.return_value = subprocess.CompletedProcess([], 1, stdout="", stderr="bad ls")
            with self.assertRaisesRegex(RuntimeError, "bad ls"):
                self.gate.tracked_files()

            run_git.return_value = subprocess.CompletedProcess([], 0, stdout="a.py\nb.txt\n", stderr="")
            self.assertEqual(self.gate.staged_files(), ["a.py", "b.txt"])

            run_git.return_value = subprocess.CompletedProcess([], 1, stdout="", stderr="bad diff")
            with self.assertRaisesRegex(RuntimeError, "bad diff"):
                self.gate.staged_files()

            run_git.return_value = subprocess.CompletedProcess([], 0, stdout="origin/main\n", stderr="")
            self.assertEqual(self.gate.default_push_range(), "@{upstream}..HEAD")

            run_git.return_value = subprocess.CompletedProcess([], 1, stdout="", stderr="no upstream")
            self.assertEqual(self.gate.default_push_range(), "HEAD")

    def test_path_binary_and_worktree_checks_cover_all_policy_branches(self) -> None:
        with tempfile.TemporaryDirectory(prefix="repo-hygiene-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            original_root = self.gate.REPO_ROOT
            self.gate.REPO_ROOT = root
            try:
                (root / "ok").mkdir()
                (root / "ok/empty.txt").write_bytes(b"")
                (root / "ok/nul.txt").write_bytes(b"a\0b")
                (root / "ok/invalid.txt").write_bytes(b"\xff")
                (root / "ok/control.txt").write_bytes(b"hello\x01")
                (root / "ok/large.txt").write_text("12345678", encoding="utf-8")
                (root / "build").mkdir()
                (root / "build/generated.txt").write_text("generated\n", encoding="utf-8")
                (root / "docs/audit/defects").mkdir(parents=True)
                (root / "docs/audit/defects/open.md").write_text("defect\n", encoding="utf-8")
                (root / "docs/assets").mkdir(parents=True)
                (root / "docs/assets/logo.png").write_bytes(b"\x89PNG\0")
                (root / "bin.zip").write_text("zip\n", encoding="utf-8")

                self.assertTrue(self.gate.has_forbidden_path_part("build/generated.txt"))
                self.assertTrue(self.gate.has_forbidden_file_suffix("bin.zip"))
                self.assertTrue(self.gate.is_allowed_binary("docs/assets/logo.png"))
                self.assertFalse(self.gate.is_binary_file("ok/empty.txt"))
                self.assertTrue(self.gate.is_binary_file("ok/nul.txt"))
                self.assertTrue(self.gate.is_binary_file("ok/invalid.txt"))
                self.assertTrue(self.gate.is_binary_file("ok/control.txt"))

                errors = self.gate.check_worktree_files(
                    [
                        "missing.txt",
                        "docs/audit/defects/open.md",
                        "build/generated.txt",
                        "bin.zip",
                        "ok/large.txt",
                        "ok/nul.txt",
                        "docs/assets/logo.png",
                    ],
                    max_file_bytes=7,
                )
            finally:
                self.gate.REPO_ROOT = original_root

        joined = "\n".join(errors)
        self.assertIn("active audit defect records must stay untracked", joined)
        self.assertIn("contains forbidden generated/dependency path part", joined)
        self.assertIn("uses forbidden generated/binary suffix", joined)
        self.assertIn("file size 8 bytes exceeds soft limit 7 bytes", joined)
        self.assertIn("unexpected binary file", joined)
        self.assertNotIn("docs/assets/logo.png", joined)

    def test_gitignore_doc_and_project_branding_missing_paths_are_reported(self) -> None:
        with tempfile.TemporaryDirectory(prefix="repo-hygiene-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            original_root = self.gate.REPO_ROOT
            original_doc_refs = self.gate.REQUIRED_DOC_REFERENCES
            original_headings = self.gate.REQUIRED_PROJECT_BRAND_HEADINGS
            original_metadata = self.gate.REQUIRED_PROJECT_BRAND_METADATA
            self.gate.REPO_ROOT = root
            self.gate.REQUIRED_DOC_REFERENCES = {Path("docs/README.md"): ("scripts/docs-index.py",)}
            self.gate.REQUIRED_PROJECT_BRAND_HEADINGS = {Path("README.md"): "# Vityo"}
            self.gate.REQUIRED_PROJECT_BRAND_METADATA = {Path("pubspec.yaml"): ("name: vityo_app", "description: Vityo")}
            try:
                self.assertEqual(self.gate.check_gitignore(), [".gitignore is missing"])
                (root / ".gitignore").write_text("node_modules/\n", encoding="utf-8")
                self.assertTrue(self.gate.check_gitignore())
                self.assertEqual(
                    self.gate.check_doc_references(),
                    ["required documentation file is missing: docs/README.md"],
                )
                (root / "docs").mkdir()
                (root / "docs/README.md").write_text("no tool docs\n", encoding="utf-8")
                self.assertEqual(
                    self.gate.check_doc_references(),
                    ["docs/README.md must document scripts/docs-index.py"],
                )
                self.assertEqual(
                    self.gate.check_project_branding(),
                    [
                        "required project branding file is missing: README.md",
                        "required project metadata file is missing: pubspec.yaml",
                    ],
                )
                (root / "README.md").write_text("# Wrong\n", encoding="utf-8")
                (root / "pubspec.yaml").write_text("name: other\n", encoding="utf-8")
                branding_errors = self.gate.check_project_branding()
            finally:
                self.gate.REPO_ROOT = original_root
                self.gate.REQUIRED_DOC_REFERENCES = original_doc_refs
                self.gate.REQUIRED_PROJECT_BRAND_HEADINGS = original_headings
                self.gate.REQUIRED_PROJECT_BRAND_METADATA = original_metadata

        joined = "\n".join(branding_errors)
        self.assertIn("README.md must use project heading: # Vityo", joined)
        self.assertIn("pubspec.yaml must use project metadata marker: name: vityo_app", joined)
        self.assertIn("pubspec.yaml must use project metadata marker: description: Vityo", joined)

    def test_view_and_facade_checks_report_missing_and_invalid_layouts(self) -> None:
        with tempfile.TemporaryDirectory(prefix="repo-hygiene-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            original_root = self.gate.REPO_ROOT
            original_view_ide = self.gate.VIEW_IDE_ROOT
            original_view_render = self.gate.VIEW_RENDER_ROOT
            original_command = self.gate.LEGACY_COMMANDS_ROOT
            original_language = self.gate.VIEW_IDE_LANGUAGE_ROOT
            original_editor = self.gate.VIEW_IDE_EDITOR_ROOT
            self.gate.REPO_ROOT = root
            self.gate.VIEW_IDE_ROOT = root / "view_ide"
            self.gate.VIEW_RENDER_ROOT = root / "view_render"
            self.gate.LEGACY_COMMANDS_ROOT = root / "legacy_commands"
            self.gate.VIEW_IDE_LANGUAGE_ROOT = root / "view_ide/language"
            self.gate.VIEW_IDE_EDITOR_ROOT = root / "view_ide/editor"
            try:
                boundary_errors = self.gate.check_view_boundary_imports()
                self.assertTrue(any("required view boundary directory is missing" in error for error in boundary_errors))

                command_errors = self.gate.check_legacy_command_adapter()
                self.assertEqual(command_errors, ["required legacy command adapter is missing: legacy_commands/app_commands.dart"])

                (root / "legacy_commands").mkdir()
                (root / "legacy_commands/app_commands.dart").write_text("export only;\n", encoding="utf-8")
                command_errors = self.gate.check_legacy_command_adapter()

                (root / "view_ide/language").mkdir(parents=True)
                (root / "view_ide/language/language.dart").write_text("export 'wrong.dart';\n", encoding="utf-8")
                (root / "view_ide/language/extra.dart").write_text("class Extra {}\n", encoding="utf-8")
                language_errors = self.gate.check_view_ide_language_layout()

                (root / "view_ide/editor").mkdir(parents=True)
                (root / "view_ide/editor/editor.dart").write_text("export 'wrong.dart';\n", encoding="utf-8")
                (root / "view_ide/editor/extra.dart").write_text("class Extra {}\n", encoding="utf-8")
                editor_errors = self.gate.check_view_ide_editor_layout()
            finally:
                self.gate.REPO_ROOT = original_root
                self.gate.VIEW_IDE_ROOT = original_view_ide
                self.gate.VIEW_RENDER_ROOT = original_view_render
                self.gate.LEGACY_COMMANDS_ROOT = original_command
                self.gate.VIEW_IDE_LANGUAGE_ROOT = original_language
                self.gate.VIEW_IDE_EDITOR_ROOT = original_editor

        self.assertTrue(any("must preserve command render adapter marker" in error for error in command_errors))
        self.assertTrue(any("required language submodule is missing" in error for error in language_errors))
        self.assertTrue(any("language.dart must stay the canonical language barrel" in error for error in language_errors))
        self.assertTrue(any("top-level view_ide/language files must be registered facades" in error for error in language_errors))
        self.assertTrue(any("required editor submodule is missing" in error for error in editor_errors))
        self.assertTrue(any("editor.dart must stay the canonical editor barrel" in error for error in editor_errors))
        self.assertTrue(any("top-level view_ide/editor files must be registered facades" in error for error in editor_errors))

    def test_legacy_facade_helpers_cover_missing_invalid_and_missing_target(self) -> None:
        with tempfile.TemporaryDirectory(prefix="repo-hygiene-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            original_root = self.gate.REPO_ROOT
            self.gate.REPO_ROOT = root
            try:
                missing = self.gate.check_legacy_view_ide_facades(
                    legacy_root=root / "legacy",
                    migrated_root=root / "migrated",
                    legacy_name="sample",
                )
                (root / "legacy").mkdir()
                (root / "migrated").mkdir()
                (root / "legacy/a.dart").write_text("class A {}\n", encoding="utf-8")
                invalid = self.gate.check_legacy_view_ide_facades(
                    legacy_root=root / "legacy",
                    migrated_root=root / "migrated",
                    legacy_name="sample",
                )
                (root / "legacy/a.dart").write_text("export '../view_ide/sample/a.dart';\n", encoding="utf-8")
                missing_target = self.gate.check_legacy_view_ide_facades(
                    legacy_root=root / "legacy",
                    migrated_root=root / "migrated",
                    legacy_name="sample",
                )
                (root / "migrated/a.dart").write_text("class A {}\n", encoding="utf-8")
                clean = self.gate.check_legacy_view_ide_facades(
                    legacy_root=root / "legacy",
                    migrated_root=root / "migrated",
                    legacy_name="sample",
                )
            finally:
                self.gate.REPO_ROOT = original_root

        self.assertIn("required legacy sample facade directory is missing", missing[0])
        self.assertIn("must stay one-line facades", invalid[0])
        self.assertIn("facade target is missing", missing_target[0])
        self.assertEqual(clean, [])

    def test_push_history_report_and_main_modes(self) -> None:
        rev_list = subprocess.CompletedProcess([], 0, stdout="oid1 path\n", stderr="")
        batch = subprocess.CompletedProcess(
            [],
            0,
            stdout=(
                "tree oid0 0 ignored\n"
                "blob oid1 not-a-size docs/audit/defects/open.md\n"
                "blob oid2 25 build/generated.txt\n"
                "blob oid3 30 artifact.zip\n"
                "blob oid4 50 src/large.txt\n"
                "malformed\n"
            ),
            stderr="",
        )
        with mock.patch.object(self.gate.subprocess, "run", side_effect=[rev_list, batch]):
            errors = self.gate.check_push_history("HEAD~1..HEAD", max_file_bytes=40)
        joined = "\n".join(errors)
        self.assertIn("active audit defect records must stay untracked", joined)
        self.assertIn("forbidden generated/dependency path part", joined)
        self.assertIn("forbidden generated/binary suffix", joined)
        self.assertIn("blob size 50 bytes", joined)

        with mock.patch.object(self.gate.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, stdout="", stderr="")):
            self.assertEqual(self.gate.check_push_history("HEAD", max_file_bytes=40), [])

        stdout = io.StringIO()
        with redirect_stdout(stdout):
            self.assertEqual(self.gate.print_report("tracked", []), 0)
        self.assertIn("[repo-hygiene] tracked: OK", stdout.getvalue())

        stderr = io.StringIO()
        with redirect_stderr(stderr):
            self.assertEqual(self.gate.print_report("tracked", ["b", "a", "a"]), 1)
        self.assertIn("  - a", stderr.getvalue())
        self.assertIn("  - b", stderr.getvalue())

        tracked_check_names = (
            "check_gitignore",
            "check_doc_references",
            "check_project_branding",
            "check_view_boundary_imports",
            "check_legacy_backend_toolchain_facades",
            "check_legacy_command_adapter",
            "check_legacy_editor_facades",
            "check_legacy_language_facades",
            "check_legacy_workspace_facades",
            "check_legacy_module_host_facades",
            "check_legacy_runtime_facades",
            "check_legacy_render_shell_facades",
            "check_legacy_view_render_facades",
            "check_shell_runtime_boundary",
            "check_legacy_agent_facades",
            "check_legacy_platform_facades",
            "check_view_ide_language_layout",
            "check_view_ide_editor_layout",
        )
        with mock.patch.object(sys, "argv", ["repo-hygiene-gate.py", "--mode", "tracked"]):
            with ExitStack() as stack:
                for name in tracked_check_names:
                    stack.enter_context(mock.patch.object(self.gate, name, return_value=[]))
                stack.enter_context(mock.patch.object(self.gate, "tracked_files", return_value=[]))
                stdout = io.StringIO()
                with redirect_stdout(stdout):
                    code = self.gate.main()

        self.assertEqual(code, 0)
        self.assertIn("nothing to check", stdout.getvalue())

    def test_legacy_facade_wrappers_delegate_to_shared_checker(self) -> None:
        wrappers = (
            (
                self.gate.check_legacy_editor_facades,
                self.gate.LEGACY_EDITOR_ROOT,
                self.gate.VIEW_IDE_EDITOR_ROOT,
                "editor",
                self.gate.LEGACY_EDITOR_FACADE_FILES,
                None,
            ),
            (
                self.gate.check_legacy_workspace_facades,
                self.gate.LEGACY_WORKSPACE_ROOT,
                self.gate.VIEW_IDE_WORKSPACE_ROOT,
                "workspace",
                self.gate.LEGACY_WORKSPACE_FACADE_FILES,
                "../../view_ide/workspace",
            ),
            (
                self.gate.check_legacy_module_host_facades,
                self.gate.LEGACY_MODULE_HOST_ROOT,
                self.gate.VIEW_IDE_MODULE_HOST_ROOT,
                "module_host",
                None,
                None,
            ),
            (
                self.gate.check_legacy_runtime_facades,
                self.gate.LEGACY_RUNTIME_ROOT,
                self.gate.VIEW_IDE_RUNTIME_ROOT,
                "runtime",
                self.gate.LEGACY_RUNTIME_FACADE_FILES,
                None,
            ),
            (
                self.gate.check_legacy_agent_facades,
                self.gate.LEGACY_AGENT_ROOT,
                self.gate.VIEW_IDE_AGENT_ROOT,
                "agent",
                self.gate.LEGACY_AGENT_FACADE_FILES,
                None,
            ),
            (
                self.gate.check_legacy_platform_facades,
                self.gate.LEGACY_PLATFORM_ROOT,
                self.gate.VIEW_IDE_PLATFORM_ROOT,
                "platform",
                self.gate.LEGACY_PLATFORM_FACADE_FILES,
                None,
            ),
        )

        for wrapper, legacy_root, migrated_root, legacy_name, file_names, export_prefix in wrappers:
            with self.subTest(legacy_name=legacy_name):
                with mock.patch.object(
                    self.gate,
                    "check_legacy_view_ide_facades",
                    return_value=[legacy_name],
                ) as shared:
                    self.assertEqual(wrapper(), [legacy_name])

                kwargs = shared.call_args.kwargs
                self.assertEqual(kwargs["legacy_root"], legacy_root)
                self.assertEqual(kwargs["migrated_root"], migrated_root)
                self.assertEqual(kwargs["legacy_name"], legacy_name)
                if file_names is None:
                    self.assertNotIn("file_names", kwargs)
                else:
                    self.assertEqual(kwargs["file_names"], file_names)
                if export_prefix is None:
                    self.assertNotIn("export_prefix", kwargs)
                else:
                    self.assertEqual(kwargs["export_prefix"], export_prefix)

    def test_render_facade_checks_report_missing_files_and_targets(self) -> None:
        with tempfile.TemporaryDirectory(prefix="repo-hygiene-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            original_values = {
                "REPO_ROOT": self.gate.REPO_ROOT,
                "LEGACY_APP_LAYOUT_ROOT": self.gate.LEGACY_APP_LAYOUT_ROOT,
                "LEGACY_WORKSPACE_ROOT": self.gate.LEGACY_WORKSPACE_ROOT,
                "LEGACY_EDITOR_ROOT": self.gate.LEGACY_EDITOR_ROOT,
                "LEGACY_AGENT_ROOT": self.gate.LEGACY_AGENT_ROOT,
                "LEGACY_RUNTIME_ROOT": self.gate.LEGACY_RUNTIME_ROOT,
                "LEGACY_THEME_ROOT": self.gate.LEGACY_THEME_ROOT,
                "LEGACY_PLATFORM_ROOT": self.gate.LEGACY_PLATFORM_ROOT,
                "VIEW_RENDER_SHELL_ROOT": self.gate.VIEW_RENDER_SHELL_ROOT,
                "VIEW_RENDER_EDITOR_ROOT": self.gate.VIEW_RENDER_EDITOR_ROOT,
                "VIEW_RENDER_AGENT_ROOT": self.gate.VIEW_RENDER_AGENT_ROOT,
                "VIEW_RENDER_RUNTIME_ROOT": self.gate.VIEW_RENDER_RUNTIME_ROOT,
                "VIEW_RENDER_THEME_ROOT": self.gate.VIEW_RENDER_THEME_ROOT,
                "VIEW_RENDER_PLATFORM_ROOT": self.gate.VIEW_RENDER_PLATFORM_ROOT,
            }
            self.gate.REPO_ROOT = root
            self.gate.LEGACY_APP_LAYOUT_ROOT = root / "legacy/layout"
            self.gate.LEGACY_WORKSPACE_ROOT = root / "legacy/workspace"
            self.gate.LEGACY_EDITOR_ROOT = root / "legacy/editor"
            self.gate.LEGACY_AGENT_ROOT = root / "legacy/agent"
            self.gate.LEGACY_RUNTIME_ROOT = root / "legacy/runtime"
            self.gate.LEGACY_THEME_ROOT = root / "legacy/theme"
            self.gate.LEGACY_PLATFORM_ROOT = root / "legacy/platform"
            self.gate.VIEW_RENDER_SHELL_ROOT = root / "render/shell"
            self.gate.VIEW_RENDER_EDITOR_ROOT = root / "render/editor"
            self.gate.VIEW_RENDER_AGENT_ROOT = root / "render/agent"
            self.gate.VIEW_RENDER_RUNTIME_ROOT = root / "render/runtime"
            self.gate.VIEW_RENDER_THEME_ROOT = root / "render/theme"
            self.gate.VIEW_RENDER_PLATFORM_ROOT = root / "render/platform"
            try:
                shell_missing = self.gate.check_legacy_render_shell_facades()

                self.gate.LEGACY_WORKSPACE_ROOT.mkdir(parents=True)
                self.gate.LEGACY_APP_LAYOUT_ROOT.mkdir(parents=True)
                (self.gate.LEGACY_WORKSPACE_ROOT / "shell_model.dart").write_text(
                    "export '../../view_render/shell/shell_model.dart';\n",
                    encoding="utf-8",
                )
                (self.gate.LEGACY_WORKSPACE_ROOT / "shell_scope.dart").write_text(
                    "export '../../view_render/shell/shell_scope.dart';\n",
                    encoding="utf-8",
                )
                (self.gate.LEGACY_APP_LAYOUT_ROOT / "vityo_shell_scaffold.dart").write_text(
                    "export '../../view_render/shell/vityo_shell_scaffold.dart';\n",
                    encoding="utf-8",
                )
                shell_missing_targets = self.gate.check_legacy_render_shell_facades()

                view_missing = self.gate.check_legacy_view_render_facades()

                for directory, name, export_target in (
                    (self.gate.LEGACY_AGENT_ROOT, "agent_surface.dart", "../view_render/agent/agent_surface.dart"),
                    (self.gate.LEGACY_EDITOR_ROOT, "editor_surface.dart", "../view_render/editor/editor_surface.dart"),
                    (self.gate.LEGACY_RUNTIME_ROOT, "runtime_surface.dart", "../view_render/runtime/runtime_surface.dart"),
                    (self.gate.LEGACY_RUNTIME_ROOT, "debug_console_surface.dart", "../view_render/runtime/debug_console_surface.dart"),
                    (self.gate.LEGACY_THEME_ROOT, "vityo_theme.dart", "../view_render/theme/vityo_theme.dart"),
                    (self.gate.LEGACY_PLATFORM_ROOT, "viewport_profile.dart", "../view_render/platform/viewport_profile.dart"),
                ):
                    directory.mkdir(parents=True, exist_ok=True)
                    (directory / name).write_text(f"export '{export_target}';\n", encoding="utf-8")
                view_missing_targets = self.gate.check_legacy_view_render_facades()
            finally:
                for name, value in original_values.items():
                    setattr(self.gate, name, value)

        self.assertTrue(any("required legacy render shell facade is missing" in error for error in shell_missing))
        self.assertTrue(any("facade target is missing" in error for error in shell_missing_targets))
        self.assertTrue(any("required legacy view_render facade is missing" in error for error in view_missing))
        self.assertTrue(any("facade target is missing" in error for error in view_missing_targets))

    def test_shell_runtime_and_layout_early_return_paths(self) -> None:
        with tempfile.TemporaryDirectory(prefix="repo-hygiene-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            original_values = {
                "REPO_ROOT": self.gate.REPO_ROOT,
                "VIEW_IDE_SHELL_RUNTIME_ROOT": self.gate.VIEW_IDE_SHELL_RUNTIME_ROOT,
                "VIEW_RENDER_SHELL_ROOT": self.gate.VIEW_RENDER_SHELL_ROOT,
                "VIEW_IDE_LANGUAGE_ROOT": self.gate.VIEW_IDE_LANGUAGE_ROOT,
                "VIEW_IDE_EDITOR_ROOT": self.gate.VIEW_IDE_EDITOR_ROOT,
            }
            self.gate.REPO_ROOT = root
            self.gate.VIEW_IDE_SHELL_RUNTIME_ROOT = root / "runtime"
            self.gate.VIEW_RENDER_SHELL_ROOT = root / "render"
            self.gate.VIEW_IDE_LANGUAGE_ROOT = root / "missing-language"
            self.gate.VIEW_IDE_EDITOR_ROOT = root / "missing-editor"
            try:
                self.assertEqual(self.gate.check_view_ide_language_layout(), [])
                self.assertEqual(self.gate.check_view_ide_editor_layout(), [])

                self.gate.VIEW_IDE_SHELL_RUNTIME_ROOT.mkdir()
                self.gate.VIEW_RENDER_SHELL_ROOT.mkdir()
                (self.gate.VIEW_IDE_SHELL_RUNTIME_ROOT / "shell_runtime_model.dart").write_text(
                    "enum BottomSurfaceTab { terminal }\n",
                    encoding="utf-8",
                )
                (self.gate.VIEW_RENDER_SHELL_ROOT / "shell_model.dart").write_text(
                    "class ShellModel {}\n",
                    encoding="utf-8",
                )
                errors = self.gate.check_shell_runtime_boundary()
            finally:
                for name, value in original_values.items():
                    setattr(self.gate, name, value)

        joined = "\n".join(errors)
        self.assertIn("shell runtime must not own render tab state marker", joined)
        self.assertIn("must preserve render shell marker: enum BottomSurfaceTab", joined)
        self.assertIn("must preserve render shell marker: class ShellModel extends ShellRuntimeModel", joined)

    def test_legacy_facade_helper_handles_missing_migrated_root_and_named_file(self) -> None:
        with tempfile.TemporaryDirectory(prefix="repo-hygiene-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            original_root = self.gate.REPO_ROOT
            self.gate.REPO_ROOT = root
            try:
                (root / "legacy").mkdir()
                self.assertEqual(
                    self.gate.check_legacy_view_ide_facades(
                        legacy_root=root / "legacy",
                        migrated_root=root / "missing-migrated",
                        legacy_name="sample",
                    ),
                    [],
                )
                (root / "migrated").mkdir()
                errors = self.gate.check_legacy_view_ide_facades(
                    legacy_root=root / "legacy",
                    migrated_root=root / "migrated",
                    legacy_name="sample",
                    file_names=("missing.dart",),
                )
            finally:
                self.gate.REPO_ROOT = original_root

        self.assertIn("required legacy sample facade is missing", errors[0])

    def test_main_push_and_empty_policy_error_paths(self) -> None:
        check_names = (
            "check_gitignore",
            "check_doc_references",
            "check_project_branding",
            "check_view_boundary_imports",
            "check_legacy_backend_toolchain_facades",
            "check_legacy_command_adapter",
            "check_legacy_editor_facades",
            "check_legacy_language_facades",
            "check_legacy_workspace_facades",
            "check_legacy_module_host_facades",
            "check_legacy_runtime_facades",
            "check_legacy_render_shell_facades",
            "check_legacy_view_render_facades",
            "check_shell_runtime_boundary",
            "check_legacy_agent_facades",
            "check_legacy_platform_facades",
            "check_view_ide_language_layout",
            "check_view_ide_editor_layout",
        )

        with mock.patch.object(sys, "argv", ["repo-hygiene-gate.py", "--mode", "push"]):
            with ExitStack() as stack:
                for name in check_names:
                    stack.enter_context(mock.patch.object(self.gate, name, return_value=[]))
                stack.enter_context(mock.patch.object(self.gate, "default_push_range", return_value="main..HEAD"))
                push = stack.enter_context(mock.patch.object(self.gate, "check_push_history", return_value=["bad history"]))
                report = stack.enter_context(mock.patch.object(self.gate, "print_report", return_value=1))
                self.assertEqual(self.gate.main(), 1)
        push.assert_called_once_with("main..HEAD", self.gate.DEFAULT_MAX_FILE_BYTES)
        report.assert_called_once_with("push range main..HEAD", ["bad history"])

        with mock.patch.object(sys, "argv", ["repo-hygiene-gate.py", "--mode", "tracked"]):
            with ExitStack() as stack:
                stack.enter_context(mock.patch.object(self.gate, check_names[0], return_value=["policy error"]))
                for name in check_names[1:]:
                    stack.enter_context(mock.patch.object(self.gate, name, return_value=[]))
                stack.enter_context(mock.patch.object(self.gate, "tracked_files", return_value=[]))
                report = stack.enter_context(mock.patch.object(self.gate, "print_report", return_value=1))
                self.assertEqual(self.gate.main(), 1)
        report.assert_called_once_with("tracked policy", ["policy error"])


if __name__ == "__main__":
    unittest.main()

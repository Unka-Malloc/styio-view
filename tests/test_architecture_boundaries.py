#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import io
import sys
import tempfile
import unittest
from contextlib import contextmanager, redirect_stderr
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
ARCHITECTURE_GATE_PATH = REPO_ROOT / "scripts" / "check_architecture_boundaries.py"
FACADE_GATE_PATH = REPO_ROOT / "scripts" / "check_compat_facades.py"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


@contextmanager
def patched_architecture_roots(gate, tmp_root: Path):
    app_lib_root = tmp_root / "frontend" / "vityo_app" / "lib"
    src_root = app_lib_root / "src"
    originals = (
        gate.APP_LIB_ROOT,
        gate.SRC_ROOT,
        gate.VIEW_IDE_ROOT,
        gate.VIEW_RENDER_ROOT,
        gate.LEGACY_COMPAT_ROOTS,
        gate.INTEGRATION_ROOT,
    )
    gate.APP_LIB_ROOT = app_lib_root
    gate.SRC_ROOT = src_root
    gate.VIEW_IDE_ROOT = src_root / "view_ide"
    gate.VIEW_RENDER_ROOT = src_root / "view_render"
    gate.LEGACY_COMPAT_ROOTS = (
        src_root / "backend_toolchain",
        src_root / "editor",
        src_root / "language",
    )
    gate.INTEGRATION_ROOT = src_root / "integration"
    try:
        yield src_root
    finally:
        (
            gate.APP_LIB_ROOT,
            gate.SRC_ROOT,
            gate.VIEW_IDE_ROOT,
            gate.VIEW_RENDER_ROOT,
            gate.LEGACY_COMPAT_ROOTS,
            gate.INTEGRATION_ROOT,
        ) = originals


class ArchitectureBoundaryGateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.gate = load_module("check_architecture_boundaries", ARCHITECTURE_GATE_PATH)

    def test_current_tree_satisfies_architecture_boundaries(self) -> None:
        self.assertEqual(self.gate.check_architecture_boundaries(), [])

    def test_view_ide_rejects_relative_view_render_dependency(self) -> None:
        with tempfile.TemporaryDirectory(prefix="arch-boundary-") as tmp_name:
            with patched_architecture_roots(self.gate, Path(tmp_name)) as src_root:
                write(
                    src_root / "view_ide" / "sample.dart",
                    "import '../view_render/view_render.dart';\n",
                )
                write(
                    src_root / "view_render" / "view_render.dart",
                    "class ViewRender {}\n",
                )

                errors = self.gate.check_view_ide_no_view_render_dependency()

        self.assertTrue(
            any("view_ide must not import or export view_render" in error for error in errors),
            errors,
        )

    def test_view_ide_rejects_package_view_render_dependency(self) -> None:
        with tempfile.TemporaryDirectory(prefix="arch-boundary-") as tmp_name:
            with patched_architecture_roots(self.gate, Path(tmp_name)) as src_root:
                write(
                    src_root / "view_ide" / "sample.dart",
                    "import 'package:vityo_app/src/view_render/view_render.dart';\n",
                )
                write(
                    src_root / "view_render" / "view_render.dart",
                    "class ViewRender {}\n",
                )

                errors = self.gate.check_view_ide_no_view_render_dependency()

        self.assertTrue(
            any("view_ide must not import or export view_render" in error for error in errors),
            errors,
        )

    def test_view_render_accepts_registered_view_ide_contract_surface(self) -> None:
        with tempfile.TemporaryDirectory(prefix="arch-boundary-") as tmp_name:
            with patched_architecture_roots(self.gate, Path(tmp_name)) as src_root:
                write(
                    src_root / "view_render" / "runtime" / "surface.dart",
                    "import '../../view_ide/runtime/runtime_replay_summary.dart';\n",
                )
                write(
                    src_root / "view_ide" / "runtime" / "runtime_replay_summary.dart",
                    "class RuntimeReplaySummary {}\n",
                )

                errors = self.gate.check_view_render_registered_view_ide_contracts()

        self.assertEqual(errors, [])

    def test_view_render_rejects_unregistered_view_ide_implementation_import(self) -> None:
        with tempfile.TemporaryDirectory(prefix="arch-boundary-") as tmp_name:
            with patched_architecture_roots(self.gate, Path(tmp_name)) as src_root:
                write(
                    src_root / "view_render" / "agent" / "surface.dart",
                    "import '../../view_ide/agent/agent_provider_registry.dart';\n",
                )
                write(
                    src_root / "view_ide" / "agent" / "agent_provider_registry.dart",
                    "class AgentProviderRegistry {}\n",
                )

                errors = self.gate.check_view_render_registered_view_ide_contracts()

        self.assertTrue(
            any("registered view_ide contract surfaces" in error for error in errors),
            errors,
        )

    def test_view_render_rejects_legacy_backend_toolchain_import(self) -> None:
        with tempfile.TemporaryDirectory(prefix="arch-boundary-") as tmp_name:
            with patched_architecture_roots(self.gate, Path(tmp_name)) as src_root:
                write(
                    src_root / "view_render" / "runtime" / "surface.dart",
                    "import '../../backend_toolchain/execution_adapter.dart';\n",
                )
                write(
                    src_root / "backend_toolchain" / "execution_adapter.dart",
                    "export '../view_ide/backend_toolchain/execution_adapter.dart';\n",
                )

                errors = self.gate.check_view_render_no_legacy_compat_imports()

        self.assertTrue(
            any("legacy compatibility facade roots" in error for error in errors),
            errors,
        )

    def test_text_report_failure_returns_nonzero(self) -> None:
        stderr = io.StringIO()
        with redirect_stderr(stderr):
            code = self.gate.print_text_report(["sample.dart:1: violation"])

        self.assertEqual(code, 1)
        self.assertIn("[architecture-boundaries] FAILED", stderr.getvalue())


class CompatFacadeGateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.gate = load_module("check_compat_facades", FACADE_GATE_PATH)

    def test_current_tree_satisfies_compat_facades(self) -> None:
        self.assertEqual(self.gate.check_compat_facades(), [])

    def test_legacy_editor_accepts_view_ide_and_view_render_facades(self) -> None:
        with tempfile.TemporaryDirectory(prefix="compat-facade-") as tmp_name:
            root = Path(tmp_name)
            legacy = root / "src" / "editor"
            write(
                legacy / "editor_controller.dart",
                "export '../view_ide/editor/editor_controller.dart';\n",
            )
            write(
                legacy / "editor_surface.dart",
                "export '../view_render/editor/editor_surface.dart';\n",
            )
            write(
                root / "src" / "view_ide" / "editor" / "editor_controller.dart",
                "class EditorController {}\n",
            )
            write(
                root / "src" / "view_render" / "editor" / "editor_surface.dart",
                "class EditorSurface {}\n",
            )
            rule = self.gate.FacadeRule(
                name="editor",
                root=legacy,
                allowed_target_prefixes=("view_ide/editor/", "view_render/editor/"),
            )
            original_src_root = self.gate.SRC_ROOT
            self.gate.SRC_ROOT = root / "src"
            try:
                errors = self.gate.check_compat_facades((rule,))
            finally:
                self.gate.SRC_ROOT = original_src_root

        self.assertEqual(errors, [])

    def test_legacy_language_rejects_implementation_body(self) -> None:
        with tempfile.TemporaryDirectory(prefix="compat-facade-") as tmp_name:
            root = Path(tmp_name)
            legacy = root / "src" / "language"
            write(
                legacy / "styio_language_service.dart",
                "class StyioLanguageService {}\n",
            )
            rule = self.gate.FacadeRule(
                name="language",
                root=legacy,
                allowed_target_prefixes=("view_ide/language/",),
            )
            original_src_root = self.gate.SRC_ROOT
            self.gate.SRC_ROOT = root / "src"
            try:
                errors = self.gate.check_compat_facades((rule,))
            finally:
                self.gate.SRC_ROOT = original_src_root

        self.assertTrue(any("single export" in error for error in errors), errors)

    def test_legacy_backend_rejects_wrong_target_root(self) -> None:
        with tempfile.TemporaryDirectory(prefix="compat-facade-") as tmp_name:
            root = Path(tmp_name)
            legacy = root / "src" / "backend_toolchain"
            write(
                legacy / "execution_adapter.dart",
                "export '../runtime/execution_adapter.dart';\n",
            )
            write(
                root / "src" / "runtime" / "execution_adapter.dart",
                "class ExecutionAdapter {}\n",
            )
            rule = self.gate.FacadeRule(
                name="backend_toolchain",
                root=legacy,
                allowed_target_prefixes=("view_ide/backend_toolchain/",),
            )
            original_src_root = self.gate.SRC_ROOT
            self.gate.SRC_ROOT = root / "src"
            try:
                errors = self.gate.check_compat_facades((rule,))
            finally:
                self.gate.SRC_ROOT = original_src_root

        self.assertTrue(any("facade target must resolve under" in error for error in errors), errors)

    def test_text_report_failure_returns_nonzero(self) -> None:
        stderr = io.StringIO()
        with redirect_stderr(stderr):
            code = self.gate.print_text_report(["legacy.dart: bad facade"])

        self.assertEqual(code, 1)
        self.assertIn("[compat-facades] FAILED", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()

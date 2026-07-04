#!/usr/bin/env python3
"""Tests for the Linux packaging gate."""

from __future__ import annotations

import importlib.util
import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[1]
GATE_PATH = REPO_ROOT / "scripts" / "check-linux-packaging-gate.py"


def load_gate_module():
    spec = importlib.util.spec_from_file_location(
        "check_linux_packaging_gate",
        GATE_PATH,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {GATE_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class LinuxPackagingGateTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.gate = load_gate_module()

    def _write(self, root: Path, relative_path: str, text: str) -> None:
        path = root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def _write_valid_packaging_tree(self, root: Path) -> None:
        self._write(
            root,
            "packaging/linux/io.vityo.desktop",
            "\n".join(
                [
                    "[Desktop Entry]",
                    "Name=Vityo",
                    "Type=Application",
                    "Exec=vityo",
                    "Icon=io.vityo",
                    "Categories=Development;",
                ]
            ),
        )
        self._write(
            root,
            "packaging/linux/io.vityo.metainfo.xml",
            """<?xml version="1.0" encoding="UTF-8"?>
<component>
  <id>io.vityo</id>
  <name>Vityo</name>
  <summary>IDE shell</summary>
  <description><p>Vityo desktop package.</p></description>
</component>
""",
        )
        self._write(
            root,
            "packaging/linux/DEBIAN/control",
            "\n".join(
                [
                    "Package: vityo",
                    "Version: 0.1.0",
                    "Section: devel",
                    "Architecture: amd64",
                    "Description: Vityo IDE shell",
                ]
            ),
        )
        self._write(root, "packaging/linux/README.md", "# Linux packaging\n")

    def test_run_checks_passes_for_valid_tree(self) -> None:
        with tempfile.TemporaryDirectory(prefix="linux-packaging-") as tmp:
            root = Path(tmp)
            self._write_valid_packaging_tree(root)
            with mock.patch.object(self.gate, "REPO_ROOT", root):
                results = self.gate.run_checks()

        self.assertTrue(all(result["ok"] for result in results))

    def test_missing_files_are_reported(self) -> None:
        with tempfile.TemporaryDirectory(prefix="linux-packaging-") as tmp:
            root = Path(tmp)
            with mock.patch.object(self.gate, "REPO_ROOT", root):
                results = self.gate.run_checks()

        self.assertFalse(all(result["ok"] for result in results))
        self.assertIn("missing", str(results[0]["detail"]))
        self.assertIn("desktop-entry keys", {str(result["name"]) for result in results})

    def test_desktop_file_requires_all_fields(self) -> None:
        with tempfile.TemporaryDirectory(prefix="linux-packaging-") as tmp:
            root = Path(tmp)
            self._write(root, "packaging/linux/io.vityo.desktop", "Name=Vityo\n")
            with mock.patch.object(self.gate, "REPO_ROOT", root):
                result = self.gate.check_desktop_file(
                    "packaging/linux/io.vityo.desktop"
                )

        self.assertFalse(result["ok"])
        self.assertIn("Exec", str(result["detail"]))

    def test_appstream_xml_handles_invalid_and_missing_tags(self) -> None:
        with tempfile.TemporaryDirectory(prefix="linux-packaging-") as tmp:
            root = Path(tmp)
            appstream = "packaging/linux/io.vityo.metainfo.xml"
            self._write(root, appstream, "<component>")
            with mock.patch.object(self.gate, "REPO_ROOT", root):
                invalid = self.gate.check_appstream_xml(appstream)

            self._write(root, appstream, "<component><id>io.vityo</id></component>")
            with mock.patch.object(self.gate, "REPO_ROOT", root):
                missing = self.gate.check_appstream_xml(appstream)

        self.assertFalse(invalid["ok"])
        self.assertIn("invalid XML", str(invalid["detail"]))
        self.assertFalse(missing["ok"])
        self.assertIn("summary", str(missing["detail"]))

    def test_appstream_xml_accepts_namespaced_tags(self) -> None:
        with tempfile.TemporaryDirectory(prefix="linux-packaging-") as tmp:
            root = Path(tmp)
            appstream = "packaging/linux/io.vityo.metainfo.xml"
            self._write(
                root,
                appstream,
                """<component xmlns="http://www.freedesktop.org/standards/appstream/1.0">
  <id>io.vityo</id>
  <name>Vityo</name>
  <summary>IDE shell</summary>
  <description><p>Vityo desktop package.</p></description>
</component>
""",
            )
            with mock.patch.object(self.gate, "REPO_ROOT", root):
                result = self.gate.check_appstream_xml(appstream)

        self.assertTrue(result["ok"])

    def test_debian_control_requires_package_fields(self) -> None:
        with tempfile.TemporaryDirectory(prefix="linux-packaging-") as tmp:
            root = Path(tmp)
            control = "packaging/linux/DEBIAN/control"
            self._write(root, control, "Package: vityo\n")
            with mock.patch.object(self.gate, "REPO_ROOT", root):
                result = self.gate.check_debian_control(control)

        self.assertFalse(result["ok"])
        self.assertIn("Architecture", str(result["detail"]))

    def test_main_emits_json_and_status_code(self) -> None:
        with tempfile.TemporaryDirectory(prefix="linux-packaging-") as tmp:
            root = Path(tmp)
            self._write_valid_packaging_tree(root)
            stdout = io.StringIO()
            with mock.patch.object(self.gate, "REPO_ROOT", root):
                with redirect_stdout(stdout):
                    code = self.gate.main(["--json"])

        self.assertEqual(code, 0)
        payload = json.loads(stdout.getvalue())
        self.assertTrue(payload["ok"])
        self.assertGreater(len(payload["checks"]), 0)

    def test_main_returns_failure_for_invalid_tree(self) -> None:
        with tempfile.TemporaryDirectory(prefix="linux-packaging-") as tmp:
            stdout = io.StringIO()
            with mock.patch.object(self.gate, "REPO_ROOT", Path(tmp)):
                with redirect_stdout(stdout):
                    code = self.gate.main([])

        self.assertEqual(code, 1)
        self.assertIn("[linux-packaging] FAIL", stdout.getvalue())


if __name__ == "__main__":
    unittest.main()

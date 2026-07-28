#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
import zipfile
import json
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[1]
PACKAGER_PATH = REPO_ROOT / "scripts/package-nightly.py"


def load_packager_module():
    spec = importlib.util.spec_from_file_location("package_nightly", PACKAGER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {PACKAGER_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class PackageNightlyTest(unittest.TestCase):
    def setUp(self) -> None:
        self.packager = load_packager_module()

    @staticmethod
    def _versions() -> dict[str, object]:
        return {
            "schema_version": 1,
            "core_version": "0.1.0-nightly",
            "platform_adapters": {"windows": "0.1.0-nightly.1"},
        }

    @staticmethod
    def _windows_config() -> dict[str, object]:
        return {
            "schema_version": 1,
            "platform": "windows",
            "package_format": "zip-powershell",
            "build_relative_path": "build/windows/release",
            "signing": {"status": "explicit-gap", "reason": "No test credential."},
            "automatic_updates": False,
        }

    def test_unsigned_package_cannot_enable_automatic_updates(self) -> None:
        config = self._windows_config()
        config["automatic_updates"] = True

        with self.assertRaisesRegex(ValueError, "cannot enable automatic updates"):
            self.packager.validate_release_inputs("windows", config, self._versions())

    def test_windows_package_contains_payload_and_installers(self) -> None:
        with tempfile.TemporaryDirectory(prefix="package-nightly-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            build = root / "build/windows/release"
            build.mkdir(parents=True)
            (build / "vityo_app.exe").write_bytes(b"application")
            packaging = root / "packaging/windows"
            packaging.mkdir(parents=True)
            (packaging / "install.ps1").write_text("# installer\n", encoding="utf-8")
            (packaging / "uninstall.ps1").write_text("# uninstaller\n", encoding="utf-8")
            output = root / "vityo-nightly-windows.zip"
            self.packager.ROOT = root

            self.packager.package_windows(self._windows_config(), output)

            with zipfile.ZipFile(output) as archive:
                names = set(archive.namelist())
        self.assertEqual(
            names,
            {
                "Styio-IDE-Nightly/install.ps1",
                "Styio-IDE-Nightly/uninstall.ps1",
                "Styio-IDE-Nightly/vityo_app.exe",
            },
        )

    def test_release_input_validation_covers_each_contract(self) -> None:
        valid = self._windows_config()
        versions = self._versions()
        self.assertEqual(
            self.packager.validate_release_inputs("windows", valid, versions),
            "0.1.0-nightly.1",
        )
        mutations = (
            ({**versions, "schema_version": 2}, valid),
            (versions, {**valid, "schema_version": 2}),
            (versions, {**valid, "package_format": "dmg"}),
            (versions, {**valid, "signing": {"status": "unknown"}}),
            (versions, {**valid, "signing": {"status": "explicit-gap", "reason": ""}}),
            (versions, {**valid, "automatic_updates": "false"}),
            ({**versions, "core_version": "latest"}, valid),
            ({**versions, "platform_adapters": {}}, valid),
        )
        for changed_versions, changed_config in mutations:
            with self.subTest(config=changed_config, versions=changed_versions):
                with self.assertRaises(ValueError):
                    self.packager.validate_release_inputs(
                        "windows", changed_config, changed_versions
                    )

    def test_file_directory_json_and_copy_helpers(self) -> None:
        with tempfile.TemporaryDirectory() as temp_name:
            root = Path(temp_name)
            source = root / "source"
            source.mkdir()
            (source / "nested").mkdir()
            (source / "nested/file.txt").write_text("nested", encoding="utf-8")
            (source / "top.txt").write_text("top", encoding="utf-8")
            destination = root / "destination"
            self.packager.copy_tree_contents(source, destination)
            self.assertEqual((destination / "nested/file.txt").read_text(), "nested")
            self.assertEqual(self.packager.require_dir(source), source)
            self.assertEqual(self.packager.require_file(source / "top.txt"), source / "top.txt")
            with self.assertRaises(FileNotFoundError):
                self.packager.require_file(root / "missing")
            with self.assertRaises(FileNotFoundError):
                self.packager.require_dir(root / "missing")
            value = root / "value.json"
            value.write_text('{"ok": true}', encoding="utf-8")
            self.assertEqual(self.packager.load_json(value), {"ok": True})
            value.write_text("[]", encoding="utf-8")
            with self.assertRaises(ValueError):
                self.packager.load_json(value)

    def test_linux_and_macos_packagers_delegate_to_native_tools(self) -> None:
        with tempfile.TemporaryDirectory() as temp_name:
            root = Path(temp_name)
            self.packager.ROOT = root
            build = root / "build/linux"
            build.mkdir(parents=True)
            (build / "vityo_app").write_text("app", encoding="utf-8")
            packaging = root / "packaging/linux"
            packaging.mkdir(parents=True)
            (packaging / "control").write_text("Version: 0.1.0\n", encoding="utf-8")
            (packaging / "io.styio.ide.desktop").write_text("desktop", encoding="utf-8")
            (packaging / "io.styio.ide.metainfo.xml").write_text("meta", encoding="utf-8")
            (packaging / "icon.png").write_bytes(b"png")
            config = {
                "build_relative_path": "build/linux",
                "installer_definition": "packaging/linux/control",
                "icon_relative_path": "packaging/linux/icon.png",
            }
            output = root / "vityo.deb"
            with mock.patch.object(self.packager.subprocess, "run") as run:
                self.assertEqual(
                    self.packager.package_linux(config, output, "1.2.3-nightly+4"),
                    output,
                )
            self.assertEqual(run.call_args.args[0][0], "dpkg-deb")

            app = root / "build/macos/Vityo.app"
            app.mkdir(parents=True)
            script = root / "packaging/macos/create-dmg.sh"
            script.parent.mkdir(parents=True)
            script.write_text("#!/bin/sh\n", encoding="utf-8")
            mac_output = root / "vityo.dmg"
            with mock.patch.object(self.packager.subprocess, "run") as run:
                result = self.packager.package_macos(
                    {
                        "build_relative_path": "build/macos/Vityo.app",
                        "installer_definition": "packaging/macos/create-dmg.sh",
                    },
                    mac_output,
                )
            self.assertEqual(result, mac_output)
            run.assert_called_once_with(["bash", script, app, mac_output], check=True)

    def test_main_builds_independent_windows_artifact_and_receipt(self) -> None:
        with tempfile.TemporaryDirectory() as temp_name:
            root = Path(temp_name)
            self.packager.ROOT = root
            packaging = root / "packaging"
            (packaging / "windows").mkdir(parents=True)
            (packaging / "windows/nightly.json").write_text(
                json.dumps(self._windows_config()), encoding="utf-8"
            )
            (packaging / "release-versions.json").write_text(
                json.dumps(self._versions()), encoding="utf-8"
            )
            output_dir = root / "out"
            with (
                mock.patch.object(
                    sys,
                    "argv",
                    ["package-nightly.py", "--platform", "windows", "--output-dir", str(output_dir)],
                ),
                mock.patch.object(self.packager, "package_windows", side_effect=lambda _, path: path.touch() or path),
                mock.patch("builtins.print"),
            ):
                self.assertEqual(self.packager.main(), 0)
            artifacts = list(output_dir.glob("*.zip"))
            receipt = json.loads(
                artifacts[0].with_suffix(".zip.json").read_text(encoding="utf-8")
            )
        self.assertEqual(receipt["platform"], "windows")
        self.assertEqual(receipt["adapter_version"], "0.1.0-nightly.1")


if __name__ == "__main__":
    unittest.main()

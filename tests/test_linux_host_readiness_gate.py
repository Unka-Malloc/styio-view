#!/usr/bin/env python3
"""Tests for the Linux host readiness gate."""

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
GATE_PATH = REPO_ROOT / "scripts" / "check-linux-host-readiness-gate.py"


def load_gate_module():
    spec = importlib.util.spec_from_file_location(
        "check_linux_host_readiness_gate", GATE_PATH
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {GATE_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class LinuxHostReadinessGateTest(unittest.TestCase):
    """Unit tests for the Linux host readiness gate."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.gate = load_gate_module()

    # helpers

    def _write_version_file(
        self, key: str, content: str
    ):
        """Temporarily swap a version file for a temp file with *content*."""
        tmp = tempfile.NamedTemporaryFile(
            mode="w", suffix=".txt", delete=False, encoding="utf-8"
        )
        tmp.write(content)
        tmp.close()
        original_path = self.gate.VERSION_FILES.get(key)
        patch = mock.patch.dict(
            self.gate.VERSION_FILES, {key: Path(tmp.name)}
        )
        return patch, tmp.name

    # python checks

    def test_python_found_and_matches(self) -> None:
        with mock.patch.object(
            self.gate, "_run", return_value="Python 3.13.5"
        ):
            with mock.patch.object(
                self.gate, "shutil", spec_set=True
            ) as mock_shutil:
                mock_shutil.which.return_value = "/usr/bin/python3"
                patch, tmp_path = self._write_version_file("python", "3.13.5")
                with patch:
                    result = self.gate.check_python()
        self.assertTrue(result["ok"])
        self.assertIn("3.13.5", str(result["detail"]))
        Path(tmp_path).unlink(missing_ok=True)

    def test_python_missing(self) -> None:
        with mock.patch.object(
            self.gate, "shutil", spec_set=True
        ) as mock_shutil:
            mock_shutil.which.return_value = None
            result = self.gate.check_python()
        self.assertFalse(result["ok"])
        self.assertTrue(result.get("blocked"))
        self.assertIn("not found", str(result["detail"]))

    def test_python_version_mismatch(self) -> None:
        with mock.patch.object(
            self.gate, "_run", return_value="Python 3.12.0"
        ):
            with mock.patch.object(
                self.gate, "shutil", spec_set=True
            ) as mock_shutil:
                mock_shutil.which.return_value = "/usr/bin/python3"
                patch, tmp_path = self._write_version_file(
                    "python", "3.13.5"
                )
                with patch:
                    result = self.gate.check_python()
        self.assertFalse(result["ok"])
        self.assertFalse(result.get("blocked"))
        self.assertIn("3.12.0", str(result["detail"]))
        self.assertIn("3.13.5", str(result["detail"]))
        Path(tmp_path).unlink(missing_ok=True)

    def test_python_version_output_unparseable(self) -> None:
        with mock.patch.object(
            self.gate, "_run", return_value="Python weird"
        ):
            with mock.patch.object(
                self.gate, "shutil", spec_set=True
            ) as mock_shutil:
                mock_shutil.which.return_value = "/usr/bin/python3"
                result = self.gate.check_python()
        self.assertFalse(result["ok"])
        self.assertIn("unparseable", str(result["detail"]))

    # flutter checks

    def test_flutter_found(self) -> None:
        sample = (
            "Flutter 3.41.7 - channel stable - https://github.com/flutter/flutter\n"
            "Dart 3.11.5\n"
        )
        with mock.patch.object(
            self.gate, "_run", return_value=sample
        ):
            with mock.patch.object(
                self.gate, "shutil", spec_set=True
            ) as mock_shutil:
                mock_shutil.which.return_value = "/opt/flutter/bin/flutter"
                patch, tmp_path = self._write_version_file(
                    "flutter", "3.41.7"
                )
                with patch:
                    result = self.gate.check_flutter()
        self.assertTrue(result["ok"])
        self.assertIn("3.41.7", str(result["detail"]))
        Path(tmp_path).unlink(missing_ok=True)

    def test_flutter_missing(self) -> None:
        with mock.patch.object(
            self.gate, "shutil", spec_set=True
        ) as mock_shutil:
            mock_shutil.which.return_value = None
            result = self.gate.check_flutter()
        self.assertFalse(result["ok"])
        self.assertTrue(result.get("blocked"))
        self.assertIn("not found", str(result["detail"]))

    def test_flutter_version_mismatch(self) -> None:
        sample = (
            "Flutter 3.40.0 - channel stable - https://github.com/flutter/flutter\n"
            "Dart 3.10.0\n"
        )
        with mock.patch.object(
            self.gate, "_run", return_value=sample
        ):
            with mock.patch.object(
                self.gate, "shutil", spec_set=True
            ) as mock_shutil:
                mock_shutil.which.return_value = "/opt/flutter/bin/flutter"
                patch, tmp_path = self._write_version_file(
                    "flutter", "3.41.7"
                )
                with patch:
                    result = self.gate.check_flutter()
        self.assertFalse(result["ok"])
        self.assertIn("3.40.0", str(result["detail"]))
        self.assertIn("3.41.7", str(result["detail"]))
        Path(tmp_path).unlink(missing_ok=True)

    def test_flutter_version_output_no_match(self) -> None:
        with mock.patch.object(
            self.gate, "_run", return_value="some garbage output"
        ):
            with mock.patch.object(
                self.gate, "shutil", spec_set=True
            ) as mock_shutil:
                mock_shutil.which.return_value = "/opt/flutter/bin/flutter"
                result = self.gate.check_flutter()
        self.assertFalse(result["ok"])
        self.assertIn("could not parse", str(result["detail"]))

    def test_flutter_crlf_sdk_script_blocker(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            flutter_bin = Path(tmp) / "flutter" / "bin" / "flutter"
            shared_sh = flutter_bin.parent / "internal" / "shared.sh"
            shared_sh.parent.mkdir(parents=True)
            flutter_bin.write_bytes(b"#!/usr/bin/env bash\n")
            shared_sh.write_bytes(b"#!/usr/bin/env bash\r\n")

            with mock.patch.object(self.gate, "_run", return_value=None):
                with mock.patch.object(
                    self.gate, "shutil", spec_set=True
                ) as mock_shutil:
                    mock_shutil.which.return_value = str(flutter_bin)
                    result = self.gate.check_flutter()

        self.assertFalse(result["ok"])
        self.assertTrue(result.get("blocked"))
        self.assertIn("CRLF", str(result["detail"]))
        self.assertIn("shared.sh", str(result["detail"]))

    # npm checks

    def test_npm_found(self) -> None:
        with mock.patch.object(
            self.gate, "_run", return_value="v24.15.0"
        ):
            with mock.patch.object(
                self.gate, "shutil", spec_set=True
            ) as mock_shutil:
                mock_shutil.which.side_effect = (
                    lambda x: f"/usr/bin/{x}" if x in ("node", "npm") else None
                )
                patch, tmp_path = self._write_version_file(
                    "node", "v24.15.0"
                )
                with patch:
                    result = self.gate.check_npm()
        self.assertTrue(result["ok"])
        self.assertIn("v24.15.0", str(result["detail"]))
        Path(tmp_path).unlink(missing_ok=True)

    def test_npm_accepts_nvmrc_without_v_prefix(self) -> None:
        with mock.patch.object(
            self.gate, "_run", return_value="v24.15.0"
        ):
            with mock.patch.object(
                self.gate, "shutil", spec_set=True
            ) as mock_shutil:
                mock_shutil.which.side_effect = (
                    lambda x: f"/usr/bin/{x}" if x in ("node", "npm") else None
                )
                patch, tmp_path = self._write_version_file(
                    "node", "24.15.0"
                )
                with patch:
                    result = self.gate.check_npm()
        self.assertTrue(result["ok"])
        self.assertIn("v24.15.0", str(result["detail"]))
        Path(tmp_path).unlink(missing_ok=True)

    def test_npm_node_missing(self) -> None:
        with mock.patch.object(
            self.gate, "shutil", spec_set=True
        ) as mock_shutil:
            mock_shutil.which.return_value = None
            result = self.gate.check_npm()
        self.assertFalse(result["ok"])
        self.assertTrue(result.get("blocked"))
        self.assertIn("not found", str(result["detail"]))

    def test_npm_version_mismatch(self) -> None:
        with mock.patch.object(
            self.gate, "_run", return_value="v22.0.0"
        ):
            with mock.patch.object(
                self.gate, "shutil", spec_set=True
            ) as mock_shutil:
                mock_shutil.which.side_effect = (
                    lambda x: f"/usr/bin/{x}" if x in ("node", "npm") else None
                )
                patch, tmp_path = self._write_version_file(
                    "node", "v24.15.0"
                )
                with patch:
                    result = self.gate.check_npm()
        self.assertFalse(result["ok"])
        self.assertIn("v22.0.0", str(result["detail"]))
        self.assertIn("v24.15.0", str(result["detail"]))
        Path(tmp_path).unlink(missing_ok=True)

    def test_npm_missing_npm_binary(self) -> None:
        """When node matches expected but npm is absent, warn about npm."""
        def which_side(name: str) -> str | None:
            if name == "node":
                return "/usr/bin/node"
            return None

        with mock.patch.object(
            self.gate, "_run", return_value="v24.15.0"
        ):
            with mock.patch.object(
                self.gate, "shutil", spec_set=True
            ) as mock_shutil:
                mock_shutil.which.side_effect = which_side
                patch, tmp_path = self._write_version_file(
                    "node", "v24.15.0"
                )
                with patch:
                    result = self.gate.check_npm()
        self.assertFalse(result["ok"])
        self.assertIn("but npm is missing", str(result["detail"]))
        Path(tmp_path).unlink(missing_ok=True)

    # chromium checks

    def test_chromium_found(self) -> None:
        with mock.patch.object(
            self.gate, "_run", return_value="Chromium 147.0.7727.116"
        ):
            with mock.patch.object(
                self.gate, "shutil", spec_set=True
            ) as mock_shutil:
                mock_shutil.which.side_effect = (
                    lambda x: f"/usr/bin/{x}" if x == "chromium" else None
                )
                patch, tmp_path = self._write_version_file(
                    "chromium", "147.0.7727.116"
                )
                with patch:
                    result = self.gate.check_chromium()
        self.assertTrue(result["ok"])
        self.assertIn("147.0.7727.116", str(result["detail"]))
        Path(tmp_path).unlink(missing_ok=True)

    def test_chromium_missing(self) -> None:
        with mock.patch.object(
            self.gate, "shutil", spec_set=True
        ) as mock_shutil:
            mock_shutil.which.return_value = None
            result = self.gate.check_chromium()
        self.assertFalse(result["ok"])
        self.assertTrue(result.get("blocked"))
        self.assertIn("no Chromium/Chrome binary found", str(result["detail"]))

    def test_chromium_version_mismatch(self) -> None:
        with mock.patch.object(
            self.gate, "_run", return_value="Chromium 146.0.0.0"
        ):
            with mock.patch.object(
                self.gate, "shutil", spec_set=True
            ) as mock_shutil:
                mock_shutil.which.side_effect = (
                    lambda x: f"/usr/bin/{x}" if x == "chromium" else None
                )
                patch, tmp_path = self._write_version_file(
                    "chromium", "147.0.7727.116"
                )
                with patch:
                    result = self.gate.check_chromium()
        self.assertFalse(result["ok"])
        self.assertIn("146.0.0.0", str(result["detail"]))
        self.assertIn("147.0.7727.116", str(result["detail"]))
        Path(tmp_path).unlink(missing_ok=True)

    def test_chromium_alternate_binary(self) -> None:
        with mock.patch.object(
            self.gate, "_run", return_value="Google Chrome 147.0.7727.116"
        ):
            with mock.patch.object(
                self.gate, "shutil", spec_set=True
            ) as mock_shutil:

                def which_side(name: str) -> str | None:
                    mapping = {
                        "chromium": None,
                        "chromium-browser": None,
                        "google-chrome": "/usr/bin/google-chrome",
                    }
                    return mapping.get(name)

                mock_shutil.which.side_effect = which_side
                result = self.gate.check_chromium()
        self.assertTrue(result["ok"])
        self.assertIn("google-chrome", str(result["detail"]))

    # docker-flutter checks

    def test_docker_flutter_available(self) -> None:
        flutter_sample = (
            "Flutter 3.41.7 - channel stable - https://github.com/flutter/flutter\n"
        )
        with mock.patch.object(
            self.gate, "shutil", spec_set=True
        ) as mock_shutil:
            mock_shutil.which.return_value = "/usr/bin/docker"
            with mock.patch.object(
                self.gate, "_run"
            ) as mock_run:
                mock_run.side_effect = [
                    "24.0.7",  # docker info
                    f"{self.gate.DEV_CONTAINER_TAG}\n",  # docker images
                    flutter_sample,  # docker run flutter --version
                ]
                result = self.gate.check_docker_flutter()
        self.assertTrue(result["ok"])
        self.assertIn("3.41.7", str(result["detail"]))
        self.assertIn("24.0.7", str(result["detail"]))

    def test_docker_missing(self) -> None:
        with mock.patch.object(
            self.gate, "shutil", spec_set=True
        ) as mock_shutil:
            mock_shutil.which.return_value = None
            result = self.gate.check_docker_flutter()
        self.assertFalse(result["ok"])
        self.assertTrue(result.get("blocked"))
        self.assertIn("not found", str(result["detail"]))

    def test_docker_daemon_unreachable(self) -> None:
        with mock.patch.object(
            self.gate, "shutil", spec_set=True
        ) as mock_shutil:
            mock_shutil.which.return_value = "/usr/bin/docker"
            with mock.patch.object(
                self.gate, "_run", return_value=None
            ):
                result = self.gate.check_docker_flutter()
        self.assertFalse(result["ok"])
        self.assertTrue(result.get("blocked"))
        self.assertIn("daemon unreachable", str(result["detail"]))

    def test_docker_image_not_found(self) -> None:
        with mock.patch.object(
            self.gate, "shutil", spec_set=True
        ) as mock_shutil:
            mock_shutil.which.return_value = "/usr/bin/docker"
            with mock.patch.object(
                self.gate, "_run"
            ) as mock_run:
                mock_run.side_effect = [
                    "24.0.7",         # docker info
                    "other/image:latest\n",  # docker images: no dev image
                ]
                result = self.gate.check_docker_flutter()
        self.assertFalse(result["ok"])
        self.assertFalse(result.get("blocked"))
        self.assertIn("not found locally", str(result["detail"]))

    # CRLF script checks

    def test_crlf_scripts_clean(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            sh_dir = Path(tmp) / "frontend" / "vityo_app" / "scripts"
            sh_dir.mkdir(parents=True)
            good = sh_dir / "good.sh"
            good.write_bytes(b"#!/usr/bin/env bash\nset -euo pipefail\n")

            with mock.patch.object(
                self.gate, "REPO_ROOT", Path(tmp)
            ):
                result = self.gate.check_crlf_scripts()
        self.assertTrue(result["ok"])
        self.assertIn("LF line endings", str(result["detail"]))

    def test_crlf_scripts_detected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            sh_dir = Path(tmp) / "frontend" / "vityo_app" / "scripts"
            sh_dir.mkdir(parents=True)
            bad = sh_dir / "bad.sh"
            bad.write_bytes(b"#!/usr/bin/env bash\r\nset -euo pipefail\r\n")
            good = sh_dir / "good.sh"
            good.write_bytes(b"#!/usr/bin/env bash\nset -euo pipefail\n")

            with mock.patch.object(
                self.gate, "REPO_ROOT", Path(tmp)
            ):
                result = self.gate.check_crlf_scripts()
        self.assertFalse(result["ok"])
        self.assertTrue(result.get("blocked"))
        self.assertIn("bad.sh", str(result["detail"]))
        self.assertNotIn("good.sh", str(result["detail"]))

    def test_crlf_scripts_scans_extra_roots(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            scripts_dir = Path(tmp) / "scripts"
            scripts_dir.mkdir(parents=True)
            bad_sh = scripts_dir / "some-tool.sh"
            bad_sh.write_bytes(b"#!/usr/bin/env bash\r\n")
            docker_dir = Path(tmp) / "docker"
            docker_dir.mkdir(parents=True)
            bad_docker = docker_dir / "build.sh"
            bad_docker.write_bytes(b"#!/usr/bin/env bash\r\n")

            with mock.patch.object(
                self.gate, "REPO_ROOT", Path(tmp)
            ):
                result = self.gate.check_crlf_scripts()
        self.assertFalse(result["ok"])
        self.assertIn("some-tool.sh", str(result["detail"]))
        self.assertIn("build.sh", str(result["detail"]))

    # JSON output

    def test_json_output_contains_all_checks(self) -> None:
        """The --json flag should produce valid JSON with all registered
        checks present."""
        with mock.patch.object(
            self.gate, "run_all_checks"
        ) as mock_all:
            mock_all.return_value = [
                {"name": "python", "ok": True, "detail": "Python 3.13.5"},
                {"name": "flutter", "ok": False, "blocked": True,
                 "detail": "flutter not found"},
            ]
            with mock.patch.object(
                self.gate, "json"
            ) as mock_json:
                mock_json.dumps.return_value = '{"ok": false}'
                with mock.patch.object(
                    self.gate, "print"
                ) as mock_print:
                    with redirect_stdout(io.StringIO()):
                        exit_code = self.gate.main(["--json"])
        self.assertEqual(exit_code, 1)
        mock_all.assert_called_once()

    def test_main_exit_code_blocked(self) -> None:
        """Blocked checks should yield exit code 1."""
        with mock.patch.object(
            self.gate, "run_all_checks"
        ) as mock_all:
            mock_all.return_value = [
                {"name": "crlf-scripts", "ok": False, "blocked": True,
                 "detail": "CRLF detected"},
            ]
            with redirect_stdout(io.StringIO()):
                exit_code = self.gate.main(["--json"])
        self.assertEqual(exit_code, 1)

    def test_main_exit_code_warnings_only(self) -> None:
        """Only warnings (non-blocked failures) should yield exit code 2."""
        with mock.patch.object(
            self.gate, "run_all_checks"
        ) as mock_all:
            mock_all.return_value = [
                {"name": "chromium", "ok": False, "blocked": False,
                 "detail": "version mismatch"},
            ]
            with redirect_stdout(io.StringIO()):
                exit_code = self.gate.main(["--json"])
        self.assertEqual(exit_code, 2)

    def test_main_exit_code_all_pass(self) -> None:
        """All passing checks should yield exit code 0."""
        with mock.patch.object(
            self.gate, "run_all_checks"
        ) as mock_all:
            mock_all.return_value = [
                {"name": "python", "ok": True, "detail": "Python 3.13.5"},
            ]
            with redirect_stdout(io.StringIO()):
                exit_code = self.gate.main(["--json"])
        self.assertEqual(exit_code, 0)

    def test_single_check_flag(self) -> None:
        """--check should run only the named check."""
        with mock.patch.object(
            self.gate, "run_single_check", return_value={
                "name": "flutter", "ok": True, "detail": "ok"
            }
        ) as mock_single:
            with redirect_stdout(io.StringIO()):
                result = self.gate.main(["--check", "flutter"])
        mock_single.assert_called_once_with("flutter")
        self.assertEqual(result, 0)

    def test_single_check_unknown(self) -> None:
        """An unknown check name should produce a failure result."""
        result = self.gate.run_single_check("nonexistent")
        self.assertFalse(result["ok"])
        self.assertIn("unknown check", str(result["detail"]))

    def test_registry_contains_all_keys(self) -> None:
        """Every check name in CHECK_REGISTRY should have a matching
        module-level function."""
        for name in self.gate.CHECK_REGISTRY:
            with self.subTest(check=name):
                func = self.gate._CHECK_FUNCS.get(name)
                self.assertIsNotNone(func, f"no function for {name}")
                self.assertTrue(callable(func))

    def test_read_version_file_missing(self) -> None:
        """_read_version_file returns None for non-existent entries."""
        result = self.gate._read_version_file("nonexistent")
        self.assertIsNone(result)

    def test_run_returns_none_on_fnf_error(self) -> None:
        """_run returns None when the command is not found."""
        result = self.gate._run(["does-not-exist-hopefully"])
        self.assertIsNone(result)

    def test_run_all_checks_include_subset(self) -> None:
        """run_all_checks with an include set runs only those checks."""
        results = self.gate.run_all_checks(include={"python", "npm"})
        names = {r["name"] for r in results}
        self.assertEqual(names, {"python", "npm"})


if __name__ == "__main__":
    unittest.main()

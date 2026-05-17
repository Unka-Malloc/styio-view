#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
GATE_PATH = REPO_ROOT / "scripts" / "release-readiness-gate.py"


def load_gate_module():
    spec = importlib.util.spec_from_file_location(
        "release_readiness_gate",
        GATE_PATH,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {GATE_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class ReleaseReadinessGateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.gate = load_gate_module()

    def _write_minimal_release_tree(self, root: Path) -> None:
        for relative_path in self.gate.REQUIRED_RELEASE_FILES:
            path = root / relative_path
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("placeholder\n", encoding="utf-8")

        pubspec_path = root / "frontend/vityo_app/pubspec.yaml"
        pubspec_path.write_text(
            "name: vityo_app\n"
            "description: Vityo IDE editor shell for web, desktop, and mobile targets.\n"
            "publish_to: \"none\"\n"
            "version: 0.1.0+1\n",
            encoding="utf-8",
        )

        readme_path = root / "frontend/vityo_app/README.md"
        readme_path.write_text(
            "# Vityo Flutter Shell\n\n"
            "## Release readiness gate\n\n"
            "Run `python3 scripts/release-readiness-gate.py` from the repository root.\n"
            "The release build command is `flutter build web --release`.\n",
            encoding="utf-8",
        )

        for paths in self.gate.REQUIRED_IDE_CAPABILITY_TESTS.values():
            for relative_path in paths:
                path = root / relative_path
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("// test placeholder\n", encoding="utf-8")

    def test_static_checks_accept_release_tree(self) -> None:
        with tempfile.TemporaryDirectory(prefix="release-gate-", dir=REPO_ROOT) as tmp_name:
            tmp_root = Path(tmp_name)
            self._write_minimal_release_tree(tmp_root)

            results = self.gate.collect_static_checks(
                tmp_root,
                Path("frontend/vityo_app"),
            )

        self.assertTrue(all(result.ok for result in results), results)

    def test_static_checks_reject_missing_capability_test(self) -> None:
        with tempfile.TemporaryDirectory(prefix="release-gate-", dir=REPO_ROOT) as tmp_name:
            tmp_root = Path(tmp_name)
            self._write_minimal_release_tree(tmp_root)
            missing_path = tmp_root / "frontend/vityo_app/test/styio_completion_feature_test.dart"
            missing_path.unlink()

            results = self.gate.collect_static_checks(
                tmp_root,
                Path("frontend/vityo_app"),
            )

        self.assertTrue(
            any(
                not result.ok
                and result.name == "IDE capability test coverage: language service"
                and "styio_completion_feature_test.dart" in result.detail
                for result in results
            ),
            results,
        )

    def test_static_checks_reject_non_vityo_pubspec(self) -> None:
        with tempfile.TemporaryDirectory(prefix="release-gate-", dir=REPO_ROOT) as tmp_name:
            tmp_root = Path(tmp_name)
            self._write_minimal_release_tree(tmp_root)
            (tmp_root / "frontend/vityo_app/pubspec.yaml").write_text(
                "name: styio_view_app\n"
                "description: old shell\n"
                "publish_to: \"none\"\n"
                "version: 0.1.0+1\n",
                encoding="utf-8",
            )

            results = self.gate.collect_static_checks(
                tmp_root,
                Path("frontend/vityo_app"),
            )

        failed_names = {result.name for result in results if not result.ok}
        self.assertIn("pubspec name", failed_names)
        self.assertIn("pubspec description", failed_names)

    def test_main_reports_json_without_running_build_when_skipped(self) -> None:
        with tempfile.TemporaryDirectory(prefix="release-gate-", dir=REPO_ROOT) as tmp_name:
            tmp_root = Path(tmp_name)
            self._write_minimal_release_tree(tmp_root)
            output = io.StringIO()

            with redirect_stdout(output):
                exit_code = self.gate.main(
                    [
                        "--repo-root",
                        str(tmp_root),
                        "--flutter-dir",
                        "frontend/vityo_app",
                        "--skip-build",
                        "--json",
                    ]
                )

        payload = json.loads(output.getvalue())
        self.assertEqual(exit_code, 0)
        self.assertTrue(payload["ok"])
        self.assertFalse(
            any(check["name"] == "flutter release build" for check in payload["checks"])
        )


if __name__ == "__main__":
    unittest.main()

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
from unittest import mock


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

    def _write_minimal_tooling_manifest(self, root: Path) -> None:
        tool_path = root / "scripts/release-readiness-gate.py"
        tool_path.parent.mkdir(parents=True, exist_ok=True)
        tool_path.write_text("#!/usr/bin/env python3\n", encoding="utf-8")

        runbook_by_module = {
            "adapter-contracts": "docs/teams/ADAPTER-CONTRACTS-RUNBOOK.md",
            "coordination": "docs/teams/COORDINATION-RUNBOOK.md",
            "docs-delivery": "docs/teams/DOCS-DELIVERY-RUNBOOK.md",
            "foundation-environment": "docs/teams/DOCS-DELIVERY-RUNBOOK.md",
            "module-platform": "docs/teams/MODULE-PLATFORM-RUNBOOK.md",
            "runtime-agent": "docs/teams/RUNTIME-AGENT-RUNBOOK.md",
            "shell-editor": "docs/teams/SHELL-EDITOR-RUNBOOK.md",
            "theme-ux": "docs/teams/THEME-UX-RUNBOOK.md",
        }
        for relative_path in set(runbook_by_module.values()):
            path = root / relative_path
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("# Runbook\n", encoding="utf-8")

        manifest = {
            "schema": 1,
            "project": "Vityo",
            "last_updated": "2026-06-19",
            "release_gate": "scripts/release-readiness-gate.py",
            "policy": {
                "current_state": "current-only",
                "stale_support": "forbidden",
                "minimum_tool_status": "current",
                "module_coverage": "required",
            },
            "tools": [
                {
                    "id": "release-readiness-gate",
                    "kind": "gate",
                    "status": "current",
                    "path": "scripts/release-readiness-gate.py",
                    "command": "python3 scripts/release-readiness-gate.py --skip-build",
                    "scope": ["release", "tooling"],
                }
            ],
            "skills": [
                {
                    "id": "release-operations",
                    "status": "current",
                    "backing_tools": ["release-readiness-gate"],
                }
            ],
            "modules": [
                {
                    "id": module_id,
                    "status": "current",
                    "runbook": runbook_by_module[module_id],
                    "owned_paths": ["docs/"],
                    "maintenance_tools": ["release-readiness-gate"],
                    "skills": ["release-operations"],
                }
                for module_id in sorted(self.gate.REQUIRED_MAINTENANCE_MODULES)
            ],
        }
        manifest_path = root / self.gate.TOOLING_MANIFEST_PATH
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

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

        self._write_minimal_tooling_manifest(root)

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

    def test_static_checks_reject_stale_tool_status(self) -> None:
        with tempfile.TemporaryDirectory(prefix="release-gate-", dir=REPO_ROOT) as tmp_name:
            tmp_root = Path(tmp_name)
            self._write_minimal_release_tree(tmp_root)
            manifest_path = tmp_root / self.gate.TOOLING_MANIFEST_PATH
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["tools"][0]["status"] = "deprecated"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            results = self.gate.collect_static_checks(
                tmp_root,
                Path("frontend/vityo_app"),
            )

        self.assertTrue(
            any(
                not result.ok
                and result.name == "maintenance tool status: release-readiness-gate"
                and result.detail == "deprecated"
                for result in results
            ),
            results,
        )

    def test_static_checks_reject_module_without_maintenance_tool(self) -> None:
        with tempfile.TemporaryDirectory(prefix="release-gate-", dir=REPO_ROOT) as tmp_name:
            tmp_root = Path(tmp_name)
            self._write_minimal_release_tree(tmp_root)
            manifest_path = tmp_root / self.gate.TOOLING_MANIFEST_PATH
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["modules"][0]["maintenance_tools"] = []
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            results = self.gate.collect_static_checks(
                tmp_root,
                Path("frontend/vityo_app"),
            )

        self.assertTrue(
            any(
                not result.ok
                and result.name.startswith("maintenance module tools:")
                and "maintenance_tools" in result.detail
                for result in results
            ),
            results,
        )

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

    def test_small_parsers_and_manifest_loader_reject_invalid_inputs(self) -> None:
        parsed = self.gate.parse_pubspec_fields(
            "# comment\n"
            "name: 'vityo_app'\n"
            "description: \"Vityo IDE editor shell\"\n"
            " nested: ignored\n"
            "bad line\n"
        )
        self.assertEqual(parsed["name"], "vityo_app")
        self.assertEqual(parsed["description"], "Vityo IDE editor shell")
        self.assertNotIn("nested", parsed)

        self.assertIsNone(self.gate.parse_policy_date(None))
        self.assertIsNone(self.gate.parse_policy_date("not-a-date"))
        self.assertFalse(self.gate.is_safe_relative_path(""))
        self.assertFalse(self.gate.is_safe_relative_path("/absolute"))
        self.assertFalse(self.gate.is_safe_relative_path("../escape"))
        self.assertTrue(self.gate.is_safe_relative_path("docs/file.md"))
        self.assertEqual(self.gate.string_list("not-list"), [])
        self.assertEqual(self.gate.string_list(["a", "", 1, "b"]), ["a", "b"])
        self.assertEqual(
            self.gate.entry_text_fields(
                {
                    "id": "tool",
                    "kind": "gate",
                    "status": "deprecated",
                    "path": "scripts/tool.py",
                    "command": "run",
                    "scope": ["release", 1],
                    "owned_paths": ["docs/"],
                }
            ),
            ["tool", "gate", "deprecated", "scripts/tool.py", "run", "release", "docs/"],
        )
        self.assertTrue(self.gate.has_stale_tooling_marker({"status": "deprecated"}))

        with tempfile.TemporaryDirectory(prefix="release-gate-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            missing, missing_error = self.gate.load_tooling_manifest(root / "missing.json")
            self.assertIsNone(missing)
            self.assertIsNotNone(missing_error)
            invalid_json = root / "invalid.json"
            invalid_json.write_text("{bad", encoding="utf-8")
            payload, error = self.gate.load_tooling_manifest(invalid_json)
            self.assertIsNone(payload)
            self.assertIn("invalid JSON", error)
            invalid_root = root / "list.json"
            invalid_root.write_text("[]", encoding="utf-8")
            payload, error = self.gate.load_tooling_manifest(invalid_root)
            self.assertIsNone(payload)
            self.assertEqual(error, "manifest root must be an object")

    def test_check_missing_pubspec_readme_and_bad_tooling_manifest_shapes(self) -> None:
        with tempfile.TemporaryDirectory(prefix="release-gate-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            self.assertEqual(
                self.gate.check_pubspec(root, Path("frontend/vityo_app"))[0].name,
                "pubspec metadata",
            )
            self.assertEqual(
                self.gate.check_readme(root, Path("frontend/vityo_app"))[0].name,
                "release README markers",
            )
            manifest_path = root / self.gate.TOOLING_MANIFEST_PATH
            manifest_path.parent.mkdir(parents=True)
            manifest_path.write_text(
                json.dumps(
                    {
                        "schema": 2,
                        "project": "Old",
                        "last_updated": "bad-date",
                        "release_gate": "old/gate.py",
                        "policy": {
                            "current_state": "legacy",
                            "stale_support": "allowed",
                        },
                        "tools": [
                            "bad-tool",
                            {"status": "current"},
                            {
                                "id": "release-readiness-gate",
                                "status": "deprecated",
                                "path": "../escape.py",
                                "command": "",
                                "scope": ["legacy"],
                            },
                            {
                                "id": "release-readiness-gate",
                                "status": "current",
                                "path": "scripts/release-readiness-gate.py",
                                "command": "python3 scripts/release-readiness-gate.py",
                            },
                        ],
                        "skills": [
                            "bad-skill",
                            {"status": "current"},
                            {
                                "id": "release-operations",
                                "status": "deprecated",
                                "backing_tools": ["missing-tool"],
                            },
                            {
                                "id": "release-operations",
                                "status": "current",
                                "backing_tools": ["release-readiness-gate"],
                            },
                        ],
                        "modules": [
                            "bad-module",
                            {"status": "current"},
                            {
                                "id": "adapter-contracts",
                                "status": "deprecated",
                                "runbook": "/absolute.md",
                                "maintenance_tools": ["missing-tool"],
                                "skills": ["missing-skill"],
                                "owned_paths": ["old/docs"],
                            },
                            {
                                "id": "adapter-contracts",
                                "status": "current",
                                "runbook": "docs/teams/ADAPTER-CONTRACTS-RUNBOOK.md",
                                "maintenance_tools": ["release-readiness-gate"],
                                "skills": ["release-operations"],
                            },
                        ],
                    }
                ),
                encoding="utf-8",
            )
            (root / "scripts").mkdir()
            (root / "scripts/release-readiness-gate.py").write_text("# gate\n", encoding="utf-8")
            (root / "docs/teams").mkdir(parents=True)
            (root / "docs/teams/ADAPTER-CONTRACTS-RUNBOOK.md").write_text("# runbook\n", encoding="utf-8")

            results = self.gate.check_tooling_manifest(root)

        by_name = {result.name: result for result in results}
        def has_failed(name: str) -> bool:
            return any(result.name == name and not result.ok for result in results)

        self.assertFalse(by_name["maintenance tooling schema"].ok)
        self.assertFalse(by_name["maintenance tooling project"].ok)
        self.assertFalse(by_name["maintenance tooling updated"].ok)
        self.assertFalse(by_name["maintenance tooling policy: current state"].ok)
        self.assertFalse(by_name["maintenance tooling policy: stale support"].ok)
        self.assertFalse(by_name["maintenance tooling release gate"].ok)
        self.assertTrue(any(result.name == "maintenance tool entry" for result in results))
        self.assertTrue(any(result.name == "maintenance tool id" for result in results))
        self.assertTrue(has_failed("maintenance tool status: release-readiness-gate"))
        self.assertTrue(has_failed("maintenance tool path: release-readiness-gate"))
        self.assertTrue(has_failed("maintenance tool command: release-readiness-gate"))
        self.assertTrue(has_failed("maintenance tool current-only text: release-readiness-gate"))
        self.assertFalse(by_name["maintenance tool ids unique"].ok)
        self.assertTrue(any(result.name == "maintenance skill entry" for result in results))
        self.assertTrue(any(result.name == "maintenance skill id" for result in results))
        self.assertTrue(has_failed("maintenance skill status: release-operations"))
        self.assertTrue(has_failed("maintenance skill tools: release-operations"))
        self.assertTrue(has_failed("maintenance skill current-only text: release-operations"))
        self.assertFalse(by_name["maintenance skill ids unique"].ok)
        self.assertTrue(any(result.name == "maintenance module entry" for result in results))
        self.assertTrue(any(result.name == "maintenance module id" for result in results))
        self.assertTrue(has_failed("maintenance module status: adapter-contracts"))
        self.assertTrue(has_failed("maintenance module runbook: adapter-contracts"))
        self.assertTrue(has_failed("maintenance module tools: adapter-contracts"))
        self.assertTrue(has_failed("maintenance module skills: adapter-contracts"))
        self.assertTrue(has_failed("maintenance module current-only text: adapter-contracts"))
        self.assertFalse(by_name["maintenance module ids unique"].ok)
        self.assertFalse(by_name["maintenance module coverage"].ok)

    def test_release_build_payload_human_output_and_main_build_path(self) -> None:
        with tempfile.TemporaryDirectory(prefix="release-gate-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            missing = self.gate.run_release_build(root, Path("frontend/vityo_app"))
            self.assertFalse(missing.ok)
            self.assertIn("missing", missing.detail)

            app_dir = root / "frontend/vityo_app"
            app_dir.mkdir(parents=True)
            with mock.patch.object(self.gate.subprocess, "run") as run:
                run.return_value.returncode = 0
                passed = self.gate.run_release_build(root, Path("frontend/vityo_app"))
                run.return_value.returncode = 2
                failed = self.gate.run_release_build(root, Path("frontend/vityo_app"))

        self.assertTrue(passed.ok)
        self.assertEqual(passed.detail, "flutter build web --release")
        self.assertFalse(failed.ok)
        self.assertEqual(failed.detail, "exit code 2")

        payload = self.gate.result_payload(
            [
                self.gate.CheckResult("pass", True, "ok"),
                self.gate.CheckResult("fail", False, "bad"),
            ]
        )
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["checks"][1]["name"], "fail")

        output = io.StringIO()
        with redirect_stdout(output):
            self.gate.print_human([self.gate.CheckResult("pass", True, "ok")])
        self.assertIn("[release-readiness] ok: pass (ok)", output.getvalue())

        with mock.patch.object(
            self.gate,
            "collect_static_checks",
            return_value=[self.gate.CheckResult("static", True, "ok")],
        ) as collect:
            with mock.patch.object(
                self.gate,
                "run_release_build",
                return_value=self.gate.CheckResult("flutter release build", False, "exit code 1"),
            ) as build:
                output = io.StringIO()
                with redirect_stdout(output):
                    code = self.gate.main(["--repo-root", ".", "--flutter-dir", "frontend/vityo_app"])

        self.assertEqual(code, 1)
        collect.assert_called_once()
        build.assert_called_once()
        self.assertIn("[release-readiness] error: flutter release build", output.getvalue())


if __name__ == "__main__":
    unittest.main()

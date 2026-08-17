"""Acceptance for the manifest-bound vityod desktop component."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import pathlib
import stat
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]


def _load_module(name: str, path: pathlib.Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class VityodPackagingAcceptanceTest(unittest.TestCase):
    def test_repository_binds_exactly_one_vityod_for_each_desktop_lane(
        self,
    ) -> None:
        delivery = _load_module(
            "vityo_desktop_delivery_acceptance",
            ROOT / "packaging" / "vityo" / "desktop_delivery.py",
        )
        self.assertEqual(delivery.validate_repository(ROOT), [])

        for platform in delivery.PLATFORMS:
            with self.subTest(platform=platform):
                manifest = json.loads(
                    (ROOT / "packaging" / platform / "nightly.json").read_text(
                        encoding="utf-8"
                    )
                )
                self.assertEqual(
                    set(key for key in manifest if key == "vityod"), {"vityod"}
                )
                component = manifest["vityod"]
                self.assertTrue(
                    component["source_relative_path"].startswith(
                        "products/vityo_app/native/vityod/target/release/vityod"
                    )
                )
                self.assertNotIn(
                    "..",
                    pathlib.PurePosixPath(component["package_relative_path"]).parts,
                )


    def test_staging_copies_declared_binary_and_binds_its_digest(self) -> None:
        packaging = _load_module(
            "vityo_package_nightly_acceptance",
            ROOT / "scripts" / "package-nightly.py",
        )
        with tempfile.TemporaryDirectory(prefix="vityod-acceptance-") as raw:
            tmp_path = pathlib.Path(raw)
            source = tmp_path / "source" / "vityod"
            source.parent.mkdir()
            source.write_bytes(b"fixture vityod executable\n")
            packaging.ROOT = tmp_path
            packaging.vityod_build_identity = lambda: {
                "daemon_version": "0.1.0",
                "build_source_fingerprint": "c" * 64,
                "target": "fixture-desktop",
            }
            destination_root = tmp_path / "application"
            relative = pathlib.Path("components/vityod")

            staged = packaging.stage_vityod(
                {
                    "vityod": {
                        "source_relative_path": source.relative_to(
                            tmp_path
                        ).as_posix(),
                        "package_relative_path": relative.as_posix(),
                        "target": "fixture-desktop",
                        "required_runtime_libraries": [],
                    }
                },
                destination_root,
            )

            self.assertEqual(staged, destination_root / relative)
            self.assertEqual(staged.read_bytes(), source.read_bytes())
            self.assertTrue(staged.stat().st_mode & stat.S_IXUSR)
            component = json.loads(
                (staged.parent / "vityod-component.json").read_text(
                    encoding="utf-8"
                )
            )
            self.assertEqual(
                component,
                {
                    "schema_version": 1,
                    "component": "vityod",
                    "target": "fixture-desktop",
                    "protocol_min": 1,
                    "protocol_max": 1,
                    "executable_sha256": hashlib.sha256(
                        source.read_bytes()
                    ).hexdigest(),
                    "daemon_version": "0.1.0",
                    "build_source_fingerprint": "c" * 64,
                    "required_runtime_libraries": [],
                    "package_relative_path": relative.as_posix(),
                },
            )


    def test_staging_rejects_paths_outside_the_application(self) -> None:
        packaging = _load_module(
            "vityo_package_nightly_path_acceptance",
            ROOT / "scripts" / "package-nightly.py",
        )
        with tempfile.TemporaryDirectory(prefix="vityod-path-acceptance-") as raw:
            tmp_path = pathlib.Path(raw)
            source = tmp_path / "vityod"
            source.write_bytes(b"fixture")
            packaging.ROOT = tmp_path
            packaging.vityod_build_identity = lambda: {
                "daemon_version": "0.1.0",
                "build_source_fingerprint": "c" * 64,
                "target": "fixture-desktop",
            }
            for relative in ("../vityod", "/tmp/vityod"):
                with self.subTest(relative=relative), self.assertRaisesRegex(
                    ValueError, "inside the application"
                ):
                    packaging.stage_vityod(
                        {
                            "vityod": {
                                "source_relative_path": "vityod",
                                "package_relative_path": relative,
                                "target": "fixture-desktop",
                                "required_runtime_libraries": [],
                            }
                        },
                        tmp_path / "application",
                    )

    def test_upgrade_rollback_uninstall_and_reclamation_are_safe(self) -> None:
        lifecycle = _load_module(
            "vityo_packaging_lifecycle_acceptance",
            ROOT / "packaging" / "vityo" / "lifecycle.py",
        )
        state = {
            "schema_version": 2,
            "workspace_metadata": {"workspace": "fixture", "revision": 7},
            "acknowledged_dirty_buffers": [{"document": "main.styio", "revision": 4}],
            "transaction_journal": [{"transaction": "tx-1", "status": "committed"}],
            "agent_journal": [{"session": "agent-1", "status": "idle"}],
            "settings": {"theme": "graphite"},
            "credential_references": ["ref:fixture-provider"],
        }
        original_digest = lifecycle.state_digest(state)

        committed = lifecycle.simulate_upgrade(
            state, candidate_schema_version=3
        )
        self.assertEqual(committed.status, "committed")
        self.assertEqual(committed.state["schema_version"], 3)
        self.assertEqual(committed.checkpoint_digest, original_digest)

        for result in (
            lifecycle.simulate_upgrade(state, candidate_schema_version=4),
            lifecycle.simulate_upgrade(
                state,
                candidate_schema_version=3,
                active_blockers=["pty:1"],
            ),
            lifecycle.simulate_upgrade(
                state,
                candidate_schema_version=3,
                interrupt_after_checkpoint=True,
            ),
            lifecycle.simulate_upgrade(
                state,
                candidate_schema_version=3,
                health_check_passes=False,
            ),
        ):
            with self.subTest(status=result.status, phase=result.phase):
                self.assertEqual(lifecycle.state_digest(result.state), original_digest)

        uninstalled = lifecycle.simulate_uninstall(state)
        self.assertEqual(uninstalled.status, "retained")
        self.assertEqual(lifecycle.state_digest(uninstalled.state), original_digest)

        denied = lifecycle.plan_reclamation(state, explicitly_confirmed=False)
        self.assertEqual(denied.status, "confirmation-required")
        self.assertEqual(denied.reclamation_plan, ())
        planned = lifecycle.plan_reclamation(state, explicitly_confirmed=True)
        self.assertEqual(planned.status, "planned")
        self.assertTrue(planned.reclamation_plan)
        self.assertEqual(lifecycle.state_digest(planned.state), original_digest)

    def test_lifecycle_fixture_rejects_raw_credentials(self) -> None:
        lifecycle = _load_module(
            "vityo_packaging_lifecycle_secret_acceptance",
            ROOT / "packaging" / "vityo" / "lifecycle.py",
        )
        with self.assertRaisesRegex(ValueError, "secret material"):
            lifecycle.validate_fixture_state(
                {
                    "schema_version": 1,
                    "workspace_metadata": {},
                    "acknowledged_dirty_buffers": [],
                    "transaction_journal": [],
                    "agent_journal": [],
                    "settings": {"token": "must-not-be-recorded"},
                    "credential_references": ["ref:fixture"],
                }
            )

    def test_fixture_matrix_rejects_dishonest_native_claims(self) -> None:
        matrix = _load_module(
            "vityod_matrix_dishonest_acceptance",
            ROOT / "scripts" / "vityod-desktop-matrix-gate.py",
        )
        manifest = json.loads(
            (ROOT / "packaging" / "linux" / "nightly.json").read_text(
                encoding="utf-8"
            )
        )
        fixture = json.loads(
            (
                ROOT
                / "packaging"
                / "vityo"
                / "fixtures"
                / "vityod"
                / "linux"
                / "component-manifest.json"
            ).read_text(encoding="utf-8")
        )
        fixture["native_launch"] = True
        fixture["blocked_reason"] = ""
        matrix.load_object = lambda path: (
            manifest if path.name == "nightly.json" else fixture
        )

        errors = matrix.validate_fixture("linux")

        self.assertIn("linux: fixture must not claim native launch", errors)
        self.assertIn("linux: fixture-only evidence needs a blocked reason", errors)


if __name__ == "__main__":
    unittest.main()

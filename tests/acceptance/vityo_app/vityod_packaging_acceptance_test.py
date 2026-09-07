"""Acceptance for the manifest-bound vityod desktop component."""

from __future__ import annotations

import hashlib
import importlib.util
import io
import json
import pathlib
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest import mock

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

    def test_fixture_matrix_accepts_repository_fixtures_and_rejects_non_objects(
        self,
    ) -> None:
        matrix = _load_module(
            "vityod_matrix_fixture_acceptance",
            ROOT / "scripts" / "vityod-desktop-matrix-gate.py",
        )
        for platform in matrix.PLATFORMS:
            with self.subTest(platform=platform):
                self.assertEqual(matrix.validate_fixture(platform), [])

        with tempfile.TemporaryDirectory(prefix="vityod-matrix-json-") as raw:
            path = pathlib.Path(raw) / "payload.json"
            path.write_text("[]", encoding="utf-8")
            with (
                mock.patch.object(matrix, "ROOT", pathlib.Path(raw)),
                self.assertRaisesRegex(ValueError, "must contain an object"),
            ):
                matrix.load_object(path)

    def test_matrix_framing_supports_socket_and_file_transports(self) -> None:
        matrix = _load_module(
            "vityod_matrix_framing_acceptance",
            ROOT / "scripts" / "vityod-desktop-matrix-gate.py",
        )
        response = json.dumps(
            {"method": "handshake.negotiate.result"}, separators=(",", ":")
        ).encode("utf-8")
        frame = struct.pack(">HBBIQI4x", 1, 1, 0, 0, 1, len(response)) + response

        class SocketConnection:
            def __init__(self, data: bytes) -> None:
                self.data = bytearray(data)
                self.sent = b""

            def sendall(self, payload: bytes) -> None:
                self.sent += payload

            def recv(self, length: int) -> bytes:
                chunk = bytes(self.data[: min(length, 7)])
                del self.data[: len(chunk)]
                return chunk

        socket_connection = SocketConnection(frame)
        matrix._exchange_handshake(socket_connection, "socket-client")
        self.assertTrue(socket_connection.sent)
        self.assertEqual(
            json.loads(matrix._handshake_payload("socket-client"))["clientInstanceId"],
            "socket-client",
        )

        class FileConnection:
            def __init__(self, data: bytes) -> None:
                self.reader = io.BytesIO(data)
                self.writer = io.BytesIO()
                self.flushed = False

            def read(self, length: int) -> bytes:
                return self.reader.read(length)

            def write(self, payload: bytes) -> None:
                self.writer.write(payload)

            def flush(self) -> None:
                self.flushed = True

        file_connection = FileConnection(frame)
        matrix._exchange_handshake(file_connection, "file-client")
        self.assertTrue(file_connection.flushed)

        for invalid in (
            struct.pack(">HBBIQI4x", 1, 2, 0, 0, 1, 0),
            struct.pack(">HBBIQI4x", 1, 1, 0, 0, 1, 2 * 1024 * 1024),
        ):
            with self.subTest(header=invalid), self.assertRaisesRegex(
                RuntimeError, "invalid handshake frame"
            ):
                matrix._exchange_handshake(SocketConnection(invalid), "invalid")

        rejected = json.dumps({"method": "handshake.rejected"}).encode("utf-8")
        rejected_frame = (
            struct.pack(">HBBIQI4x", 1, 1, 0, 0, 1, len(rejected)) + rejected
        )
        with self.assertRaisesRegex(RuntimeError, "rejected"):
            matrix._exchange_handshake(SocketConnection(rejected_frame), "rejected")
        with self.assertRaisesRegex(RuntimeError, "closed"):
            matrix._read_exact(SocketConnection(b""), 1)

    def test_matrix_uses_platform_transport_and_cleans_up_probe(self) -> None:
        matrix = _load_module(
            "vityod_matrix_transport_acceptance",
            ROOT / "scripts" / "vityod-desktop-matrix-gate.py",
        )

        class FakeSocket:
            def __enter__(self):
                return self

            def __exit__(self, *_args: object) -> None:
                return None

            def settimeout(self, timeout: int) -> None:
                self.timeout = timeout

            def connect(self, endpoint: str) -> None:
                self.endpoint = endpoint

        fake_socket = FakeSocket()
        with (
            mock.patch.object(matrix.os, "name", "posix"),
            mock.patch.object(matrix.socket, "socket", return_value=fake_socket),
            mock.patch.object(matrix, "_exchange_handshake") as exchange,
        ):
            matrix._handshake("service.sock", "client")
        exchange.assert_called_once_with(fake_socket, "client")

        file_connection = mock.MagicMock()
        file_connection.__enter__.return_value = file_connection
        with (
            mock.patch.object(matrix.os, "name", "nt"),
            mock.patch("builtins.open", return_value=file_connection) as opened,
            mock.patch.object(matrix, "_exchange_handshake") as exchange,
        ):
            matrix._handshake(r"\\.\pipe\vityod", "windows-client")
        opened.assert_called_once_with(r"\\.\pipe\vityod", "r+b", buffering=0)
        exchange.assert_called_once_with(file_connection, "windows-client")

        process = mock.Mock()
        process.poll.return_value = None
        with (
            mock.patch.object(matrix.os, "name", "posix"),
            mock.patch.object(pathlib.Path, "exists", return_value=True),
            mock.patch.object(matrix.subprocess, "Popen", return_value=process),
            mock.patch.object(matrix, "_handshake") as handshake,
        ):
            self.assertEqual(
                matrix._probe_reconnect(pathlib.Path("vityod")),
                (True, "two authenticated client handshakes completed"),
            )
        self.assertEqual(handshake.call_count, 2)
        process.terminate.assert_called_once()
        process.wait.assert_called_once_with(timeout=3)

        failed_process = mock.Mock()
        failed_process.poll.return_value = None
        failed_process.wait.side_effect = [subprocess.TimeoutExpired("vityod", 3), 0]
        with (
            mock.patch.object(matrix.os, "name", "posix"),
            mock.patch.object(pathlib.Path, "exists", return_value=True),
            mock.patch.object(matrix.subprocess, "Popen", return_value=failed_process),
            mock.patch.object(matrix, "_handshake", side_effect=RuntimeError("probe failed")),
        ):
            self.assertEqual(
                matrix._probe_reconnect(pathlib.Path("vityod")),
                (False, "probe failed"),
            )
        failed_process.kill.assert_called_once()

    def test_native_component_validation_covers_identity_and_health(self) -> None:
        matrix = _load_module(
            "vityod_matrix_native_acceptance",
            ROOT / "scripts" / "vityod-desktop-matrix-gate.py",
        )
        with tempfile.TemporaryDirectory(prefix="vityod-native-component-") as raw:
            root = pathlib.Path(raw)
            application = root / "application"
            binary = application / "components" / "vityod"
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b"vityod binary")
            package_root = root / "packaging" / "linux"
            package_root.mkdir(parents=True)
            component = {
                "target": "native-linux",
                "package_relative_path": "components/vityod",
                "required_runtime_libraries": [],
            }
            (package_root / "nightly.json").write_text(
                json.dumps({"vityod": component}), encoding="utf-8"
            )
            identity_path = binary.parent / "vityod-component.json"
            identity = {
                "schema_version": 1,
                "component": "vityod",
                "protocol_min": 1,
                "protocol_max": 1,
                "package_relative_path": "components/vityod",
                "required_runtime_libraries": [],
                "executable_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                "target": "native-linux",
                "daemon_version": "0.1.0",
                "build_source_fingerprint": "a" * 64,
            }
            identity_path.write_text(json.dumps(identity), encoding="utf-8")
            health = mock.Mock(
                returncode=0,
                stdout=json.dumps(
                    {
                        "component": "vityod",
                        "status": "ready",
                        "protocolVersion": 1,
                    }
                ),
            )
            with (
                mock.patch.object(matrix, "ROOT", root),
                mock.patch.object(matrix.subprocess, "run", return_value=health),
                mock.patch.object(matrix, "_probe_reconnect", return_value=(True, "ok")),
            ):
                self.assertEqual(
                    matrix.validate_native_component("linux", application), []
                )

                invalid = dict(identity)
                invalid.update(
                    {
                        "schema_version": 2,
                        "target": "wrong-target",
                        "daemon_version": "bad version",
                        "build_source_fingerprint": "z",
                        "executable_sha256": "wrong",
                    }
                )
                identity_path.write_text(json.dumps(invalid), encoding="utf-8")
                health.returncode = 1
                with mock.patch.object(
                    matrix, "_probe_reconnect", return_value=(False, "reconnect failed")
                ):
                    errors = matrix.validate_native_component("linux", application)
                self.assertTrue(any("schema_version" in error for error in errors))
                self.assertTrue(any("target" in error for error in errors))
                self.assertTrue(any("daemon version" in error for error in errors))
                self.assertTrue(any("source fingerprint" in error for error in errors))
                self.assertTrue(any("health check" in error for error in errors))
                self.assertTrue(any("reconnect failed" in error for error in errors))

                (package_root / "nightly.json").write_text("{}", encoding="utf-8")
                self.assertIn(
                    "no vityod component",
                    matrix.validate_native_component("linux", application)[0],
                )

            (package_root / "nightly.json").write_text(
                json.dumps({"vityod": component}), encoding="utf-8"
            )
            identity_path.unlink()
            with mock.patch.object(matrix, "ROOT", root):
                self.assertIn(
                    "exactly one component manifest",
                    matrix.validate_native_component("linux", application)[0],
                )
            identity_path.write_text(json.dumps(identity), encoding="utf-8")
            binary.unlink()
            with mock.patch.object(matrix, "ROOT", root):
                self.assertIn(
                    "executable is missing",
                    matrix.validate_native_component("linux", application)[0],
                )

    def test_matrix_main_reports_fixture_and_native_lane_results(self) -> None:
        matrix = _load_module(
            "vityod_matrix_main_acceptance",
            ROOT / "scripts" / "vityod-desktop-matrix-gate.py",
        )
        contract = {"component": {"name": "vityod"}}
        stdout = io.StringIO()
        with (
            mock.patch.object(sys, "argv", [str(matrix.__file__), "--fixtures-only"]),
            mock.patch.object(matrix, "load_object", return_value=contract),
            mock.patch.object(matrix, "validate_fixture", return_value=[]),
            redirect_stdout(stdout),
        ):
            self.assertEqual(matrix.main(), 0)
        payload = json.loads(stdout.getvalue())
        self.assertEqual(payload["mode"], "fixtures-only")
        self.assertEqual(len(payload["lanes"]), 3)

        for argv in (
            [str(matrix.__file__)],
            [str(matrix.__file__), "--fixtures-only", "--platform", "linux"],
        ):
            with (
                self.subTest(argv=argv),
                mock.patch.object(sys, "argv", argv),
                redirect_stderr(io.StringIO()),
                self.assertRaises(SystemExit),
            ):
                matrix.main()

        stdout = io.StringIO()
        with (
            mock.patch.object(
                sys,
                "argv",
                [
                    str(matrix.__file__),
                    "--platform",
                    "windows",
                    "--application-root",
                    ".",
                ],
            ),
            mock.patch.object(matrix.sys, "platform", "linux"),
            mock.patch.object(matrix, "load_object", return_value=contract),
            redirect_stdout(stdout),
        ):
            self.assertEqual(matrix.main(), 1)
        self.assertIn("matching host", stdout.getvalue())

        stdout = io.StringIO()
        with (
            mock.patch.object(
                sys,
                "argv",
                [
                    str(matrix.__file__),
                    "--platform",
                    "linux",
                    "--application-root",
                    ".",
                ],
            ),
            mock.patch.object(matrix.sys, "platform", "linux"),
            mock.patch.object(matrix, "load_object", return_value=contract),
            mock.patch.object(matrix, "validate_native_component", return_value=[]),
            redirect_stdout(stdout),
        ):
            self.assertEqual(matrix.main(), 0)
        self.assertEqual(json.loads(stdout.getvalue())["mode"], "native")

    def test_packaging_build_identity_and_native_build_contract(self) -> None:
        packaging = _load_module(
            "vityo_package_identity_acceptance",
            ROOT / "scripts" / "package-nightly.py",
        )
        rustc = mock.Mock(stdout="rustc 1.90.0\nhost: aarch64-apple-darwin\n")
        with mock.patch.object(packaging.subprocess, "run", return_value=rustc):
            identity = packaging.vityod_build_identity()
        self.assertEqual(identity["target"], "aarch64-apple-darwin")
        self.assertEqual(len(identity["build_source_fingerprint"]), 64)
        self.assertTrue(
            packaging.vityod_target_matches(
                "native-apple-darwin", "aarch64-apple-darwin"
            )
        )
        self.assertFalse(packaging.vityod_target_matches("native-linux", "windows"))

        with (
            mock.patch.object(
                packaging.tomllib,
                "loads",
                return_value={"workspace": {"package": {"version": "invalid"}}},
            ),
            self.assertRaisesRegex(ValueError, "version is invalid"),
        ):
            packaging.vityod_build_identity()
        with (
            mock.patch.object(packaging.subprocess, "run", return_value=mock.Mock(stdout="")),
            self.assertRaisesRegex(ValueError, "host target is invalid"),
        ):
            packaging.vityod_build_identity()

        self.assertIsNone(packaging.build_vityod({}))
        with self.assertRaisesRegex(ValueError, "must be an object"):
            packaging.build_vityod({"vityod": "invalid"})
        with tempfile.TemporaryDirectory(prefix="vityod-build-") as raw:
            root = pathlib.Path(raw)
            manifest = root / "products/vityo_app/native/vityod/Cargo.toml"
            manifest.parent.mkdir(parents=True)
            manifest.write_text("[workspace]\n", encoding="utf-8")
            binary = root / "target/vityod"
            binary.parent.mkdir()
            binary.write_bytes(b"binary")
            config = {
                "vityod": {
                    "target": "native-linux",
                    "source_relative_path": "target/vityod",
                }
            }
            with (
                mock.patch.object(packaging, "ROOT", root),
                mock.patch.object(
                    packaging,
                    "vityod_build_identity",
                    return_value={"target": "native-linux"},
                ),
                mock.patch.object(packaging.subprocess, "run") as run,
            ):
                self.assertEqual(packaging.build_vityod(config), binary)
            run.assert_called_once()
            with (
                mock.patch.object(packaging, "ROOT", root),
                mock.patch.object(
                    packaging,
                    "vityod_build_identity",
                    return_value={"target": "native-windows"},
                ),
                self.assertRaisesRegex(ValueError, "does not match"),
            ):
                packaging.build_vityod(config)

    def test_packaging_rejects_runtime_library_drift_and_stages_macos(self) -> None:
        packaging = _load_module(
            "vityo_package_runtime_acceptance",
            ROOT / "scripts" / "package-nightly.py",
        )
        with tempfile.TemporaryDirectory(prefix="vityod-package-runtime-") as raw:
            root = pathlib.Path(raw)
            source = root / "vityod"
            source.write_bytes(b"binary")
            destination = root / "application"
            invalid = {
                "vityod": {
                    "source_relative_path": "vityod",
                    "package_relative_path": "components/vityod",
                    "required_runtime_libraries": "invalid",
                }
            }
            with (
                mock.patch.object(packaging, "ROOT", root),
                mock.patch.object(
                    packaging,
                    "vityod_build_identity",
                    return_value={
                        "daemon_version": "0.1.0",
                        "build_source_fingerprint": "a" * 64,
                        "target": "native-linux",
                    },
                ),
                self.assertRaisesRegex(ValueError, "string list"),
            ):
                packaging.stage_vityod(invalid, destination)

            app = root / "Vityo.app"
            app.mkdir()
            (app / "Vityo").write_text("app", encoding="utf-8")
            script = root / "package.sh"
            script.write_text("#!/bin/sh\n", encoding="utf-8")
            config = {
                "build_relative_path": "Vityo.app",
                "installer_definition": "package.sh",
            }
            output = root / "Vityo.dmg"
            with (
                mock.patch.object(packaging, "ROOT", root),
                mock.patch.object(packaging.subprocess, "run") as run,
            ):
                self.assertEqual(packaging.package_macos(config, output), output)
                config["vityod"] = {"component": "vityod"}
                with mock.patch.object(packaging, "stage_vityod") as stage:
                    self.assertEqual(packaging.package_macos(config, output), output)
                stage.assert_called_once()
            self.assertEqual(run.call_count, 2)

    def test_packaging_main_writes_component_bound_evidence(self) -> None:
        packaging = _load_module(
            "vityo_package_main_acceptance",
            ROOT / "scripts" / "package-nightly.py",
        )
        with tempfile.TemporaryDirectory(prefix="vityod-package-main-") as raw:
            output_root = pathlib.Path(raw)
            binary = output_root / "vityod"
            binary.write_bytes(b"binary")
            config = {
                "vityod": {"package_relative_path": "components/vityod"},
                "signing": {"status": "configured"},
                "automatic_updates": True,
            }
            versions = {"core_version": "1.0.0"}
            expected = output_root / "vityo-nightly-linux-1.2.3.deb"
            expected.write_bytes(b"old")
            stdout = io.StringIO()
            with (
                mock.patch.object(
                    sys,
                    "argv",
                    [
                        str(packaging.__file__),
                        "--platform",
                        "linux",
                        "--output-dir",
                        str(output_root),
                    ],
                ),
                mock.patch.object(packaging, "load_json", side_effect=[config, versions]),
                mock.patch.object(
                    packaging, "validate_release_inputs", return_value="1.2.3"
                ),
                mock.patch.object(packaging, "build_vityod", return_value=binary),
                mock.patch.object(packaging, "package_linux") as package_linux,
                mock.patch.object(
                    packaging,
                    "vityod_build_identity",
                    return_value={
                        "daemon_version": "0.1.0",
                        "build_source_fingerprint": "a" * 64,
                        "target": "native-linux",
                    },
                ),
                redirect_stdout(stdout),
            ):
                self.assertEqual(packaging.main(), 0)
            package_linux.assert_called_once_with(config, expected, "1.2.3")
            evidence = json.loads(
                expected.with_suffix(".deb.json").read_text(encoding="utf-8")
            )
            self.assertEqual(evidence["vityod"]["package_relative_path"], "components/vityod")
            self.assertEqual(stdout.getvalue().strip(), str(expected))


if __name__ == "__main__":
    unittest.main()

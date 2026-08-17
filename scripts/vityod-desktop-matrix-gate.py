#!/usr/bin/env python3
"""Validate Vityo desktop packages bind one truthful vityod component."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import secrets
import socket
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PLATFORMS = ("linux", "macos", "windows")
FINGERPRINT_LENGTH = 64


def load_object(path: Path) -> dict[str, object]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"{path.relative_to(ROOT)} must contain an object")
    return payload


def validate_fixture(platform: str) -> list[str]:
    errors: list[str] = []
    manifest = load_object(ROOT / "packaging" / platform / "nightly.json")
    fixture = load_object(
        ROOT
        / "packaging"
        / "vityo"
        / "fixtures"
        / "vityod"
        / platform
        / "component-manifest.json"
    )
    component = manifest.get("vityod")
    if not isinstance(component, dict):
        return [f"{platform}: package manifest has no vityod component"]
    if fixture.get("schema_version") != 1 or fixture.get("fixture_only") is not True:
        errors.append(f"{platform}: fixture identity is invalid")
    for key in ("target", "package_relative_path"):
        if fixture.get(key) != component.get(key):
            errors.append(f"{platform}: fixture {key} does not match package contract")
    if fixture.get("required_runtime_libraries") != component.get(
        "required_runtime_libraries"
    ):
        errors.append(f"{platform}: fixture runtime libraries do not match package contract")
    if fixture.get("protocol_min") != 1 or fixture.get("protocol_max") != 1:
        errors.append(f"{platform}: fixture protocol range is invalid")
    for key in ("executable_sha256", "build_source_fingerprint"):
        value = str(fixture.get(key, ""))
        if len(value) != FINGERPRINT_LENGTH or any(
            character not in "0123456789abcdef" for character in value
        ):
            errors.append(f"{platform}: fixture {key} is invalid")
    if fixture.get("component") != "vityod":
        errors.append(f"{platform}: fixture component must be vityod")
    if fixture.get("native_launch") is not False:
        errors.append(f"{platform}: fixture must not claim native launch")
    if not str(fixture.get("blocked_reason", "")).strip():
        errors.append(f"{platform}: fixture-only evidence needs a blocked reason")
    return errors


def _read_exact(connection: object, length: int) -> bytes:
    chunks: list[bytes] = []
    remaining = length
    while remaining:
        if hasattr(connection, "recv"):
            chunk = connection.recv(remaining)
        else:
            chunk = connection.read(remaining)
        if not chunk:
            raise RuntimeError("daemon closed the reconnect probe")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def _handshake_payload(client_id: str) -> bytes:
    envelope = {
        "protocolVersion": 1,
        "method": "handshake.negotiate",
        "requestId": f"{client_id}-request",
        "clientInstanceId": client_id,
        "idempotencyKey": f"{client_id}-handshake",
        "deadlineUnixMillis": int(time.time() * 1000) + 5000,
        "params": {
            "requiredCapabilities": ["event.resume", "workspace.snapshot"]
        },
        "capabilities": [],
    }
    return json.dumps(envelope, separators=(",", ":")).encode("utf-8")


def _exchange_handshake(connection: object, client_id: str) -> None:
    payload = _handshake_payload(client_id)
    header = struct.pack(">HBBIQI4x", 1, 1, 0, 0, 1, len(payload))
    if hasattr(connection, "sendall"):
        connection.sendall(header + payload)
    else:
        connection.write(header + payload)
        connection.flush()
    response_header = _read_exact(connection, 24)
    version, kind, _flags, _stream, _sequence, length = struct.unpack(
        ">HBBIQI4x", response_header
    )
    if version != 1 or kind != 1 or length > 1024 * 1024:
        raise RuntimeError("daemon returned an invalid handshake frame")
    response = json.loads(_read_exact(connection, length))
    if response.get("method") != "handshake.negotiate.result":
        raise RuntimeError("daemon rejected the packaged handshake")


def _handshake(endpoint: str, client_id: str) -> None:
    if os.name == "nt":
        with open(endpoint, "r+b", buffering=0) as connection:
            _exchange_handshake(connection, client_id)
        return
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(5)
        connection.connect(endpoint)
        _exchange_handshake(connection, client_id)


def _probe_reconnect(binary: Path) -> tuple[bool, str]:
    with tempfile.TemporaryDirectory(prefix="vityod-native-probe-") as raw:
        endpoint = (
            rf"\\.\pipe\vityod-package-{os.getpid()}-{secrets.token_hex(6)}"
            if os.name == "nt"
            else str(Path(raw) / "service.sock")
        )
        process = subprocess.Popen(
            [binary, "--serve", "--endpoint", endpoint],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            deadline = time.monotonic() + 5
            if os.name == "nt":
                while process.poll() is None:
                    try:
                        _handshake(endpoint, "package-probe-1")
                        break
                    except OSError:
                        if time.monotonic() >= deadline:
                            return False, "packaged daemon endpoint did not become ready"
                        time.sleep(0.025)
                else:
                    return False, "packaged daemon exited before reconnect validation"
            else:
                endpoint_path = Path(endpoint)
                while not endpoint_path.exists() and process.poll() is None:
                    if time.monotonic() >= deadline:
                        return False, "packaged daemon endpoint did not become ready"
                    time.sleep(0.025)
            if process.poll() is not None:
                return False, "packaged daemon exited before reconnect validation"
            if os.name != "nt":
                _handshake(endpoint, "package-probe-1")
            _handshake(endpoint, "package-probe-2")
            return True, "two authenticated client handshakes completed"
        except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
            return False, str(error)
        finally:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=3)


def validate_native_component(platform: str, application_root: Path) -> list[str]:
    errors: list[str] = []
    package = load_object(ROOT / "packaging" / platform / "nightly.json")
    component = package.get("vityod")
    if not isinstance(component, dict):
        return [f"{platform}: package manifest has no vityod component"]
    relative = Path(str(component.get("package_relative_path", "")))
    binary = application_root / relative
    manifests = list(application_root.rglob("vityod-component.json"))
    if len(manifests) != 1:
        errors.append(f"{platform}: package must contain exactly one component manifest")
        return errors
    if not binary.is_file():
        errors.append(f"{platform}: declared vityod executable is missing")
        return errors
    identity = load_object(manifests[0])
    expected_digest = hashlib.sha256(binary.read_bytes()).hexdigest()
    expected_fields = {
        "schema_version": 1,
        "component": "vityod",
        "protocol_min": 1,
        "protocol_max": 1,
        "package_relative_path": relative.as_posix(),
        "required_runtime_libraries": component.get("required_runtime_libraries"),
        "executable_sha256": expected_digest,
    }
    for key, expected in expected_fields.items():
        if identity.get(key) != expected:
            errors.append(f"{platform}: component {key} does not match the package")
    actual_target = str(identity.get("target", ""))
    declared_target = str(component.get("target", ""))
    target_matches = actual_target == declared_target or (
        declared_target == "native-apple-darwin"
        and actual_target.endswith("-apple-darwin")
    )
    if not target_matches:
        errors.append(f"{platform}: component target does not match the package")
    daemon_version = str(identity.get("daemon_version", ""))
    if not daemon_version or any(character.isspace() for character in daemon_version):
        errors.append(f"{platform}: daemon version is invalid")
    source_fingerprint = str(identity.get("build_source_fingerprint", ""))
    if len(source_fingerprint) != FINGERPRINT_LENGTH or any(
        character not in "0123456789abcdef" for character in source_fingerprint
    ):
        errors.append(f"{platform}: daemon source fingerprint is invalid")
    health = subprocess.run(
        [binary, "--health"],
        check=False,
        capture_output=True,
        text=True,
        timeout=5,
    )
    try:
        health_payload = json.loads(health.stdout) if health.returncode == 0 else {}
    except json.JSONDecodeError:
        health_payload = {}
    if (
        health_payload.get("component") != "vityod"
        or health_payload.get("status") != "ready"
        or health_payload.get("protocolVersion") != 1
    ):
        errors.append(f"{platform}: packaged daemon health check failed")
    reconnect_ok, reconnect_reason = _probe_reconnect(binary)
    if not reconnect_ok:
        errors.append(f"{platform}: {reconnect_reason}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixtures-only", action="store_true")
    parser.add_argument("--platform", choices=PLATFORMS)
    parser.add_argument("--application-root", type=Path)
    args = parser.parse_args()
    if args.fixtures_only and (args.platform or args.application_root):
        parser.error("--fixtures-only cannot be combined with a native lane")
    if not args.fixtures_only and (args.platform is None or args.application_root is None):
        parser.error("use --fixtures-only or provide --platform and --application-root")
    errors: list[str] = []
    contract = load_object(ROOT / "packaging" / "vityo" / "desktop-delivery.json")
    if contract.get("component", {}).get("name") != "vityod":
        errors.append("desktop delivery component must be vityod")
    if args.fixtures_only:
        for platform in PLATFORMS:
            errors.extend(validate_fixture(platform))
        lanes = [
            {"platform": platform, "status": "fixture-only"}
            for platform in PLATFORMS
        ]
        mode = "fixtures-only"
    else:
        host = {"darwin": "macos", "linux": "linux", "win32": "windows"}.get(
            sys.platform, sys.platform
        )
        if host != args.platform:
            errors.append(f"{args.platform}: native evidence requires a matching host")
        else:
            errors.extend(
                validate_native_component(args.platform, args.application_root.resolve())
            )
        lanes = [
            {
                "platform": args.platform,
                "status": "passed" if not errors else "failed",
            }
        ]
        mode = "native"
    payload = {
        "ok": not errors,
        "mode": mode,
        "lanes": lanes,
        "errors": errors,
    }
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())

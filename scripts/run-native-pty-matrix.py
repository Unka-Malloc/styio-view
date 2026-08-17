#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path


CAPABILITY = "desktop-native-pty"
PORTABLE_PTY_VERSION = "0.9.0"
PORTABLE_PTY_REQUIREMENT = "0.9"
SCENARIOS = (
    "tty-identity",
    "child-observed-resize",
    "forced-process-close",
    "terminal-environment-propagation",
)
PROVIDERS = {
    "linux": "forkpty",
    "macos": "forkpty",
    "windows": "conpty",
}


def host_platform() -> str | None:
    if sys.platform.startswith("linux"):
        return "linux"
    if sys.platform == "darwin":
        return "macos"
    if sys.platform == "win32":
        return "windows"
    return None


def git_head(repository: Path) -> str:
    return subprocess.run(
        ["git", "-C", str(repository), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()


def require_pinned_pty_dependency(app_root: Path) -> None:
    daemon_root = app_root / "native" / "vityod"
    manifest = (daemon_root / "Cargo.toml").read_text(encoding="utf-8")
    lock = (daemon_root / "Cargo.lock").read_text(encoding="utf-8")
    if re.search(
        rf'^portable-pty\s*=\s*"{re.escape(PORTABLE_PTY_REQUIREMENT)}"\s*$',
        manifest,
        re.MULTILINE,
    ) is None:
        raise ValueError(
            f"portable-pty must be pinned to {PORTABLE_PTY_REQUIREMENT}"
        )
    locked = rf'name = "portable-pty"\nversion = "{re.escape(PORTABLE_PTY_VERSION)}"'
    if re.search(locked, lock) is None:
        raise ValueError(
            f"portable-pty lock must resolve exactly to {PORTABLE_PTY_VERSION}"
        )


def run_matrix(*, flutter: str, app_root: Path) -> None:
    flutter_executable = shutil.which(flutter)
    if flutter_executable is None:
        raise ValueError(f"Flutter executable is unavailable: {flutter}")
    commands = (
        [flutter_executable, "test", "test/pty_manager_test.dart"],
        [
            flutter_executable,
            "test",
            "test/configuration_toolchain_test.dart",
            "--plain-name",
            "terminal runtime starts configured shell through pty manager",
        ],
    )
    for command in commands:
        subprocess.run(command, cwd=app_root, check=True)


def build_report(*, platform: str, vityo_commit: str) -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "capability": CAPABILITY,
        "platform": platform,
        "provider": PROVIDERS[platform],
        "ptyDependency": {
            "name": "portable-pty",
            "version": PORTABLE_PTY_VERSION,
            "owner": "vityod",
        },
        "vityoCommit": vityo_commit,
        "ok": True,
        "scenarios": [
            {"id": scenario, "status": "passed"} for scenario in SCENARIOS
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", choices=tuple(PROVIDERS), required=True)
    parser.add_argument("--vityo", type=Path, default=Path("."))
    parser.add_argument("--flutter", default="flutter")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    actual_platform = host_platform()
    if actual_platform != args.platform:
        parser.error(
            f"declared platform {args.platform!r} does not match host {actual_platform!r}"
        )

    app_root = args.vityo / "products" / "vityo_app"
    require_pinned_pty_dependency(app_root)
    run_matrix(flutter=args.flutter, app_root=app_root)
    report = build_report(
        platform=args.platform,
        vityo_commit=git_head(args.vityo),
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(report, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

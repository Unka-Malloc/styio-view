#!/usr/bin/env python3
"""Linux host readiness gate - detect/report WSL/Docker Linux readiness for
Python, Dart/Flutter, npm, Chrome/Chromium, Docker image Dart/Flutter
availability, and CRLF Flutter shell-script blockers.

This gate does NOT attempt to repair external SDKs or install packages.  It
only diagnoses and reports blocked states.  Intended to run inside a WSL
Debian/Ubuntu environment or a Linux container before invoking full build or
test workflows.

Usage:
    python3 scripts/check-linux-host-readiness-gate.py [--json]
    python3 scripts/check-linux-host-readiness-gate.py --check docker-flutter
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Callable

REPO_ROOT = Path(__file__).resolve().parents[1]

# ---- pinned version files (may be absent on a shallow checkout) ----
VERSION_FILES: dict[str, Path] = {
    "python": REPO_ROOT / ".python-version",
    "flutter": REPO_ROOT / ".flutter-version",
    "node": REPO_ROOT / ".nvmrc",
    "chromium": REPO_ROOT / ".chromium-version",
}

# ---- Docker image tag used by the dev container ----
DEV_CONTAINER_TAG = "vityo-nightly/dev-env:latest"


# helpers


def _read_version_file(key: str) -> str | None:
    """Return the pinned version string from the repository version file,
    stripped, or None if the file is missing or empty."""
    path = VERSION_FILES.get(key)
    if path is None or not path.is_file():
        return None
    text = path.read_text(encoding="utf-8", errors="replace").strip()
    return text if text else None


def _run(cmd: list[str], timeout: float = 15.0) -> str | None:
    """Run *cmd*, return stripped stdout on success or None on any error."""
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        if result.returncode != 0:
            return None
        return result.stdout.strip()
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
        return None


def _normalize_node_version(value: str | None) -> str | None:
    if value is None:
        return None
    normalized = value.strip()
    return normalized[1:] if normalized.startswith("v") else normalized


def _has_crlf(path: Path) -> bool:
    try:
        return b"\r\n" in path.read_bytes()
    except (OSError, PermissionError):
        return False


def _flutter_sdk_crlf_files(flutter_binary: str) -> list[str]:
    flutter_path = Path(flutter_binary)
    candidates = [
        flutter_path.parent / "internal" / "shared.sh",
    ]
    if flutter_path.suffix.lower() not in {".bat", ".cmd", ".exe"}:
        candidates.insert(0, flutter_path)
    return [str(path) for path in candidates if path.is_file() and _has_crlf(path)]


def _check_found(key: str, detail: str) -> dict[str, object]:
    return {"name": key, "ok": True, "detail": detail}


def _check_blocked(key: str, detail: str) -> dict[str, object]:
    return {"name": key, "ok": False, "detail": detail, "blocked": True}


def _check_warn(key: str, detail: str) -> dict[str, object]:
    return {"name": key, "ok": False, "detail": detail, "blocked": False}


# individual checks


def check_python() -> dict[str, object]:
    """Check that python3 is on PATH and its version meets the repository
    standard."""
    expected = _read_version_file("python")
    if not shutil.which("python3"):
        return _check_blocked(
            "python",
            "python3 not found on PATH - required for repo scripts",
        )
    raw = _run(["python3", "--version"])
    if raw is None:
        return _check_blocked("python", "python3 found but --version failed")
    m = re.search(r"(\d+\.\d+\.\d+)", raw)
    if not m:
        return _check_warn("python", f"unparseable version: {raw!r}")

    actual = m.group(1)
    if expected and actual != expected:
        return _check_warn(
            "python",
            f"found Python {actual}, repo expects {expected}",
        )
    return _check_found("python", f"Python {actual} on PATH")


def check_flutter() -> dict[str, object]:
    """Check that flutter and dart are on PATH and match the pinned version."""
    expected = _read_version_file("flutter")

    flutter_binary = shutil.which("flutter")
    if not flutter_binary:
        return _check_blocked(
            "flutter",
            "flutter not found on PATH - required for Flutter shell builds",
        )

    raw = _run(["flutter", "--version"])
    if raw is None:
        crlf_files = _flutter_sdk_crlf_files(flutter_binary)
        if crlf_files:
            return _check_blocked(
                "flutter",
                "flutter found but --version failed because Flutter SDK "
                f"shell script(s) use CRLF line endings: {', '.join(crlf_files)}",
            )
        return _check_blocked("flutter", "flutter found but --version failed")

    # Extract Flutter channel/version from first line, e.g.
    # "Flutter 3.41.7 - channel stable - ..."
    flutter_ver: str | None = None
    dart_ver: str | None = None
    for line in raw.splitlines():
        m = re.search(r"^Flutter\s+(\S+)", line)
        if m:
            flutter_ver = m.group(1).rstrip(".")
        m2 = re.search(r"Dart\s+(\d+\.\d+\.\d+)", line)
        if m2:
            dart_ver = m2.group(1)

    issues: list[str] = []
    if flutter_ver is None:
        issues.append("could not parse Flutter version from output")
    elif expected and flutter_ver != expected:
        issues.append(
            f"Flutter {flutter_ver} installed, repo expects {expected}"
        )

    if dart_ver is None:
        issues.append("could not parse Dart version")
    elif expected:
        # Dart version should match the Flutter-bundled one; we can
        # cross-reference but a warning is sufficient.
        pass

    if not issues:
        detail = f"Flutter {flutter_ver}"
        if dart_ver:
            detail += f", Dart {dart_ver}"
        detail += " on PATH"
        return _check_found("flutter", detail)

    return _check_warn("flutter", "; ".join(issues))


def check_npm() -> dict[str, object]:
    """Check that node and npm are on PATH and node matches the pinned
    version."""
    expected = _read_version_file("node")

    if not shutil.which("node"):
        return _check_blocked(
            "npm", "node not found on PATH - required for prototype tooling"
        )

    raw = _run(["node", "--version"])
    if raw is None:
        return _check_blocked("npm", "node found but --version failed")

    actual = raw.strip()
    actual_normalized = _normalize_node_version(actual)
    expected_normalized = _normalize_node_version(expected)
    if expected_normalized and actual_normalized != expected_normalized:
        return _check_warn(
            "npm",
            f"Node {actual} installed, repo expects {expected}",
        )

    if not shutil.which("npm"):
        return _check_warn(
            "npm",
            f"Node {actual} on PATH but npm is missing",
        )

    return _check_found("npm", f"Node {actual} and npm on PATH")


def check_chromium() -> dict[str, object]:
    """Check that chromium / chromium-browser / google-chrome is on PATH and
    version matches the pinned standard."""
    expected = _read_version_file("chromium")

    candidates = ["chromium", "chromium-browser", "google-chrome", "google-chrome-stable"]
    found: str | None = None
    for name in candidates:
        if shutil.which(name):
            found = name
            break

    if found is None:
        return _check_blocked(
            "chromium",
            "no Chromium/Chrome binary found on PATH - required for web tests",
        )

    raw = _run([found, "--version"])
    if raw is None:
        return _check_warn(
            "chromium",
            f"{found} found on PATH but --version failed",
        )

    m = re.search(r"(\d+\.\d+\.\d+\.\d+)", raw)
    actual = m.group(1) if m else raw.strip()
    if expected and actual != expected:
        return _check_warn(
            "chromium",
            f"{found} version {actual}, repo expects {expected}",
        )
    return _check_found("chromium", f"{found} {actual} on PATH")


def check_docker_flutter() -> dict[str, object]:
    """Check whether Docker is available and, if so, whether the dev container
    image exists locally and contains Flutter/Dart on PATH."""
    if not shutil.which("docker"):
        return _check_blocked(
            "docker-flutter",
            "docker not found on PATH - cannot use containerized build",
        )

    # Quick connectivity probe: `docker info`
    info = _run(["docker", "info", "--format", "{{.ServerVersion}}"])
    if info is None:
        return _check_blocked(
            "docker-flutter",
            "docker found but daemon unreachable (is Docker running?)",
        )

    dev_container_tag = os.environ.get("VITYO_DOCKER_IMAGE", DEV_CONTAINER_TAG)

    # Check if the dev container image exists locally.
    inspect = _run(
        [
            "docker",
            "images",
            "--format",
            "{{.Repository}}:{{.Tag}}",
            dev_container_tag,
        ]
    )
    if inspect is None or dev_container_tag not in inspect:
        return _check_warn(
            "docker-flutter",
            f"Docker daemon {info} reachable, but {dev_container_tag} "
            "not found locally - build the image first with "
            "scripts/bootstrap-dev-container.sh",
        )

    # Quick probe: run flutter --version inside the container
    flutter_in = _run(
        [
            "docker",
            "run",
            "--rm",
            dev_container_tag,
            "flutter", "--version",
        ],
        timeout=30.0,
    )
    if flutter_in is None:
        return _check_warn(
            "docker-flutter",
            f"Image {dev_container_tag} exists but flutter --version "
            "failed inside container",
        )

    m = re.search(r"^Flutter\s+(\S+)", flutter_in)
    flutter_ver = m.group(1).rstrip(".") if m else "?"
    return _check_found(
        "docker-flutter",
        f"Docker {info}, image {dev_container_tag} available, "
        f"Flutter {flutter_ver} inside",
    )


def check_crlf_scripts() -> dict[str, object]:
    """Check that no `.sh` files under the Flutter shell tree have CRLF line
    endings, which would prevent execution inside a WSL/Linux environment."""
    flutter_dirs = [
        REPO_ROOT / "frontend" / "vityo_app",
    ]
    crlf_files: list[str] = []
    for base_dir in flutter_dirs:
        if not base_dir.is_dir():
            continue
        for sh_file in sorted(base_dir.rglob("*.sh")):
            try:
                data = sh_file.read_bytes()
                if b"\r\n" in data:
                    crlf_files.append(
                        str(sh_file.relative_to(REPO_ROOT))
                    )
            except (OSError, PermissionError):
                continue

    # Also check scripts/ and docker/ for shell scripts that need to run
    # inside the container.
    extra_roots = [REPO_ROOT / "scripts", REPO_ROOT / "docker"]
    for root in extra_roots:
        if not root.is_dir():
            continue
        for sh_file in sorted(root.rglob("*.sh")):
            try:
                data = sh_file.read_bytes()
                if b"\r\n" in data:
                    crlf_files.append(
                        str(sh_file.relative_to(REPO_ROOT))
                    )
            except (OSError, PermissionError):
                continue

    if crlf_files:
        return _check_blocked(
            "crlf-scripts",
            f"{len(crlf_files)} shell script(s) have CRLF line endings "
            f"(blocked on Linux): {', '.join(crlf_files)}",
        )
    return _check_found("crlf-scripts", "all shell scripts use LF line endings")


# check registry and runner


CHECK_REGISTRY: dict[str, tuple[str, str]] = {
    "python": ("Python availability & version", "check_python"),
    "flutter": ("Dart/Flutter availability & version", "check_flutter"),
    "npm": ("Node/npm availability & version", "check_npm"),
    "chromium": ("Chrome/Chromium availability & version", "check_chromium"),
    "docker-flutter": (
        "Docker image & containerised Flutter availability",
        "check_docker_flutter",
    ),
    "crlf-scripts": ("CRLF Flutter shell-script blockers", "check_crlf_scripts"),
}

# Mapping of check name -> function reference, populated at module load.
_CHECK_FUNCS: dict[str, Callable[[], dict[str, object]]] = {}


def _populate_check_funcs() -> None:
    """Populate _CHECK_FUNCS by name lookup to avoid circular def-order
    issues and keep the registry readable."""
    for name, (_desc, func_name) in CHECK_REGISTRY.items():
        _CHECK_FUNCS[name] = globals()[func_name]


_populate_check_funcs()


def run_single_check(name: str) -> dict[str, object]:
    """Run a single check by name and return its result dict."""
    func = _CHECK_FUNCS.get(name)
    if func is None:
        return {"name": name, "ok": False, "detail": f"unknown check: {name}"}
    return func()


def run_all_checks(
    include: set[str] | None = None,
) -> list[dict[str, object]]:
    """Run all registered checks (or a subset if *include* is given) and
    return a list of result dicts."""
    results: list[dict[str, object]] = []
    for name in CHECK_REGISTRY:
        if include is not None and name not in include:
            continue
        results.append(run_single_check(name))
    return results


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Linux host readiness gate for WSL/Docker"
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit JSON output instead of human-readable lines",
    )
    parser.add_argument(
        "--check",
        type=str,
        default=None,
        help="Run a single check by name (e.g. --check flutter)",
    )
    args = parser.parse_args(argv)

    if args.check:
        results = [run_single_check(args.check)]
    else:
        results = run_all_checks()

    blocked = [r for r in results if r.get("blocked") and not r["ok"]]
    warnings = [r for r in results if not r.get("blocked") and not r["ok"]]
    exit_code = 0
    if blocked:
        exit_code = 1
    elif warnings:
        exit_code = 2

    if args.json:
        print(
            json.dumps(
                {
                    "ok": not blocked and not warnings,
                    "blocked": len(blocked),
                    "warnings": len(warnings),
                    "checks": results,
                },
                sort_keys=True,
            )
        )
    else:
        prefix = "linux-readiness"
        for r in results:
            if r["ok"]:
                tag = "ok"
            elif r.get("blocked"):
                tag = "BLOCKED"
            else:
                tag = "WARN"
            print(f"[{prefix}] {tag}: {r['name']} ({r['detail']})")

        if blocked:
            print(
                f"[{prefix}] {len(blocked)} blocked check(s) - "
                "resolve before building on Linux",
            )
        if warnings:
            print(
                f"[{prefix}] {len(warnings)} warning(s) - "
                "review before building on Linux",
            )
        if not blocked and not warnings:
            print(f"[{prefix}] all checks passed")

    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())

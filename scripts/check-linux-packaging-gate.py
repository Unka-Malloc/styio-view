#!/usr/bin/env python3
"""Linux packaging gate — verify that Linux desktop release packaging
metadata exists and is structurally valid.

This gate can run on any host (Linux, macOS, Windows) to validate the
source-tree packaging templates.  Full desktop-file / AppStream validation
requires the corresponding CLI tools (desktop-file-validate, appstreamcli)
on a Linux host.

Usage:
    python3 scripts/check-linux-packaging-gate.py [--json]
"""

from __future__ import annotations

import argparse
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]

REQUIRED_PACKAGING_FILES: dict[str, str] = {
    "packaging/linux/io.vityo.desktop": "FreeDesktop.org desktop entry",
    "packaging/linux/io.vityo.metainfo.xml": "AppStream metadata",
    "packaging/linux/DEBIAN/control": "Debian package control file",
    "packaging/linux/README.md": "Packaging directory README",
}

DESKTOP_REQUIRED_FIELDS = ("Name", "Type", "Exec", "Icon", "Categories")
APPSTREAM_REQUIRED_TAGS = ("id", "name", "summary", "description")


def check_file_exists(relative_path: str, purpose: str) -> dict[str, object]:
    path = REPO_ROOT / relative_path
    ok = path.is_file()
    return {
        "name": f"file: {relative_path}",
        "ok": ok,
        "detail": purpose if ok else f"missing: {relative_path}",
    }


def check_desktop_file(relative_path: str) -> dict[str, object]:
    path = REPO_ROOT / relative_path
    if not path.is_file():
        return {"name": "desktop-entry keys", "ok": False, "detail": f"missing: {relative_path}"}

    present_fields: set[str] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if "=" in stripped and not stripped.startswith("#") and not stripped.startswith("["):
            key = stripped.split("=", 1)[0].strip()
            present_fields.add(key)

    missing = [f for f in DESKTOP_REQUIRED_FIELDS if f not in present_fields]
    return {
        "name": "desktop-entry keys",
        "ok": not missing,
        "detail": "all required keys present" if not missing else f"missing keys: {', '.join(missing)}",
    }


def check_appstream_xml(relative_path: str) -> dict[str, object]:
    path = REPO_ROOT / relative_path
    if not path.is_file():
        return {"name": "appstream xml", "ok": False, "detail": f"missing: {relative_path}"}

    try:
        tree = ET.parse(path)
        root = tree.getroot()
    except ET.ParseError as e:
        return {"name": "appstream xml", "ok": False, "detail": f"invalid XML: {e}"}

    ns = {"appstream": "https://www.freedesktop.org/standards/appstream/1.0"}
    # Try without namespace first
    missing_tags = []
    for tag in APPSTREAM_REQUIRED_TAGS:
        if root.find(f".//{{http://www.freedesktop.org/standards/appstream/1.0}}{tag}") is None and \
           root.find(f".//{tag}") is None:
            missing_tags.append(tag)

    return {
        "name": "appstream xml",
        "ok": not missing_tags,
        "detail": "valid XML, required tags present" if not missing_tags
        else f"missing tags: {', '.join(missing_tags)}",
    }


def check_debian_control(relative_path: str) -> dict[str, object]:
    path = REPO_ROOT / relative_path
    if not path.is_file():
        return {"name": "debian control", "ok": False, "detail": f"missing: {relative_path}"}

    required_fields = {"Package", "Version", "Section", "Architecture", "Description"}
    text = path.read_text(encoding="utf-8")
    present: set[str] = set()
    for line in text.splitlines():
        if ":" in line:
            key = line.split(":", 1)[0].strip()
            if key:
                present.add(key)
    missing = required_fields - present
    return {
        "name": "debian control",
        "ok": not missing,
        "detail": "required fields present" if not missing
        else f"missing fields: {', '.join(sorted(missing))}",
    }


def run_checks() -> list[dict[str, object]]:
    results: list[dict[str, object]] = []

    for relative_path, purpose in REQUIRED_PACKAGING_FILES.items():
        results.append(check_file_exists(relative_path, purpose))

    results.append(check_desktop_file("packaging/linux/io.vityo.desktop"))
    results.append(check_appstream_xml("packaging/linux/io.vityo.metainfo.xml"))
    results.append(check_debian_control("packaging/linux/DEBIAN/control"))

    return results


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Linux packaging gate")
    parser.add_argument("--json", action="store_true", help="Emit JSON output")
    args = parser.parse_args(argv)

    results = run_checks()
    failures = [r for r in results if not r["ok"]]

    if args.json:
        print(json.dumps({"ok": not failures, "checks": results}, sort_keys=True))
    else:
        for r in results:
            status = "ok" if r["ok"] else "FAIL"
            print(f"[linux-packaging] {status}: {r['name']} ({r['detail']})")

    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
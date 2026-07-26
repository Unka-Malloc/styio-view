#!/usr/bin/env python3
"""Validate permanent Styio product dependency boundaries."""

from __future__ import annotations

import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
IDE = ROOT / "products" / "styio_ide"
AGENT = ROOT / "products" / "styio_coding_agent"
PROTOCOL = ROOT / "packages" / "styio_agent_protocol"


def dart_sources(root: pathlib.Path) -> list[pathlib.Path]:
    return sorted(path for path in root.rglob("*.dart") if "build" not in path.parts)


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)


def package_metadata(root: pathlib.Path) -> str:
    return (root / "pubspec.yaml").read_text(encoding="utf-8")


def main() -> int:
    errors = 0
    for root in (IDE, AGENT, PROTOCOL):
        if not (root / "pubspec.yaml").is_file():
            fail(f"missing package metadata: {root.relative_to(ROOT)}")
            errors += 1

    forbidden = (
        (IDE, re.compile(r"package:styio_coding_agent/"), "IDE imports Coding Agent"),
        (AGENT, re.compile(r"package:styio_ide/"), "Coding Agent imports IDE"),
        (AGENT, re.compile(r"package:flutter/"), "Coding Agent imports Flutter"),
        (PROTOCOL, re.compile(r"package:(?:flutter|styio_ide|styio_coding_agent)/"),
         "protocol imports a product or presentation framework"),
    )
    for root, pattern, label in forbidden:
        for path in dart_sources(root):
            if pattern.search(path.read_text(encoding="utf-8")):
                fail(f"{label}: {path.relative_to(ROOT)}")
                errors += 1

    metadata_rules = (
        (IDE, re.compile(r"(?m)^\s+styio_coding_agent\s*:"), "IDE depends on Coding Agent"),
        (AGENT, re.compile(r"(?m)^\s+(?:flutter|styio_ide)\s*:"), "Coding Agent has a forbidden dependency"),
        (
            PROTOCOL,
            re.compile(r"(?m)^\s+(?:flutter|styio_ide|styio_coding_agent)\s*:"),
            "protocol has a product or presentation dependency",
        ),
    )
    for root, pattern, label in metadata_rules:
        if pattern.search(package_metadata(root)):
            fail(f"{label}: {root.relative_to(ROOT) / 'pubspec.yaml'}")
            errors += 1

    if "styio_agent_protocol:" not in package_metadata(IDE):
        fail("IDE does not consume the shared protocol package")
        errors += 1
    if "styio_agent_protocol:" not in package_metadata(AGENT):
        fail("Coding Agent does not consume the shared protocol package")
        errors += 1

    if errors:
        return 1
    print("OK: Styio product-line dependency boundaries are valid.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

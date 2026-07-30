from __future__ import annotations

import pathlib
import re
import subprocess
import sys


ROOT = pathlib.Path(__file__).resolve().parents[3]
IDE = ROOT / "products" / "vityo_app"
AGENT = ROOT / "products" / "vityo_coding_agent"
PROTOCOL = ROOT / "packages" / "vityo_agent_protocol"


def _pubspec_name(package: pathlib.Path) -> str:
    match = re.search(
        r"(?m)^name:\s*([a-z][a-z0-9_]*)\s*$",
        (package / "pubspec.yaml").read_text(encoding="utf-8"),
    )
    assert match is not None, f"missing package name in {package}"
    return match.group(1)


def _active_text_files() -> list[pathlib.Path]:
    roots = (
        ROOT / "products",
        ROOT / "packages",
        ROOT / "scripts",
        ROOT / "packaging",
        ROOT / ".github" / "workflows",
    )
    suffixes = {".dart", ".json", ".md", ".py", ".sh", ".yaml", ".yml"}
    return [
        path
        for root in roots
        if root.exists()
        for path in root.rglob("*")
        if path.is_file() and path.suffix in suffixes and "build" not in path.parts
    ]


def test_product_line_boundary_gate() -> None:
    result = subprocess.run(
        [sys.executable, "scripts/check_product_line_boundaries.py"],
        cwd=ROOT,
        check=False,
    )
    assert result.returncode == 0


def test_legacy_application_root_is_absent() -> None:
    legacy = ROOT / "frontend" / "vityo_app"
    assert not legacy.exists() or not any(legacy.iterdir())


def test_final_product_metadata_has_one_canonical_identity_per_line() -> None:
    assert _pubspec_name(IDE) == "vityo_app"
    assert _pubspec_name(AGENT) == "vityo_coding_agent"
    assert _pubspec_name(PROTOCOL) == "vityo_agent_protocol"


def test_active_sources_have_no_legacy_application_root_reference() -> None:
    offenders: list[str] = []
    for path in _active_text_files():
        text = path.read_text(encoding="utf-8")
        if "frontend/vityo_app" in text:
            offenders.append(path.relative_to(ROOT).as_posix())
    assert offenders == []


def test_old_agent_implementation_and_compatibility_roots_are_removed() -> None:
    old_roots = (
        IDE / "lib" / "src" / "agent",
        IDE / "lib" / "src" / "view_ide" / "agent",
        IDE / "lib" / "src" / "view_render" / "agent",
    )
    assert [path.relative_to(ROOT).as_posix() for path in old_roots if path.exists()] == []


def test_ide_package_does_not_link_the_coding_agent_runtime() -> None:
    pubspec = (IDE / "pubspec.yaml").read_text(encoding="utf-8")
    assert "vityo_coding_agent" not in pubspec
    dart_sources = [
        path
        for path in (IDE / "lib").rglob("*.dart")
        if "build" not in path.parts
    ]
    assert not any(
        "package:vityo_coding_agent/" in path.read_text(encoding="utf-8")
        for path in dart_sources
    )


def main() -> None:
    checks = (
        test_product_line_boundary_gate,
        test_legacy_application_root_is_absent,
        test_final_product_metadata_has_one_canonical_identity_per_line,
        test_active_sources_have_no_legacy_application_root_reference,
        test_old_agent_implementation_and_compatibility_roots_are_removed,
        test_ide_package_does_not_link_the_coding_agent_runtime,
    )
    for check in checks:
        check()
    print(f"cutover acceptance: {len(checks)} passed")


if __name__ == "__main__":
    main()

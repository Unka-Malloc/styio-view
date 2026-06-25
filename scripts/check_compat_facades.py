#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SRC_ROOT = REPO_ROOT / "frontend" / "vityo_app" / "lib" / "src"

EXPORT_PATTERN = re.compile(r"^export ['\"]([^'\"]+)['\"];$")


@dataclass(frozen=True)
class FacadeRule:
    name: str
    root: Path
    allowed_target_prefixes: tuple[str, ...]


def default_facade_rules() -> tuple[FacadeRule, ...]:
    return (
        FacadeRule(
            name="backend_toolchain",
            root=SRC_ROOT / "backend_toolchain",
            allowed_target_prefixes=("view_ide/backend_toolchain/",),
        ),
        FacadeRule(
            name="editor",
            root=SRC_ROOT / "editor",
            allowed_target_prefixes=("view_ide/editor/", "view_render/editor/"),
        ),
        FacadeRule(
            name="language",
            root=SRC_ROOT / "language",
            allowed_target_prefixes=("view_ide/language/",),
        ),
    )


def relative_to_repo(path: Path) -> str:
    try:
        return path.resolve().relative_to(REPO_ROOT.resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def relative_to_src(path: Path) -> str | None:
    try:
        return path.resolve().relative_to(SRC_ROOT.resolve()).as_posix()
    except ValueError:
        return None


def non_empty_lines(path: Path) -> list[str]:
    return [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def check_facade_rule(rule: FacadeRule) -> list[str]:
    errors: list[str] = []
    if not rule.root.is_dir():
        return [
            f"required legacy {rule.name} facade directory is missing: "
            f"{relative_to_repo(rule.root)}"
        ]

    for path in sorted(rule.root.glob("*.dart")):
        path_label = relative_to_repo(path)
        lines = non_empty_lines(path)
        if len(lines) != 1:
            errors.append(
                f"{path_label}: legacy {rule.name} files must stay one-line "
                "compatibility facades"
            )
            continue
        match = EXPORT_PATTERN.match(lines[0])
        if match is None:
            errors.append(f"{path_label}: legacy {rule.name} files must contain only a single export")
            continue
        target = (path.parent / match.group(1)).resolve()
        target_rel = relative_to_src(target)
        if target_rel is None or not any(
            target_rel.startswith(prefix) for prefix in rule.allowed_target_prefixes
        ):
            allowed = ", ".join(rule.allowed_target_prefixes)
            errors.append(
                f"{path_label}: facade target must resolve under {allowed}"
            )
            continue
        if not target.exists():
            errors.append(
                f"{path_label}: facade target is missing: {relative_to_repo(target)}"
            )
    return errors


def check_compat_facades(rules: tuple[FacadeRule, ...] | None = None) -> list[str]:
    errors: list[str] = []
    for rule in rules or default_facade_rules():
        errors.extend(check_facade_rule(rule))
    return errors


def print_text_report(errors: list[str]) -> int:
    if not errors:
        print("[compat-facades] OK")
        return 0
    print("[compat-facades] FAILED", file=sys.stderr)
    for error in sorted(errors):
        print(f"  - {error}", file=sys.stderr)
    return 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Check legacy Vityo compatibility facades.")
    parser.add_argument("--json", action="store_true", help="Emit JSON instead of text.")
    args = parser.parse_args(argv)

    errors = check_compat_facades()
    if args.json:
        print(
            json.dumps(
                {"ok": not errors, "errors": errors},
                indent=2,
                sort_keys=True,
            )
        )
        return 0 if not errors else 1
    return print_text_report(errors)


if __name__ == "__main__":
    raise SystemExit(main())

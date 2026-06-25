#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]

REQUIRED_SECURITY_FILES = (
    Path("frontend/vityo_app/lib/src/view_ide/environment/execution/execution_sandbox.dart"),
    Path("frontend/vityo_app/lib/src/view_ide/environment/configuration/log_redactor.dart"),
    Path("frontend/vityo_app/lib/src/view_ide/environment/configuration/secret_store.dart"),
    Path("frontend/vityo_app/lib/src/view_ide/module_host/module_manifest_security.dart"),
    Path("frontend/vityo_app/lib/src/view_ide/agent/agent_permission_model.dart"),
)

CRITICAL_SOURCE_GLOBS = (
    "frontend/vityo_app/lib/src/view_ide/environment/execution/*.dart",
    "frontend/vityo_app/lib/src/view_ide/environment/configuration/log_redactor.dart",
    "frontend/vityo_app/lib/src/view_ide/environment/configuration/secret_store.dart",
    "frontend/vityo_app/lib/src/view_ide/module_host/module_manifest_security.dart",
    "frontend/vityo_app/lib/src/view_ide/agent/agent_permission_model.dart",
)

FORBIDDEN_PATTERNS = (
    (re.compile(r"catch\s*\(\s*_\s*\)"), "silent catch (_) is not allowed in security-critical files"),
    (re.compile(r"runInShell\s*:\s*true"), "security-critical execution must not opt into shell mode"),
    (re.compile(r"Process\.(run|start)\([^,\n]+[\+][^,\n]+"), "process execution must use argv, not string concatenation"),
    (re.compile(r"Authorization\s*:\s*(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+", re.I), "authorization header literal is not redacted"),
    (re.compile(r"\bsk-[A-Za-z0-9_-]{12,}\b"), "API key-like literal is not allowed"),
)


def relative(path: Path) -> str:
    try:
        return path.relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def critical_files() -> list[Path]:
    files: set[Path] = set()
    for glob in CRITICAL_SOURCE_GLOBS:
        files.update(REPO_ROOT.glob(glob))
    return sorted(path for path in files if path.is_file())


def check_required_files() -> list[str]:
    return [
        f"missing required security file: {path.as_posix()}"
        for path in REQUIRED_SECURITY_FILES
        if not (REPO_ROOT / path).is_file()
    ]


def check_forbidden_patterns() -> list[str]:
    errors: list[str] = []
    for path in critical_files():
        text = path.read_text(encoding="utf-8")
        for pattern, message in FORBIDDEN_PATTERNS:
            for match in pattern.finditer(text):
                line = text.count("\n", 0, match.start()) + 1
                errors.append(f"{relative(path)}:{line}: {message}")
    return errors


def check_security_baseline() -> list[str]:
    errors: list[str] = []
    errors.extend(check_required_files())
    errors.extend(check_forbidden_patterns())
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Check Vityo security baseline gates.")
    parser.add_argument("--json", action="store_true", help="Emit JSON.")
    args = parser.parse_args(argv)
    errors = check_security_baseline()
    if args.json:
      print(json.dumps({"ok": not errors, "errors": errors}, indent=2, sort_keys=True))
    elif errors:
        print("[security-baseline] FAILED", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
    else:
        print("[security-baseline] OK")
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PYTHON_COVERAGE_GATE = ROOT / "scripts" / "python-coverage-gate.py"
DEFAULT_FLUTTER_DIR = Path("frontend/vityo_app")
DEFAULT_FAIL_UNDER = 95
LCOV_RELATIVE_PATH = Path("coverage/lcov.info")


@dataclass(frozen=True)
class LineCoverage:
    found: int
    hit: int

    @property
    def percent(self) -> float:
        return 100.0 * self.hit / self.found


def parse_lcov(path: Path) -> LineCoverage:
    if not path.is_file():
        raise RuntimeError(f"lcov report is missing: {path}")

    found = 0
    hit = 0
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("LF:"):
            try:
                found += int(line.removeprefix("LF:"))
            except ValueError as exc:
                raise RuntimeError(f"invalid LF counter in {path}: {line}") from exc
        elif line.startswith("LH:"):
            try:
                hit += int(line.removeprefix("LH:"))
            except ValueError as exc:
                raise RuntimeError(f"invalid LH counter in {path}: {line}") from exc

    if found <= 0:
        raise RuntimeError(f"lcov report has no line data: {path}")
    if hit > found:
        raise RuntimeError(f"lcov report has more hit lines than found lines: {path}")
    return LineCoverage(found=found, hit=hit)


def run_command(command: list[str], *, cwd: Path) -> int:
    return subprocess.run(command, cwd=cwd, check=False).returncode


def run_python_gate(fail_under: int) -> int:
    return run_command(
        [sys.executable, str(PYTHON_COVERAGE_GATE), "--fail-under", str(fail_under)],
        cwd=ROOT,
    )


def resolve_flutter_binary(raw: str | None) -> str | None:
    if raw:
        return shutil.which(raw) or (raw if Path(raw).is_file() else None)
    return shutil.which("flutter")


def resolve_lcov_path(*, app_dir: Path, flutter_coverage_path: Path | None) -> Path:
    if flutter_coverage_path is None:
        return app_dir / LCOV_RELATIVE_PATH
    if flutter_coverage_path.is_absolute():
        return flutter_coverage_path
    return ROOT / flutter_coverage_path


def run_flutter_gate(
    *,
    fail_under: int,
    flutter_dir: Path,
    flutter_bin: str | None,
    use_existing_report: bool = False,
    flutter_coverage_path: Path | None = None,
) -> int:
    flutter = resolve_flutter_binary(flutter_bin)
    if flutter is None and not use_existing_report:
        print("flutter is required for Flutter coverage; install Flutter or pass --flutter-bin", file=sys.stderr)
        return 2

    app_dir = ROOT / flutter_dir
    needs_app_dir = not use_existing_report or flutter_coverage_path is None
    if needs_app_dir and not app_dir.is_dir():
        print(f"Flutter app directory is missing: {flutter_dir}", file=sys.stderr)
        return 2

    if not use_existing_report:
        assert flutter is not None
        code = run_command([flutter, "test", "--coverage"], cwd=app_dir)
        if code != 0:
            return code

    try:
        coverage = parse_lcov(
            resolve_lcov_path(
                app_dir=app_dir,
                flutter_coverage_path=flutter_coverage_path,
            )
        )
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    print(
        "[project-coverage] Flutter line coverage: "
        f"{coverage.percent:.2f}% ({coverage.hit}/{coverage.found} lines)"
    )
    return 0 if coverage.percent >= fail_under else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run project coverage gates for Vityo.")
    parser.add_argument("--fail-under", type=int, default=DEFAULT_FAIL_UNDER)
    parser.add_argument("--python-fail-under", type=int)
    parser.add_argument("--flutter-fail-under", type=int)
    parser.add_argument("--flutter-dir", type=Path, default=DEFAULT_FLUTTER_DIR)
    parser.add_argument("--flutter-bin")
    parser.add_argument(
        "--flutter-coverage-path",
        type=Path,
        help="Parse this LCOV report path, relative to the repository root or absolute.",
    )
    parser.add_argument(
        "--use-existing-flutter-coverage",
        action="store_true",
        help="Parse an existing Flutter LCOV report without running flutter test.",
    )
    parser.add_argument("--skip-python", action="store_true")
    parser.add_argument("--skip-flutter", action="store_true")
    args = parser.parse_args(argv)

    if args.skip_python and args.skip_flutter:
        print("at least one coverage scope must be enabled", file=sys.stderr)
        return 2

    if not args.skip_python:
        code = run_python_gate(args.python_fail_under or args.fail_under)
        if code != 0:
            return code

    if not args.skip_flutter:
        code = run_flutter_gate(
            fail_under=args.flutter_fail_under or args.fail_under,
            flutter_dir=args.flutter_dir,
            flutter_bin=args.flutter_bin,
            use_existing_report=args.use_existing_flutter_coverage,
            flutter_coverage_path=args.flutter_coverage_path,
        )
        if code != 0:
            return code

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

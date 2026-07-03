#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Sequence

ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class TeamRule:
    key: str
    label: str
    doc: Path
    prefixes: tuple[str, ...]


TEAM_RULES: tuple[TeamRule, ...] = (
    TeamRule(
        "shell_editor",
        "Shell / Editor",
        Path("docs/teams/SHELL-EDITOR-RUNBOOK.md"),
        (
            "frontend/vityo_app/lib/src/app/",
            "frontend/vityo_app/lib/src/editor/",
            "frontend/vityo_app/lib/src/frontend_shell/",
            "frontend/vityo_app/lib/src/language/",
            "prototype/",
        ),
    ),
    TeamRule(
        "runtime_agent",
        "Runtime / Agent",
        Path("docs/teams/RUNTIME-AGENT-RUNBOOK.md"),
        (
            "frontend/vityo_app/lib/src/runtime/",
            "frontend/vityo_app/lib/src/agent/",
        ),
    ),
    TeamRule(
        "module_platform",
        "Module / Platform",
        Path("docs/teams/MODULE-PLATFORM-RUNBOOK.md"),
        (
            "frontend/vityo_app/lib/src/module_host/",
            "frontend/vityo_app/lib/src/platform/",
            "frontend/vityo_app/assets/module_manifests/",
            "frontend/vityo_app/assets/capability_matrices/",
            "frontend/vityo_app/scripts/bootstrap_flutter_platforms.sh",
        ),
    ),
    TeamRule(
        "adapter_contracts",
        "Adapter / Contracts",
        Path("docs/teams/ADAPTER-CONTRACTS-RUNBOOK.md"),
        (
            "frontend/vityo_app/lib/src/backend_toolchain/",
            "frontend/vityo_app/lib/src/integration/",
            "docs/contracts/",
            "docs/external/for-pafio/",
            "docs/external/for-styio/",
        ),
    ),
    TeamRule(
        "theme_ux",
        "Theme / UX",
        Path("docs/teams/THEME-UX-RUNBOOK.md"),
        (
            "frontend/vityo_app/lib/src/theme/",
            "prototype/editor.css",
            "prototype/styles.css",
            "prototype/theme-config.example.jsonc",
        ),
    ),
    TeamRule(
        "docs_delivery",
        "Docs / Delivery",
        Path("docs/teams/DOCS-DELIVERY-RUNBOOK.md"),
        (
            "README.md",
            "docs/",
            "scripts/check_repo_hygiene.py",
            "scripts/repo-hygiene-gate.py",
            "scripts/docs-index.py",
            "scripts/docs-lifecycle.py",
            "scripts/docs-audit.py",
            "scripts/team-docs-gate.py",
            "scripts/docs-gate.sh",
            "scripts/delivery-gate.sh",
            "scripts/bootstrap-dev-env.sh",
            "scripts/bootstrap-dev-container.sh",
            "scripts/bootstrap-dev-env-macos.sh",
            "scripts/bootstrap-dev-env-windows.ps1",
            "scripts/bootstrap-workspace.sh",
            "scripts/bootstrap-workspace.ps1",
            "scripts/android-sdk-profile.sh",
            "scripts/android-sdk-profile.ps1",
            "scripts/apple-platform-profile.sh",
            "scripts/verify-android-device.sh",
            "scripts/verify-android-device.ps1",
            "scripts/verify-apple-device.sh",
            "docker/",
            ".devcontainer/",
            "toolchain/android-sdk-profiles.csv",
            "toolchain/apple-platform-profiles.csv",
        ),
    ),
)

TEAM_RUNBOOKS = {
    Path("docs/teams/ADAPTER-CONTRACTS-RUNBOOK.md"),
    Path("docs/teams/AGENT-RUNTIME-RUNBOOK.md"),
    Path("docs/teams/ARCHITECTURE-RUNBOOK.md"),
    Path("docs/teams/COORDINATION-RUNBOOK.md"),
    Path("docs/teams/DOCS-DELIVERY-RUNBOOK.md"),
    Path("docs/teams/EXTENSION-MODULE-RUNBOOK.md"),
    Path("docs/teams/MODULE-PLATFORM-RUNBOOK.md"),
    Path("docs/teams/RUNTIME-AGENT-RUNBOOK.md"),
    Path("docs/teams/SHELL-EDITOR-RUNBOOK.md"),
    Path("docs/teams/THEME-UX-RUNBOOK.md"),
}
DOC_STATS = Path("docs/teams/DOC-STATS.md")
TEMPLATE_DOC = Path("docs/assets/workflow/TEAM-RUNBOOK-TEMPLATE.md")
GATE_DOC = Path("docs/assets/workflow/TEAM-RUNBOOK-MAINTENANCE-GATE.md")

TEAM_REQUIRED_HEADINGS: tuple[str, ...] = (
    "Mission",
    "Owned Surface",
    "Daily Workflow",
    "Change Classes",
    "Required Gates",
    "Cross-Team Dependencies",
    "Handoff / Recovery",
)
COORDINATION_REQUIRED_HEADINGS: tuple[str, ...] = (
    "Mission",
    "Module Map",
    "Ownership Table",
    "Review Matrix",
    "Escalation Rules",
    "Checkpoint Policy",
    "Release / Cutover Gates",
    "Handoff / Recovery",
)
PURPOSE_RE = re.compile(r"^\*\*Purpose:\*\*\s+.+$", re.M)
LAST_UPDATED_RE = re.compile(r"^\*\*Last updated:\*\*\s+[0-9]{4}-[0-9]{2}-[0-9]{2}\s*$", re.M)


def run_git(args: Sequence[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", *args], cwd=ROOT, text=True, capture_output=True)


def normalize_path(path: str) -> Path:
    return Path(path.strip().strip('"'))


def changed_from_worktree() -> List[Path]:
    proc = run_git(["status", "--porcelain=v1", "--untracked-files=all"])
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or "git status failed")
    paths: List[Path] = []
    for line in proc.stdout.splitlines():
        if not line:
            continue
        raw = line[3:]
        if " -> " in raw:
            raw = raw.split(" -> ", 1)[1]
        paths.append(normalize_path(raw))
    return sorted(set(paths), key=lambda p: p.as_posix())


def changed_from_staged() -> List[Path]:
    proc = run_git(["diff", "--cached", "--name-status", "--find-renames"])
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or "git diff --cached failed")
    return parse_name_status(proc.stdout)


def changed_from_base(base: str) -> List[Path]:
    merge_base = run_git(["merge-base", base, "HEAD"])
    if merge_base.returncode != 0:
        raise RuntimeError(merge_base.stderr.strip() or merge_base.stdout.strip() or "git merge-base failed")
    anchor = merge_base.stdout.strip()
    proc = run_git(["diff", "--name-status", "--find-renames", f"{anchor}..HEAD"])
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or "git diff failed")
    return parse_name_status(proc.stdout)


def parse_name_status(text: str) -> List[Path]:
    paths: List[Path] = []
    for line in text.splitlines():
        if not line:
            continue
        parts = line.split("\t")
        status = parts[0]
        if status.startswith(("R", "C")) and len(parts) >= 3:
            paths.append(normalize_path(parts[2]))
        elif len(parts) >= 2:
            paths.append(normalize_path(parts[1]))
    return sorted(set(paths), key=lambda p: p.as_posix())


def is_generated_index(path: Path) -> bool:
    return path.parts[:1] == ("docs",) and path.name == "INDEX.md"


def is_ignored_trigger(path: Path) -> bool:
    if is_generated_index(path):
        return True
    if path == DOC_STATS:
        return True
    if path.as_posix().startswith("docs/teams/"):
        return True
    return False


def matches_prefix(path: Path, prefix: str) -> bool:
    text = path.as_posix()
    return text.startswith(prefix) if prefix.endswith("/") else text == prefix


def required_team_updates(changed_paths: Iterable[Path]) -> Dict[TeamRule, List[Path]]:
    required: Dict[TeamRule, List[Path]] = {}
    for path in changed_paths:
        if is_ignored_trigger(path):
            continue
        for rule in TEAM_RULES:
            if any(matches_prefix(path, prefix) for prefix in rule.prefixes):
                required.setdefault(rule, []).append(path)
    return required


def format_paths(paths: Sequence[Path], limit: int = 8) -> str:
    shown = [f"    - {p.as_posix()}" for p in paths[:limit]]
    if len(paths) > limit:
        shown.append(f"    - ... {len(paths) - limit} more")
    return "\n".join(shown)


def h2_headings(text: str) -> List[str]:
    return [line[3:].strip() for line in text.splitlines() if line.startswith("## ")]


def validate_runbook_format(path: Path, required_headings: Sequence[str]) -> List[str]:
    errors: List[str] = []
    absolute = ROOT / path
    if not absolute.exists():
        return [f"{path.as_posix()} is missing"]
    text = absolute.read_text(encoding="utf-8")
    first_nonempty = next((line.strip() for line in text.splitlines() if line.strip()), "")
    if not first_nonempty.startswith("# ") or not first_nonempty.endswith("Runbook"):
        errors.append(f"{path.as_posix()} must start with an H1 ending in 'Runbook'")
    if not PURPOSE_RE.search(text):
        errors.append(f"{path.as_posix()} is missing top-level '**Purpose:** ...' metadata")
    if not LAST_UPDATED_RE.search(text):
        errors.append(f"{path.as_posix()} is missing top-level '**Last updated:** YYYY-MM-DD' metadata")
    headings = h2_headings(text)
    required_set = set(required_headings)
    for heading in required_headings:
        if heading not in headings:
            errors.append(f"{path.as_posix()} is missing required heading: ## {heading}")
        if headings.count(heading) > 1:
            errors.append(f"{path.as_posix()} has duplicate heading: ## {heading}")
    for heading in headings:
        if heading not in required_set:
            errors.append(f"{path.as_posix()} has non-template H2 heading: ## {heading}")
    if not errors:
        positions = [headings.index(heading) for heading in required_headings]
        if positions != sorted(positions):
            ordered = ", ".join(f"## {heading}" for heading in required_headings)
            errors.append(f"{path.as_posix()} H2 headings must follow template order: {ordered}")
    return errors


def validate_all_runbook_formats() -> List[str]:
    errors: List[str] = []
    for path in sorted(TEAM_RUNBOOKS, key=lambda p: p.as_posix()):
        required = COORDINATION_REQUIRED_HEADINGS if path.name == "COORDINATION-RUNBOOK.md" else TEAM_REQUIRED_HEADINGS
        errors.extend(validate_runbook_format(path, required))
    return errors


def run_gate(changed_paths: Sequence[Path], verbose: bool) -> int:
    changed_set = set(changed_paths)
    required = required_team_updates(changed_paths)
    failures: List[str] = []
    format_errors = validate_all_runbook_formats()

    if format_errors:
        failures.append(
            "Runbook format validation failed. Use "
            f"{TEMPLATE_DOC.as_posix()} and {GATE_DOC.as_posix()}:\n"
            + "\n".join(f"    - {error}" for error in format_errors)
        )

    for rule, paths in sorted(required.items(), key=lambda item: item[0].label):
        if rule.doc not in changed_set:
            failures.append(
                f"{rule.label} changed files require updating {rule.doc.as_posix()}:\n"
                f"{format_paths(paths)}"
            )

    changed_runbooks = sorted(TEAM_RUNBOOKS.intersection(changed_set), key=lambda p: p.as_posix())
    if changed_runbooks and DOC_STATS not in changed_set:
        failures.append(
            f"Team runbook changes require refreshing {DOC_STATS.as_posix()}:\n"
            f"{format_paths(changed_runbooks)}"
        )

    if failures:
        print("team docs gate failed:", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        print(
            "Update the required team runbook(s), keep them in the documented template shape, "
            "refresh docs/teams/DOC-STATS.md when runbook sizes change, then re-run this gate.",
            file=sys.stderr,
        )
        return 1

    if verbose:
        print("team docs gate passed")
        if changed_paths:
            print("changed paths:")
            print(format_paths(changed_paths, limit=200))
    else:
        print("team docs gate passed")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Require team runbook updates when view-owned folders change.")
    parser.add_argument("--mode", choices=["worktree", "staged"], default="worktree")
    parser.add_argument("--base", default=os.environ.get("STYIO_TEAM_DOC_GATE_BASE"))
    parser.add_argument("--verbose", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.base:
            changed_paths = changed_from_base(args.base)
        elif args.mode == "staged":
            changed_paths = changed_from_staged()
        else:
            changed_paths = changed_from_worktree()
    except Exception as exc:
        print(f"team docs gate error: {exc}", file=sys.stderr)
        return 2
    return run_gate(changed_paths, args.verbose)


if __name__ == "__main__":
    raise SystemExit(main())

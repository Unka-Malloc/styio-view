#!/usr/bin/env python3
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from contextlib import contextmanager
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CANONICAL_GATE = ROOT.parent / "styio-nightly" / "scripts" / "ecosystem-cli-doc-gate.py"
SIBLING_REPOS = ("styio-nightly", "styio-pafio")


def workspace_root_from_args(args: list[str]) -> Path:
    for index, arg in enumerate(args):
        if arg == "--workspace-root" and index + 1 < len(args):
            return Path(args[index + 1])
        if arg.startswith("--workspace-root="):
            return Path(arg.split("=", 1)[1])
    return ROOT.parent


def args_with_workspace_root(args: list[str], workspace_root: Path) -> list[str]:
    updated: list[str] = []
    skip_next = False
    for arg in args:
        if skip_next:
            skip_next = False
            continue
        if arg == "--workspace-root":
            skip_next = True
            continue
        if arg.startswith("--workspace-root="):
            continue
        updated.append(arg)
    updated.extend(["--workspace-root", workspace_root.as_posix()])
    return updated


def needs_styio_view_alias(workspace_root: Path) -> bool:
    resolved_workspace = workspace_root.resolve()
    return (
        ROOT.name != "styio-view"
        and ROOT.parent.resolve() == resolved_workspace
        and not (resolved_workspace / "styio-view").is_dir()
    )


@contextmanager
def compatibility_workspace(args: list[str]):
    workspace_root = workspace_root_from_args(args).resolve()
    if not needs_styio_view_alias(workspace_root):
        yield args
        return

    with tempfile.TemporaryDirectory(prefix="vityo-ecosystem-doc-gate-") as tmp_name:
        tmp_root = Path(tmp_name)
        for repo_name in SIBLING_REPOS:
            source = workspace_root / repo_name
            if source.exists():
                link_or_copy_directory(source, tmp_root / repo_name)
        link_or_copy_directory(ROOT, tmp_root / "styio-view")
        yield args_with_workspace_root(args, tmp_root)


def link_or_copy_directory(source: Path, target: Path) -> None:
    try:
        target.symlink_to(source, target_is_directory=True)
    except OSError:
        shutil.copytree(source, target, dirs_exist_ok=True)


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    non_blocking = False
    if "--non-blocking" in args:
        non_blocking = True
        args = [a for a in args if a != "--non-blocking"]

    if not CANONICAL_GATE.is_file():
        payload = {
            "ok": True,
            "skipped": True,
            "reason": f"canonical gate not found at {CANONICAL_GATE}",
        }
        if "--json" in args:
            print(json.dumps(payload, sort_keys=True))
        else:
            print(f"[SKIP] {payload['reason']}")
        return 0

    with compatibility_workspace(args) as canonical_args:
        proc = subprocess.run([sys.executable, str(CANONICAL_GATE), *canonical_args], cwd=ROOT)

    if proc.returncode != 0 and non_blocking:
        print(
            "[WARN] ecosystem CLI doc gate reported issues but marked non-blocking;"
            " these failures are tracked in sibling repos and do not block this PR",
            file=sys.stderr,
        )
        return 0

    return proc.returncode


if __name__ == "__main__":
    raise SystemExit(main())

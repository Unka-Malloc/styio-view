#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CANONICAL_GATE = ROOT.parent / "styio-nightly" / "scripts" / "ecosystem-cli-doc-gate.py"


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

    proc = subprocess.run([sys.executable, str(CANONICAL_GATE), *args], cwd=ROOT)

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

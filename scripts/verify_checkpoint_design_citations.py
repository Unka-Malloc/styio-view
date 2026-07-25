"""Verify every docs/design citation in convergence Checkpoints.json resolves."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CP = ROOT / "docs/plan/repository-delivery-convergence/Checkpoints.json"
PAT = re.compile(r"docs/design/([A-Za-z0-9_./-]+\.md)(?::(\d+))?")


def main() -> int:
    data = json.loads(CP.read_text(encoding="utf-8"))
    errors: list[str] = []
    checked = 0
    for node in data:
        blob = json.dumps(node, ensure_ascii=False)
        for m in PAT.finditer(blob):
            checked += 1
            rel = m.group(1)
            full = ROOT / "docs" / "design" / rel
            if not full.is_file():
                errors.append(f"missing file: docs/design/{rel} (node {node.get('id')})")
                continue
            if m.group(2):
                ln = int(m.group(2))
                lines = full.read_text(encoding="utf-8").splitlines()
                if ln < 1 or ln > len(lines):
                    errors.append(
                        f"line out of range: docs/design/{rel}:{ln} "
                        f"(file has {len(lines)} lines, node {node.get('id')})"
                    )
    if errors:
        print(f"FAIL: {len(errors)} citation errors ({checked} citations checked)")
        for e in errors[:50]:
            print(f"  {e}")
        return 1
    print(f"OK: {checked} docs/design citations resolve to existing files with valid line numbers")
    return 0


if __name__ == "__main__":
    sys.exit(main())

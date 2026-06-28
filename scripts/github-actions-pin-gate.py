#!/usr/bin/env python3
"""GitHub Actions Pin Gate - enforce that all external actions are pinned to a full-length commit SHA.

Usage:
    python3 scripts/github-actions-pin-gate.py              # audit mode (default)
    python3 scripts/github-actions-pin-gate.py --mode enforce  # enforce mode (hard fail)
    python3 scripts/github-actions-pin-gate.py --json       # machine-readable JSON

Exit codes:
    0 - all actions properly pinned
    1 - one or more unpinned actions found
    2 - configuration or parse error

Policy:
    - `uses: ./...` - local actions, always allowed.
    - `uses: owner/repo@<40-char SHA>` - pinned, allowed.
    - `uses: owner/repo@vX`, `@main`, `@master`, `@stable`, `@latest`, `@HEAD` - UNPINNED, FAIL.
    - `uses: docker://...` - container actions, reported.
"""

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORKFLOW_DIR = ROOT / ".github" / "workflows"

# Patterns that indicate an unpinned action reference.
# Any tag-like or branch-like ref (not a 40-char hex SHA) is considered unpinned.
UNPINNED_PATTERN = re.compile(
    r"^[^/]+/[^@]+@(?![\da-fA-F]{40}$)"  # owner/repo@NON-SHA
)

# Common unpinned ref patterns for reporting.
TAG_OR_BRANCH_PATTERN = re.compile(
    r"@(v\d[\d.]*|main|master|stable|latest|HEAD|nightly|dev|release.*)$"
)

# Known actions that need pinning (populated by scanning).
# When --mode enforce, these cause a hard failure.
# When --mode audit (default), they are reported with TODO guidance.


def find_workflow_files() -> list[Path]:
    """Return all .yml/.yaml workflow files under .github/workflows/."""
    if not WORKFLOW_DIR.exists():
        print(f"ERROR: workflow directory not found at {WORKFLOW_DIR}", file=sys.stderr)
        return []
    return sorted(WORKFLOW_DIR.glob("*.yml")) + sorted(WORKFLOW_DIR.glob("*.yaml"))


def extract_action_uses(workflow_path: Path) -> list[dict]:
    """Extract all `uses:` lines from a workflow file, with context."""
    results = []
    text = workflow_path.read_text(encoding="utf-8")
    rel_path = workflow_path.relative_to(ROOT)

    for lineno, line in enumerate(text.splitlines(), start=1):
        match = re.search(r"uses:\s*(\S+)", line)
        if match:
            uses = match.group(1)
            results.append({
                "file": str(rel_path),
                "line": lineno,
                "uses": uses,
            })

    return results


def classify_action(uses: str) -> dict:
    """Classify an action `uses` value."""
    # Local composite action
    if uses.startswith("./"):
        return {"status": "local", "action": uses, "reason": None}

    # Docker container action
    if uses.startswith("docker://"):
        return {"status": "container", "action": uses, "reason": "Container-based action - verify separately"}

    # External action: owner/repo@ref
    if "@" not in uses:
        return {"status": "unpinned", "action": uses, "reason": "Missing version reference (no @ref)"}

    owner_repo, ref = uses.rsplit("@", 1)

    # 40-char hex SHA -> pinned
    if re.match(r"^[\da-fA-F]{40}$", ref):
        return {"status": "pinned", "action": uses, "reason": None}

    # Known tag/branch patterns -> unpinned
    tag_match = TAG_OR_BRANCH_PATTERN.search(f"@{ref}")
    tag_label = tag_match.group(1) if tag_match else ref

    return {
        "status": "unpinned",
        "action": uses,
        "owner_repo": owner_repo,
        "ref": ref,
        "reason": f"Uses tag/branch '{ref}' instead of full-length commit SHA. Pin to a 40-char SHA and comment the original tag, e.g.: {owner_repo}@<sha>  # {ref}",
    }


def run_gate(mode: str = "audit", json_output: bool = False) -> tuple[bool, list[dict]]:
    """Run the GitHub Actions pin gate.

    Returns: (passed, findings).
    """
    workflow_files = find_workflow_files()
    if not workflow_files:
        print("ERROR: No workflow files found.", file=sys.stderr)
        sys.exit(2)

    all_uses = []
    for wf in workflow_files:
        all_uses.extend(extract_action_uses(wf))

    findings = []
    pinned = []
    unpinned = []
    local = []
    containers = []

    for entry in all_uses:
        classified = classify_action(entry["uses"])
        classified["file"] = entry["file"]
        classified["line"] = entry["line"]
        findings.append(classified)

        if classified["status"] == "pinned":
            pinned.append(classified)
        elif classified["status"] == "unpinned":
            unpinned.append(classified)
        elif classified["status"] == "local":
            local.append(classified)
        elif classified["status"] == "container":
            containers.append(classified)

    has_unpinned = len(unpinned) > 0
    passed = not has_unpinned

    if json_output:
        output = {
            "gate": "github-actions-pin",
            "mode": mode,
            "passed": passed,
            "total_actions": len(findings),
            "pinned": len(pinned),
            "unpinned": len(unpinned),
            "local": len(local),
            "container": len(containers),
            "unpinned_actions": [
                {"file": u["file"], "line": u["line"], "action": u["action"], "ref": u.get("ref", ""), "reason": u["reason"]}
                for u in unpinned
            ],
            "findings": [
                {"file": f["file"], "line": f["line"], "action": f["action"], "status": f["status"]}
                for f in findings
            ],
        }
        print(json.dumps(output, indent=2))
    else:
        print("=" * 60)
        print("  Vityo GitHub Actions Pin Gate")
        print(f"  Mode: {mode}")
        print("=" * 60)
        print(f"  Workflow files scanned: {len(workflow_files)}")
        print(f"  Total action uses:     {len(findings)}")
        print(f"  Pinned (SHA):          {len(pinned)}")
        print(f"  Local (./...):         {len(local)}")
        print(f"  Container (docker):    {len(containers)}")
        print(f"  Unpinned (tag):        {len(unpinned)}")
        print()

        if pinned:
            print("  [OK] Pinned actions:")
            for p in pinned:
                print(f"    {p['action']}  ({p['file']}:{p['line']})")
            print()

        if local:
            print("  [OK] Local actions:")
            for l in local:
                print(f"    {l['action']}  ({l['file']}:{l['line']})")
            print()

        if unpinned:
            print("  [UNPINNED] Actions must be pinned to full-length SHA:")
            for u in unpinned:
                print(f"    {u['action']}  ({u['file']}:{u['line']})")
                print(f"      -> {u['reason']}")
            print()

        if containers:
            print("  [WARN] Container actions (verify separately):")
            for c in containers:
                print(f"    {c['action']}  ({c['file']}:{c['line']})")
            print()

        print(f"  Result: {'PASS' if passed else 'FAIL'}")

    if mode == "audit" and has_unpinned:
        print("\n  [AUDIT MODE] Unpinned actions are reported but do not block PR CI.")
        print("  Release readiness requires --mode enforce to pass.")
        print("  To pin actions, resolve each tag to a full-length commit SHA.")
        print("  Example fix:  actions/checkout@v5  ->  actions/checkout@<40-char-SHA>  # v5")

    return passed, findings


def main():
    parser = argparse.ArgumentParser(description="GitHub Actions Pin Gate")
    parser.add_argument(
        "--mode",
        choices=["audit", "enforce"],
        default="audit",
        help="audit = report only (default), enforce = hard fail on unpinned actions",
    )
    parser.add_argument("--json", action="store_true", help="Output machine-readable JSON")
    args = parser.parse_args()

    passed, _ = run_gate(mode=args.mode, json_output=args.json)

    if not passed and args.mode == "enforce":
        sys.exit(1)

    # In audit mode, always exit 0; the report is informational.
    sys.exit(0)


if __name__ == "__main__":
    main()

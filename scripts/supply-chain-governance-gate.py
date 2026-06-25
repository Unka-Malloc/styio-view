#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
WORKFLOW_DIR = Path(".github/workflows")
DEPENDABOT_PATH = Path(".github/dependabot.yml")

REQUIRED_POLICY_FILES = (
    Path("DEPENDENCY-USAGE.md"),
    Path("LICENSE-POLICY.md"),
    Path("docs/governance/SECURITY-AND-SUPPLY-CHAIN.md"),
    Path("docs/specs/THIRD-PARTY.md"),
    Path("frontend/vityo_app/pubspec.lock"),
    Path("prototype/package-lock.json"),
)

REQUIRED_GATE_SCRIPTS = (
    Path("scripts/check_security_baseline.py"),
    Path("scripts/check_license_policy.py"),
    Path("scripts/dependency-policy-gate.py"),
    Path("scripts/github-actions-pin-gate.py"),
    Path("scripts/supply-chain-governance-gate.py"),
)

REQUIRED_WORKFLOW_COMMANDS = {
    Path(".github/workflows/audit.yml"): (
        "scripts/check_security_baseline.py",
        "scripts/check_license_policy.py",
        "scripts/dependency-policy-gate.py",
        "scripts/github-actions-pin-gate.py",
        "scripts/supply-chain-governance-gate.py",
    ),
    Path(".github/workflows/repo-hygiene.yml"): (
        "scripts/check_security_baseline.py",
        "scripts/check_license_policy.py",
        "scripts/dependency-policy-gate.py",
        "scripts/github-actions-pin-gate.py",
        "scripts/supply-chain-governance-gate.py",
    ),
}

REQUIRED_DEPENDABOT_UPDATES = (
    ("github-actions", "/"),
    ("pub", "/frontend/vityo_app"),
    ("npm", "/prototype"),
)

REQUIRED_SECRET_IGNORE_PATTERNS = (
    "/.env",
    "/.env.*",
    "*.pem",
    "*.key",
    "*.p12",
    "*.pfx",
)

SBOM_MARKERS = (
    "## Runtime Dependencies",
    "## Dev Dependencies",
    "## Prototype Dependencies",
    "## Build / CI / Platform Toolchain Dependencies",
    "License",
    "Source Boundary",
    "Usage Boundary",
)

GOVERNANCE_DOC_MARKERS = (
    "Dependabot",
    "scripts/supply-chain-governance-gate.py",
    "scripts/github-actions-pin-gate.py",
    "scripts/dependency-policy-gate.py",
    "scripts/check_security_baseline.py",
    "scripts/check_license_policy.py",
)

SECRET_SCAN_PATHS = (
    Path(".github"),
    Path("scripts"),
    Path("docs/governance"),
    Path("DEPENDENCY-USAGE.md"),
    Path("LICENSE-POLICY.md"),
)
SECRET_SCAN_EXCLUDED_PARTS = {
    ".git",
    "__pycache__",
    "node_modules",
    ".dart_tool",
    ".pytest_cache",
}
SECRET_SCAN_MAX_BYTES = 1024 * 1024
SECRET_PATTERNS = (
    (re.compile(r"\bghp_[A-Za-z0-9_]{30,}\b"), "GitHub classic token"),
    (re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}\b"), "GitHub fine-grained token"),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "AWS access key id"),
    (re.compile(r"\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}\b"), "OpenAI-style API key"),
    (
        re.compile(r"Authorization\s*:\s*(?:Bearer|Basic)\s+[A-Za-z0-9._~+/=-]{16,}", re.I),
        "literal authorization header",
    ),
    (
        re.compile(r"-----BEGIN (?:RSA |DSA |EC |OPENSSH )?PRIVATE KEY-----"),
        "private key material",
    ),
)
FULL_SHA = re.compile(r"^[0-9a-fA-F]{40}$")


@dataclass(frozen=True)
class CheckResult:
    name: str
    ok: bool
    detail: str
    severity: str = "error"

    def to_json(self) -> dict[str, object]:
        return {
            "name": self.name,
            "ok": self.ok,
            "detail": self.detail,
            "severity": self.severity,
        }


def relative(root: Path, path: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return path.as_posix()


def workflow_files(root: Path) -> list[Path]:
    directory = root / WORKFLOW_DIR
    if not directory.is_dir():
        return []
    return sorted(directory.glob("*.yml")) + sorted(directory.glob("*.yaml"))


def strip_inline_comment(value: str) -> str:
    return value.split("#", 1)[0].strip().strip("\"'")


def top_level_block(text: str, key: str) -> tuple[str, list[str]] | None:
    lines = text.splitlines()
    for index, line in enumerate(lines):
        match = re.match(rf"^{re.escape(key)}:\s*(.*)$", line)
        if not match:
            continue
        inline = strip_inline_comment(match.group(1))
        block: list[str] = []
        for child in lines[index + 1:]:
            if child and not child.startswith((" ", "\t")) and not child.lstrip().startswith("#"):
                break
            block.append(child)
        return inline, block
    return None


def parse_top_level_permissions(text: str) -> dict[str, str] | None:
    block = top_level_block(text, "permissions")
    if block is None:
        return None
    inline, lines = block
    if inline:
        return {"__scalar__": inline}
    permissions: dict[str, str] = {}
    for line in lines:
        match = re.match(r"^\s+([A-Za-z0-9_-]+):\s*([A-Za-z-]+)\s*(?:#.*)?$", line)
        if match:
            permissions[match.group(1)] = match.group(2)
    return permissions


def workflow_has_event(text: str, event: str) -> bool:
    inline_match = re.search(rf"^on:\s*{re.escape(event)}\s*(?:#.*)?$", text, re.MULTILINE)
    if inline_match:
        return True
    block = top_level_block(text, "on")
    if block is None:
        return False
    _, lines = block
    return any(
        re.match(rf"^\s+{re.escape(event)}\s*:", line)
        or re.match(rf"^\s*-\s*{re.escape(event)}\s*$", line)
        for line in lines
    )


def extract_action_uses(text: str) -> list[tuple[int, str]]:
    uses: list[tuple[int, str]] = []
    for line_number, line in enumerate(text.splitlines(), start=1):
        match = re.search(r"uses:\s*([^ \t#]+)", line)
        if match:
            uses.append((line_number, match.group(1).strip("\"'")))
    return uses


def is_external_action(uses: str) -> bool:
    return not uses.startswith(("./", "docker://"))


def check_workflow_security(root: Path) -> list[CheckResult]:
    results: list[CheckResult] = []
    files = workflow_files(root)
    results.append(
        CheckResult(
            "workflow inventory",
            bool(files),
            f"{len(files)} workflow file(s)" if files else f"missing: {WORKFLOW_DIR}",
        )
    )
    for path in files:
        rel = relative(root, path)
        text = path.read_text(encoding="utf-8")
        permissions = parse_top_level_permissions(text)
        results.append(
            CheckResult(
                f"workflow permissions block: {rel}",
                permissions is not None,
                "present" if permissions is not None else "missing",
            )
        )
        if permissions is not None:
            scalar = permissions.get("__scalar__")
            if scalar is not None:
                allowed_scalar = scalar == "{}"
                results.append(
                    CheckResult(
                        f"workflow minimum permissions: {rel}",
                        allowed_scalar,
                        scalar,
                    )
                )
            else:
                has_contents_read = permissions.get("contents") == "read"
                write_permissions = [
                    f"{name}: {value}"
                    for name, value in permissions.items()
                    if value not in {"read", "none"}
                ]
                results.append(
                    CheckResult(
                        f"workflow contents permission: {rel}",
                        has_contents_read,
                        "contents: read" if has_contents_read else str(permissions.get("contents", "missing")),
                    )
                )
                results.append(
                    CheckResult(
                        f"workflow write permissions: {rel}",
                        not write_permissions,
                        "none" if not write_permissions else ", ".join(write_permissions),
                    )
                )
        has_pr_target = workflow_has_event(text, "pull_request_target")
        results.append(
            CheckResult(
                f"workflow pull_request_target disabled: {rel}",
                not has_pr_target,
                "disabled" if not has_pr_target else "pull_request_target is not allowed",
            )
        )
        for line_number, uses in extract_action_uses(text):
            if not is_external_action(uses):
                continue
            if "@" not in uses:
                results.append(
                    CheckResult(
                        f"workflow action ref present: {rel}:{line_number}",
                        False,
                        uses,
                    )
                )
                continue
            ref = uses.rsplit("@", 1)[1]
            if not FULL_SHA.fullmatch(ref):
                results.append(
                    CheckResult(
                        f"workflow action SHA pin: {rel}:{line_number}",
                        False,
                        f"{uses} is not pinned to a full commit SHA",
                        severity="warning",
                    )
                )
    return results


def check_required_workflow_commands(root: Path) -> list[CheckResult]:
    results: list[CheckResult] = []
    for relative_path, commands in REQUIRED_WORKFLOW_COMMANDS.items():
        path = root / relative_path
        if not path.is_file():
            results.append(CheckResult(f"workflow gate coverage: {relative_path}", False, "missing workflow"))
            continue
        text = path.read_text(encoding="utf-8")
        for command in commands:
            results.append(
                CheckResult(
                    f"workflow gate coverage: {relative_path} -> {command}",
                    command in text,
                    "present" if command in text else "missing",
                )
            )
    return results


def parse_dependabot_updates(text: str) -> list[dict[str, str]]:
    updates: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    in_updates = False
    for raw_line in text.splitlines():
        if not raw_line.strip() or raw_line.lstrip().startswith("#"):
            continue
        indent = len(raw_line) - len(raw_line.lstrip())
        stripped = raw_line.strip()
        if indent == 0:
            in_updates = stripped == "updates:"
            continue
        if not in_updates:
            continue
        ecosystem_match = re.match(r'-\s+package-ecosystem:\s*(.+)$', stripped)
        if ecosystem_match:
            if current is not None:
                updates.append(current)
            current = {"package-ecosystem": strip_inline_comment(ecosystem_match.group(1))}
            continue
        if current is None:
            continue
        field_match = re.match(r"([A-Za-z-]+):\s*(.+)$", stripped)
        if field_match:
            current[field_match.group(1)] = strip_inline_comment(field_match.group(2))
    if current is not None:
        updates.append(current)
    return updates


def check_dependabot(root: Path) -> list[CheckResult]:
    path = root / DEPENDABOT_PATH
    if not path.is_file():
        return [CheckResult("dependabot configuration", False, f"missing: {DEPENDABOT_PATH}")]

    text = path.read_text(encoding="utf-8")
    updates = parse_dependabot_updates(text)
    update_pairs = {
        (entry.get("package-ecosystem", ""), entry.get("directory", ""))
        for entry in updates
    }
    results = [
        CheckResult(
            "dependabot version",
            re.search(r"^version:\s*2\s*$", text, re.MULTILINE) is not None,
            "version: 2" if "version: 2" in text else "missing",
        ),
        CheckResult(
            "dependabot update inventory",
            bool(updates),
            f"{len(updates)} update block(s)" if updates else "missing updates",
        ),
    ]
    for ecosystem, directory in REQUIRED_DEPENDABOT_UPDATES:
        results.append(
            CheckResult(
                f"dependabot update: {ecosystem} {directory}",
                (ecosystem, directory) in update_pairs,
                "present" if (ecosystem, directory) in update_pairs else "missing",
            )
        )
    for entry in updates:
        label = f"{entry.get('package-ecosystem', 'unknown')} {entry.get('directory', 'unknown')}"
        interval = entry.get("interval", "")
        limit = entry.get("open-pull-requests-limit")
        results.append(
            CheckResult(
                f"dependabot schedule: {label}",
                interval in {"daily", "weekly", "monthly", "quarterly", "semiannually", "yearly", "cron"},
                interval or "missing",
            )
        )
        if limit is not None:
            try:
                numeric_limit = int(limit)
            except ValueError:
                numeric_limit = -1
            results.append(
                CheckResult(
                    f"dependabot PR limit: {label}",
                    1 <= numeric_limit <= 10,
                    str(limit),
                )
            )
    return results


def check_policy_surfaces(root: Path) -> list[CheckResult]:
    results: list[CheckResult] = []
    for path in REQUIRED_POLICY_FILES:
        exists = (root / path).is_file()
        results.append(
            CheckResult(
                f"policy evidence file: {path}",
                exists,
                "present" if exists else "missing",
            )
        )
    for path in REQUIRED_GATE_SCRIPTS:
        exists = (root / path).is_file()
        results.append(
            CheckResult(
                f"governance gate script: {path}",
                exists,
                "present" if exists else "missing",
            )
        )
    usage_path = root / "DEPENDENCY-USAGE.md"
    if usage_path.is_file():
        text = usage_path.read_text(encoding="utf-8")
        for marker in SBOM_MARKERS:
            results.append(
                CheckResult(
                    f"SBOM evidence marker: {marker}",
                    marker in text,
                    "present" if marker in text else "missing",
                )
            )
    governance_path = root / "docs/governance/SECURITY-AND-SUPPLY-CHAIN.md"
    if governance_path.is_file():
        text = governance_path.read_text(encoding="utf-8")
        for marker in GOVERNANCE_DOC_MARKERS:
            results.append(
                CheckResult(
                    f"governance doc marker: {marker}",
                    marker in text,
                    "present" if marker in text else "missing",
                )
            )
    return results


def check_secret_ignore_baseline(root: Path) -> list[CheckResult]:
    path = root / ".gitignore"
    if not path.is_file():
        return [CheckResult("secret ignore baseline", False, "missing .gitignore")]
    patterns = {
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    }
    return [
        CheckResult(
            f"secret ignore pattern: {pattern}",
            pattern in patterns,
            "present" if pattern in patterns else "missing",
        )
        for pattern in REQUIRED_SECRET_IGNORE_PATTERNS
    ]


def is_scan_candidate(path: Path) -> bool:
    if any(part in SECRET_SCAN_EXCLUDED_PARTS for part in path.parts):
        return False
    if not path.is_file():
        return False
    try:
        data = path.read_bytes()
    except OSError:
        return False
    return len(data) <= SECRET_SCAN_MAX_BYTES and b"\0" not in data


def iter_secret_scan_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for scan_path in SECRET_SCAN_PATHS:
        path = root / scan_path
        if path.is_dir():
            files.extend(candidate for candidate in path.rglob("*") if is_scan_candidate(candidate))
        elif is_scan_candidate(path):
            files.append(path)
    return sorted(set(files))


def check_secret_scan(root: Path) -> list[CheckResult]:
    findings: list[str] = []
    scanned = 0
    for path in iter_secret_scan_files(root):
        scanned += 1
        text = path.read_text(encoding="utf-8", errors="ignore")
        rel = relative(root, path)
        for pattern, label in SECRET_PATTERNS:
            for match in pattern.finditer(text):
                line = text.count("\n", 0, match.start()) + 1
                findings.append(f"{rel}:{line}: {label}")
    return [
        CheckResult(
            "high-signal secret scan",
            not findings,
            f"scanned {scanned} file(s)" if not findings else "; ".join(findings),
        )
    ]


def collect_checks(root: Path) -> list[CheckResult]:
    return [
        *check_workflow_security(root),
        *check_required_workflow_commands(root),
        *check_dependabot(root),
        *check_policy_surfaces(root),
        *check_secret_ignore_baseline(root),
        *check_secret_scan(root),
    ]


def has_blocking_failures(results: list[CheckResult]) -> bool:
    return any(not result.ok and result.severity == "error" for result in results)


def print_human(results: list[CheckResult]) -> None:
    for result in results:
        if result.ok:
            status = "ok"
        elif result.severity == "warning":
            status = "warning"
        else:
            status = "error"
        print(f"[supply-chain-governance] {status}: {result.name} ({result.detail})")


def result_payload(results: list[CheckResult]) -> dict[str, object]:
    return {
        "ok": not has_blocking_failures(results),
        "checks": [result.to_json() for result in results],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Check CI/CD and supply-chain governance baselines.")
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON.")
    args = parser.parse_args(argv)

    root = args.repo_root.resolve()
    results = collect_checks(root)
    if args.json:
        print(json.dumps(result_payload(results), indent=2, sort_keys=True))
    else:
        print_human(results)
    return 1 if has_blocking_failures(results) else 0


if __name__ == "__main__":
    raise SystemExit(main())

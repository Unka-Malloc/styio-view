"""Truthful cross-platform delivery contract for Styio IDE."""

from __future__ import annotations

import argparse
import dataclasses
import json
import pathlib
import re
import shutil
import sys
from collections.abc import Mapping, Set


PLATFORMS = ("windows", "macos", "linux")
REQUIRED_TOOLS = {
    "windows": frozenset({"flutter", "python", "powershell"}),
    "macos": frozenset({"flutter", "python", "hdiutil"}),
    "linux": frozenset({"flutter", "python", "dpkg-deb", "xvfb-run"}),
}
COMMIT_PATTERN = re.compile(r"^[0-9a-f]{40,64}$")
SOURCE_FINGERPRINT_PATTERN = re.compile(r"^[0-9a-f]{64}$")


@dataclasses.dataclass(frozen=True)
class DeliveryLaneResult:
    platform: str
    status: str
    reason: str

    def to_json(self) -> dict[str, object]:
        return dataclasses.asdict(self)


def load_delivery_contract(root: pathlib.Path) -> dict[str, object]:
    path = root / "packaging" / "styio_ide" / "desktop-delivery.json"
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("desktop delivery contract must be an object")
    return payload


def evaluate_lane(
    *,
    platform: str,
    host_platform: str,
    available_tools: Set[str],
    evidence: Mapping[str, object] | None,
) -> DeliveryLaneResult:
    if platform not in PLATFORMS:
        return DeliveryLaneResult(platform, "failed", "unsupported platform")
    if host_platform != platform:
        return DeliveryLaneResult(
            platform,
            "blocked",
            f"{platform} delivery requires a matching host platform",
        )
    missing_tools = sorted(REQUIRED_TOOLS[platform].difference(available_tools))
    if missing_tools:
        return DeliveryLaneResult(
            platform,
            "blocked",
            "required host tools are unavailable: " + ", ".join(missing_tools),
        )
    if evidence is None:
        return DeliveryLaneResult(platform, "failed", "launch evidence is missing")
    if evidence.get("schema_version") != 1 or evidence.get("platform") != platform:
        return DeliveryLaneResult(platform, "failed", "evidence schema or platform is invalid")
    if not COMMIT_PATTERN.fullmatch(str(evidence.get("commit", ""))):
        return DeliveryLaneResult(platform, "failed", "evidence source commit is invalid")
    if not SOURCE_FINGERPRINT_PATTERN.fullmatch(
        str(evidence.get("source_fingerprint", ""))
    ):
        return DeliveryLaneResult(platform, "failed", "evidence source fingerprint is invalid")
    if evidence.get("artifact_verified") is not True:
        return DeliveryLaneResult(platform, "failed", "package artifact was not verified")
    if evidence.get("launched") is not True:
        return DeliveryLaneResult(platform, "failed", "packaged Styio IDE did not launch")
    if evidence.get("workspace_opened") is not True:
        return DeliveryLaneResult(platform, "failed", "workspace open smoke did not complete")
    capabilities = evidence.get("capabilities")
    if not isinstance(capabilities, Mapping):
        return DeliveryLaneResult(platform, "failed", "capability evidence is missing")
    if capabilities.get("editor") != "available" or capabilities.get("workspace") != "available":
        return DeliveryLaneResult(platform, "failed", "required IDE capabilities are unavailable")
    agent = capabilities.get("agent")
    if agent not in {"available", "unavailable"}:
        return DeliveryLaneResult(platform, "failed", "Agent capability state is not truthful")
    if agent == "unavailable" and not str(capabilities.get("agent_reason", "")).strip():
        return DeliveryLaneResult(platform, "failed", "unavailable Agent capability lacks a reason")
    return DeliveryLaneResult(platform, "passed", "complete launch and capability evidence")


def validate_repository(root: pathlib.Path) -> list[str]:
    errors: list[str] = []
    try:
        contract = load_delivery_contract(root)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        return [f"desktop delivery contract is invalid: {error}"]
    if contract.get("schema_version") != 1:
        errors.append("desktop delivery schema_version must be 1")
    if contract.get("product") != "styio_ide":
        errors.append("desktop delivery product must be styio_ide")
    if set(contract.get("platforms", [])) != set(PLATFORMS):
        errors.append("desktop delivery must declare windows, macos, and linux")

    for platform in PLATFORMS:
        manifest_path = root / "packaging" / platform / "nightly.json"
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            errors.append(f"{manifest_path.relative_to(root)}: {error}")
            continue
        if manifest.get("schema_version") != 1 or manifest.get("platform") != platform:
            errors.append(f"{manifest_path.relative_to(root)}: invalid schema/platform")
        if manifest.get("product") != "styio_ide":
            errors.append(f"{manifest_path.relative_to(root)}: product must be styio_ide")
        build_path = str(manifest.get("build_relative_path", ""))
        if not build_path.startswith("products/styio_ide/build/"):
            errors.append(f"{manifest_path.relative_to(root)}: build path escapes Styio IDE")
        signing = manifest.get("signing")
        if not isinstance(signing, dict) or signing.get("status") not in {
            "configured",
            "explicit-gap",
        }:
            errors.append(f"{manifest_path.relative_to(root)}: signing state is not explicit")
        elif signing.get("status") == "explicit-gap" and not str(
            signing.get("reason", "")
        ).strip():
            errors.append(f"{manifest_path.relative_to(root)}: signing gap lacks a reason")

    package_script = root / "scripts" / "package-nightly.py"
    try:
        package_text = package_script.read_text(encoding="utf-8").lower()
    except OSError as error:
        errors.append(f"scripts/package-nightly.py: {error}")
    else:
        for obsolete in ("vityo-nightly", "/opt/vityo", "prefix=\"vityo\""):
            if obsolete in package_text:
                errors.append(f"scripts/package-nightly.py: obsolete product marker {obsolete}")

    workflow_path = root / ".github" / "workflows" / "local-ci-gate.yml"
    try:
        workflow = workflow_path.read_text(encoding="utf-8")
    except OSError as error:
        errors.append(f".github/workflows/local-ci-gate.yml: {error}")
    else:
        for platform in PLATFORMS:
            if f"scripts/package-nightly.py --platform {platform}" not in workflow:
                errors.append(f"local-ci-gate.yml: missing {platform} package lane")
            if f"styio-ide-{platform}-package-smoke" not in workflow:
                errors.append(f"local-ci-gate.yml: missing {platform} truthful smoke marker")
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=pathlib.Path, required=True)
    parser.add_argument("--platform", choices=PLATFORMS)
    parser.add_argument("--evidence", type=pathlib.Path)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    errors = validate_repository(args.repo_root.resolve())
    lane = None
    if not errors and args.platform is not None:
        if args.evidence is None or not args.evidence.is_file():
            errors.append("desktop delivery evidence file is missing")
        else:
            evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
            host_platform = {
                "win32": "windows",
                "darwin": "macos",
                "linux": "linux",
            }.get(sys.platform, sys.platform)
            available_tools = {
                tool
                for tool in REQUIRED_TOOLS[args.platform]
                if shutil.which(tool) is not None
            }
            lane = evaluate_lane(
                platform=args.platform,
                host_platform=host_platform,
                available_tools=available_tools,
                evidence=evidence,
            )
            if lane.status != "passed":
                errors.append(f"{args.platform} lane {lane.status}: {lane.reason}")
    payload = {
        "ok": not errors,
        "errors": errors,
    }
    if lane is not None:
        payload["lane"] = lane.to_json()
    if args.json:
        print(json.dumps(payload, indent=2, sort_keys=True))
    elif errors:
        for error in errors:
            print(error, file=sys.stderr)
    else:
        print("Styio IDE desktop delivery contract is valid")
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())

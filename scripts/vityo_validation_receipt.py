"""Schema and persistence boundary for Vityo validation receipts."""

from __future__ import annotations

import json
import os
import pathlib
import re
import tempfile
from collections.abc import Mapping, Sequence


REQUIRED_IDE_REQUIREMENTS = tuple(
    f"REQ-IDE-{index:03d}" for index in range(1, 9)
)
SUPPORTED_HOST_PLATFORMS = ("windows", "macos", "linux")
MAX_RECEIPT_BYTES = 256 * 1024
_SHA256 = re.compile(r"^[0-9a-f]{64}$")
_COMMIT = re.compile(r"^[0-9a-f]{40,64}$")


class ValidationReceiptError(ValueError):
    """Bounded stable failure raised for an invalid validation receipt."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(f"{code}: {message}")
        self.code = code


def validate_full_suite_plan(plan: Sequence[Mapping[str, object]]) -> None:
    requirements: list[str] = []
    suites: list[str] = []
    for item in plan:
        requirement = item.get("requirement")
        suite = item.get("suite")
        if not isinstance(requirement, str) or not isinstance(suite, str):
            raise ValidationReceiptError(
                "invalid_requirement_mapping",
                "each full-suite entry requires string requirement and suite",
            )
        requirements.append(requirement)
        suites.append(suite)
    if (
        tuple(requirements) != REQUIRED_IDE_REQUIREMENTS
        or len(set(requirements)) != len(requirements)
        or len(set(suites)) != len(suites)
        or any(not suite.strip() for suite in suites)
    ):
        raise ValidationReceiptError(
            "invalid_requirement_mapping",
            "full-suite mapping must contain each IDE requirement once",
        )


def _validate_outcomes(
    outcomes: Mapping[str, Mapping[str, object]],
) -> None:
    if tuple(outcomes) != REQUIRED_IDE_REQUIREMENTS:
        raise ValidationReceiptError(
            "missing_requirement_outcome",
            "receipt must contain every IDE requirement in canonical order",
        )
    for requirement, outcome in outcomes.items():
        if outcome.get("status") not in {"passed", "failed", "blocked"}:
            raise ValidationReceiptError(
                "invalid_requirement_outcome",
                f"{requirement} has no truthful terminal status",
            )
        if not isinstance(outcome.get("suite"), str):
            raise ValidationReceiptError(
                "invalid_requirement_outcome",
                f"{requirement} has no suite reference",
            )


def _validate_digest(value: str, field: str) -> None:
    if not _SHA256.fullmatch(value):
        raise ValidationReceiptError(
            "invalid_evidence_digest",
            f"{field} must be lowercase SHA-256",
        )


def build_ide_receipt(
    *,
    start_fingerprint: str,
    end_fingerprint: str,
    commit: str,
    platform: str,
    outcomes: Mapping[str, Mapping[str, object]],
    protocol_schema_sha256: str,
    acceptance_fixtures_sha256: str,
    failure_code: str | None = None,
) -> dict[str, object]:
    if not _SHA256.fullmatch(start_fingerprint):
        raise ValidationReceiptError(
            "invalid_source_fingerprint",
            "start fingerprint must be lowercase SHA-256",
        )
    if start_fingerprint != end_fingerprint:
        raise ValidationReceiptError(
            "source_fingerprint_drift",
            "declared sources changed during full validation",
        )
    if not _COMMIT.fullmatch(commit):
        raise ValidationReceiptError(
            "invalid_commit",
            "commit must be a hexadecimal object identifier",
        )
    if platform not in SUPPORTED_HOST_PLATFORMS:
        raise ValidationReceiptError(
            "invalid_platform",
            "validation platform is unsupported",
        )
    _validate_digest(protocol_schema_sha256, "protocol_schema_sha256")
    _validate_digest(
        acceptance_fixtures_sha256,
        "acceptance_fixtures_sha256",
    )
    _validate_outcomes(outcomes)
    overall_status = (
        "passed"
        if all(outcome["status"] == "passed" for outcome in outcomes.values())
        else "failed"
    )
    return {
        "schema_version": 1,
        "product": "vityo",
        "suite": "full",
        "status": overall_status,
        "failure_code": None if overall_status == "passed" else failure_code,
        "commit": commit,
        "platform": platform,
        "source_fingerprint": start_fingerprint,
        "protocol_schema_sha256": protocol_schema_sha256,
        "acceptance_fixtures_sha256": acceptance_fixtures_sha256,
        "requirements": {
            requirement: dict(outcome)
            for requirement, outcome in outcomes.items()
        },
    }


def build_ide_failure_receipt(
    *,
    failure_code: str,
    commit: str | None,
    platform: str | None,
    source_fingerprint: str | None,
    protocol_schema_sha256: str | None,
    acceptance_fixtures_sha256: str | None,
    outcomes: Mapping[str, Mapping[str, object]],
) -> dict[str, object]:
    _validate_outcomes(outcomes)
    if commit is not None and not _COMMIT.fullmatch(commit):
        commit = None
    if (
        platform is not None
        and platform not in SUPPORTED_HOST_PLATFORMS
    ):
        platform = None
    if (
        source_fingerprint is not None
        and not _SHA256.fullmatch(source_fingerprint)
    ):
        source_fingerprint = None
    if (
        protocol_schema_sha256 is not None
        and not _SHA256.fullmatch(protocol_schema_sha256)
    ):
        protocol_schema_sha256 = None
    if (
        acceptance_fixtures_sha256 is not None
        and not _SHA256.fullmatch(acceptance_fixtures_sha256)
    ):
        acceptance_fixtures_sha256 = None
    return {
        "schema_version": 1,
        "product": "vityo",
        "suite": "full",
        "status": "failed",
        "failure_code": failure_code,
        "commit": commit,
        "platform": platform,
        "source_fingerprint": source_fingerprint,
        "protocol_schema_sha256": protocol_schema_sha256,
        "acceptance_fixtures_sha256": acceptance_fixtures_sha256,
        "requirements": {
            requirement: dict(outcome)
            for requirement, outcome in outcomes.items()
        },
    }


def write_receipt_atomic(
    destination: pathlib.Path,
    payload: Mapping[str, object],
) -> None:
    encoded = (
        json.dumps(
            payload,
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        ).encode("utf-8")
        + b"\n"
    )
    if len(encoded) > MAX_RECEIPT_BYTES:
        raise ValidationReceiptError(
            "receipt_too_large",
            "validation receipt exceeds the bounded artifact size",
        )
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: pathlib.Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb",
            prefix=f".{destination.name}.",
            suffix=".tmp",
            dir=destination.parent,
            delete=False,
        ) as handle:
            temporary_path = pathlib.Path(handle.name)
            handle.write(encoded)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, destination)
    finally:
        if temporary_path is not None and temporary_path.exists():
            temporary_path.unlink()

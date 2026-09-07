"""Pure upgrade and uninstall policy simulation for the packaged daemon.

This module deliberately operates on caller-provided fixture state only.  It is
used by release gates to prove ordering and retention without touching a live
daemon database or a user's files.
"""

from __future__ import annotations

import copy
import dataclasses
import hashlib
import json
from collections.abc import Mapping, Sequence


REQUIRED_STATE_KEYS = frozenset(
    {
        "schema_version",
        "workspace_metadata",
        "acknowledged_dirty_buffers",
        "transaction_journal",
        "agent_journal",
        "settings",
        "credential_references",
    }
)
FORBIDDEN_SECRET_KEYS = frozenset(
    {"credential", "credentials", "password", "secret", "token", "authorization", "cookie"}
)


@dataclasses.dataclass(frozen=True)
class LifecycleResult:
    status: str
    phase: str
    state: dict[str, object]
    checkpoint_digest: str
    reclamation_plan: tuple[str, ...] = ()
    reason: str = ""


def state_digest(state: Mapping[str, object]) -> str:
    """Return a stable content digest without embedding machine identity."""

    encoded = json.dumps(
        state, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def validate_fixture_state(state: Mapping[str, object]) -> None:
    missing = REQUIRED_STATE_KEYS.difference(state)
    if missing:
        raise ValueError("durable fixture is missing: " + ", ".join(sorted(missing)))
    schema_version = state.get("schema_version")
    if not isinstance(schema_version, int) or schema_version < 1:
        raise ValueError("durable fixture schema_version must be a positive integer")
    references = state.get("credential_references")
    if not isinstance(references, Sequence) or isinstance(references, (str, bytes)):
        raise ValueError("credential_references must be a list of opaque references")
    if not all(isinstance(value, str) and value.startswith("ref:") for value in references):
        raise ValueError("credential_references may contain opaque ref: values only")
    _reject_secrets(state)


def _reject_secrets(value: object, path: tuple[str, ...] = ()) -> None:
    if isinstance(value, Mapping):
        for key, nested in value.items():
            normalized = str(key).replace("-", "_").lower()
            if normalized in FORBIDDEN_SECRET_KEYS:
                raise ValueError("durable fixture contains forbidden secret material")
            _reject_secrets(nested, (*path, str(key)))
    elif isinstance(value, Sequence) and not isinstance(value, (str, bytes)):
        for nested in value:
            _reject_secrets(nested, path)


def simulate_upgrade(
    state: Mapping[str, object],
    *,
    candidate_schema_version: int,
    active_blockers: Sequence[str] = (),
    interrupt_after_checkpoint: bool = False,
    health_check_passes: bool = True,
) -> LifecycleResult:
    """Simulate checkpoint, migration, health validation, and rollback ordering."""

    validate_fixture_state(state)
    checkpoint = copy.deepcopy(dict(state))
    checkpoint_digest = state_digest(checkpoint)
    current_schema = int(checkpoint["schema_version"])
    if active_blockers:
        return LifecycleResult(
            "decision-required",
            "quiescence",
            checkpoint,
            checkpoint_digest,
            reason="active work prevents silent replacement",
        )
    if candidate_schema_version not in {current_schema, current_schema + 1}:
        return LifecycleResult(
            "rejected",
            "version-gate",
            checkpoint,
            checkpoint_digest,
            reason="candidate schema is not an additive compatible upgrade",
        )
    if interrupt_after_checkpoint:
        return LifecycleResult(
            "rolled-back",
            "checkpoint",
            checkpoint,
            checkpoint_digest,
            reason="upgrade interrupted after durable checkpoint",
        )

    candidate = copy.deepcopy(checkpoint)
    candidate["schema_version"] = candidate_schema_version
    if not health_check_passes:
        return LifecycleResult(
            "rolled-back",
            "health-validation",
            checkpoint,
            checkpoint_digest,
            reason="candidate health validation failed",
        )
    return LifecycleResult(
        "committed",
        "activation",
        candidate,
        checkpoint_digest,
    )


def simulate_uninstall(state: Mapping[str, object]) -> LifecycleResult:
    """Prove that uninstall removes no retained durable state."""

    validate_fixture_state(state)
    retained = copy.deepcopy(dict(state))
    return LifecycleResult(
        "retained",
        "uninstall",
        retained,
        state_digest(retained),
        reason="application components are removed separately from user state",
    )


def plan_reclamation(
    state: Mapping[str, object], *, explicitly_confirmed: bool
) -> LifecycleResult:
    """Produce a deletion plan only; never delete or mutate fixture state."""

    validate_fixture_state(state)
    retained = copy.deepcopy(dict(state))
    digest = state_digest(retained)
    if not explicitly_confirmed:
        return LifecycleResult(
            "confirmation-required",
            "reclamation",
            retained,
            digest,
            reason="reclamation requires a separate explicit confirmation",
        )
    return LifecycleResult(
        "planned",
        "reclamation",
        retained,
        digest,
        reclamation_plan=tuple(sorted(REQUIRED_STATE_KEYS)),
        reason="plan only; no user data was modified",
    )

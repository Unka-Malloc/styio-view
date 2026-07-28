# Styio Coding Agent — Validation

**Plan:** `styio-coding-agent`
**Purpose:** Map Agent requirements to focused suites and one final full regression.
**Last updated:** 2026-07-26

## Validation runner contract

`scripts/styio_quality.py` runs the Coding Agent package, shared protocol package, integration
fixtures, and benchmarks from their own working directories. Fixtures use fake providers/hosts by
default; live provider credentials are never required for the deterministic release floor and are
never printed or persisted.

Focused suites run once in their owning lifecycle. `coding-agent/full` runs exactly once after every
Coding Agent implementation lifecycle closes.

## Requirement matrix

| Requirement | Focused proof | Product proof |
|---|---|---|
| REQ-AGENT-001 | `python scripts/styio_quality.py --product coding-agent --suite headless-runtime` | Pure dependency graph plus CLI start/complete/cancel/failure smoke without IDE |
| REQ-AGENT-002 | `--suite providers` | Stream, usage, timeout, cancellation, retry/idempotency, failover, budget fixtures |
| REQ-AGENT-003 | `--suite context` | Relevance, revision invalidation, deterministic compaction, redaction, cache and memory budgets |
| REQ-AGENT-004 | `--suite tools-mcp` | Schema, discovery/revocation, cancellation, malformed/oversized output, server-loss conformance |
| REQ-AGENT-005 | `--suite agent-security` | Roots/traversal/symlink, permissions, hooks, network, secrets, token audience, destructive effects |
| REQ-AGENT-006 | `--suite coding-loop` | Bug-fix/refactor fixtures, revisioned change sets, post-edit facts, repair and loop guards |
| REQ-AGENT-007 | `--suite session-recovery` | Crash/restart, corrupted tail, idempotent effect recovery, redacted correlated receipts |
| REQ-AGENT-008 | `--suite multi-agent` | DAG scheduling, concurrency bound, worktree isolation, leases, collision/conflict/cancellation |
| REQ-AGENT-009 | `--suite protocol-integration` | Shared protocol conformance, concurrent real IDE/Agent sessions, unsupported-version failure |

## Deterministic evaluation corpus

The release floor contains repository-owned, license-compatible fixtures for:

- localized bug repair;
- cross-file refactor with stale base;
- failing test diagnosis and bounded repair;
- tool/MCP disappearance during a turn;
- provider stream interruption before and after an effect;
- context poisoning/untrusted tool output;
- permission/root/network/secret denial;
- crash between effect execution and receipt acknowledgement;
- two independent parallel tasks and one ownership collision.

Each fixture has machine-checkable acceptance criteria, expected allowed effects, maximum steps/tool
rounds, and latency/memory budgets. Evaluation compares final repository facts and receipts, not
natural-language self-reports.

## Focused closure rules

1. Run only the owning suite plus analyze for affected packages.
2. Use fixed fake-provider seeds/chunks and virtual clocks for retry/timeout behavior.
3. Record content/version digests for protocol schemas and fixtures.
4. Repair ordinary defects in the same lifecycle.
5. Route failures in an already closed lifecycle back through that lifecycle; do not add shims.
6. Do not run `coding-agent/full` until all implementation lifecycles close.

## Final validation

Run once on one head commit:

```text
python scripts/styio_quality.py --product coding-agent --suite full
```

The full suite must include:

- format/analyze and all Agent/protocol tests;
- headless CLI product scenarios;
- provider, context, MCP/tool, policy/security, coding-loop, recovery, and multi-agent fixtures;
- real Styio IDE protocol integration with two concurrent sessions;
- cancellation, latency, memory, event-buffer, and tool-output budgets;
- one-time full deterministic evaluation corpus;
- Better Plan validation and requirement-label traceability.

Final evidence records one outcome per `REQ-AGENT-*` label. Missing fixtures, skipped security cases,
or absent integration capability are blocked/failing outcomes, never a green release.

# RuntimeEventAdapter

**Purpose:** Freeze the ordered `RuntimeEventEnvelope` consumed by the runtime surface, debug console, and observed-run overlay intake.

**Last updated:** 2026-09-05

**Status:** Active (v2 producer mapping implemented; v1 parsers retired)

**Owner:** `products/vityo_app/lib/src/view_ide/backend_toolchain/`
**Plan traceability:** [Observable Topology Adapter](./ObservableTopologyAdapter.md), [ADR-0012](../adr/ADR-0012-runtime-event-protocol.md)

---

## 1. Envelope contract

`RuntimeEventEnvelope` is unchanged:

1. `schemaVersion`
2. `sessionId`
3. `sequence`
4. `timestamp`
5. `eventKind`
6. `origin`
7. `payload`

Generic intake now records Styio runtime-events v2 (`styio.observable.runtime-events`, schema `2`) into that envelope.

### v2 mapping

| Envelope field | Source |
|---|---|
| `schemaVersion` | `2` |
| `sessionId` | the execution session id (producer `execution_id` stays in payload) |
| `sequence` | file order through the existing normalizer |
| `timestamp` | UTC epoch plus `monotonic_ns` truncated to microseconds (not wall-clock time; exact `monotonic_ns` stays in payload) |
| `eventKind` | upstream `event_kind` verbatim |
| `origin` | `styio.observable.runtime-events` |
| `payload` | every known upstream field under its upstream name |

Known payload names include `family`, `priority`, `correlation_status`, `role`, `snapshot_id`, `site_id`, `instance_id`, `event_id`, `monotonic_ns`, `causes`, `wait`, optional per-kind fields (`from_phase`, `to_phase`, `phase`, `test_name`, `stream`, `queue_depth`, `queue_capacity`, `count`, `duration_ns`, …), and capability/summary fields. Unknown additive fields are ignored and never copied. An invalid capability stream records no envelopes.

The capability record's `snapshot_id` is `null` when the producer bound no snapshot — every plain run writes a `disabled`-mode stream with that shape. It is legal, decodes normally, and its controller events (`compile.*`, `transition.fired`, `state.changed`, `unit.*`, `log.emitted`, `diagnostic.emitted`) map to envelopes like any other record, so existing execution sessions keep their runtime lanes. Only a present but wrongly prefixed capability identity rejects the stream.

Artifact location uses the Pafio `--json` envelope `plan.build_root` and the Styio receipt `outputs.runtime_events_path` after a containment check. Inline `runtime_events` arrays and top-level `runtime_events_path` reads are gone.

Replay summary reads `from_phase` / `to_phase` for transitions. Lanes whose v1 keys are absent (`message`, `file`, `thread_id`) fall back to kind-only labels. New v2 kinds degrade to the existing unsupported lane; extending runtime-surface interpretation of those kinds is out of scope.

The hosted control-plane codec and hosted runtime-event adapter keep their own already-normalized envelopes and version lists. The `workflow_payload_version` execution-envelope drift is recorded and not fixed here.

---

## 2. Retired v1 definitions

The following intake parsers, aliases, and payload keys are deleted and must not return:

- `_readWorkflowRuntimeEvents`
- `_parsePayloadRuntimeEvents`
- `_parseRuntimeEventLines`
- `_parseRuntimeEventObject`
- inline `['runtime_events']` and `['runtime_events_path']` reads
- `payload['from']`, `payload['to']`, `payload['message']`, `payload['file']`, `payload['thread_id']`

v1 closed-key envelopes (`schema_version` `1`, `eventKind`, nested `payload`) are no longer produced by the local CLI adapter.

---

## 3. First required event families

Published families still include `compile.*`, `run.*`, `thread.*`, `unit.*`, `unit.test.*`, `state.*`, `transition.fired`, `log.emitted`, `diagnostic.emitted`. v2 also emits `session.*`, `task.*`, `queue.*`, `wait.*`, `aggregate.shard`, cancellation, and cooperative kinds. Consumers that do not understand a kind must degrade rather than fail.

Non-negotiable rules:

1. Events keep a stable file-order sequence inside one session.
2. Unrecognized kinds degrade; they must not crash UI.
3. Runtime surface, debug console, and the Observable overlay consume the same recorded envelopes for a session.
4. Overlay correlation is owned by `ObservableTopologyAdapter` and joins only through explicit snapshot and site identifiers.

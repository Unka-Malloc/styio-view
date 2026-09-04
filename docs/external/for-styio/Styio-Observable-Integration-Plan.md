# Styio Observable Integration Plan

**Purpose:** Define the gated Vityo consumer work that may begin only after Styio publishes accepted observable-language fixtures.

**Last updated:** 2026-09-05

**Status:** V1 authorized and implemented. V2 delta and lineage implemented; bounded query deferred. V3 remains fixture-gated.

## 1. Delivery Boundary

This plan is a downstream integration handoff, not an authorization to implement it. Styio owns the observable topology and runtime wire schemas, their semantics, identifiers, evidence, completeness rules, versions, and producer fixtures. Vityo owns only:

1. version-aware decoding and capability negotiation,
2. bounded consumer caches and staleness checks,
3. degraded or blocked states for unsupported input,
4. projection into existing inspection, graph, runtime, and debug surfaces,
5. consumer fixtures and UI-facing acceptance tests.

Vityo must not infer semantic facts from source text, compiler-private APIs, Pafio metadata, runtime timing, or UI heuristics. It must not redefine an upstream field merely to fit an existing view model.

## 2. Upstream Gates

The work is deliberately split by published producer evidence. A later stage cannot start because an earlier document exists; it starts only after the matching Styio contract version and fixture corpus are accepted.

| Vityo stage | Required Styio gate | Vityo outcome |
|---|---|---|
| V1 — static topology intake | `styio-nightly:docs/plan/observable-static-snapshot/Plan.md` (PLAN-004) publishes the first accepted snapshot fixture set and capability identifier | Decode immutable snapshots, reject unsupported versions, cache by explicit snapshot identity, and project producer-authored facts and evidence |
| V2 — delta, lineage, and query intake | `styio-nightly:docs/plan/observable-delta-query-lineage/Plan.md` (PLAN-005) publishes accepted parent/child, delta, and query fixtures | Apply deltas only to their declared parent, preserve lineage, validate query/snapshot equivalence, and bound retained history. **Delta and lineage implemented in Vityo; bounded query deferred.** |
| V3 — runtime correlation intake | `styio-nightly:docs/plan/observable-runtime-correlation/Plan.md` (PLAN-006) publishes accepted runtime-event and correlation fixtures | Join runtime events to static sites only through explicit upstream identifiers and render loss, sampling, and degraded states truthfully |

The attachment `Styio-Observable-Language-Long-Term-Evolution-2026-09-04.zip` is background reference only. It does not authorize work and cannot override repository contracts or accepted fixtures.

## 3. V1 — Static Topology Intake

**Status:** Authorized and implemented in Vityo (TASK-001). Recorded producer constants: machine-info key `observable_static_snapshot`; schema version `1`; capabilities `file-source-anchors`, `producer-evidence`, `static-topology-edges`, `static-topology-facts`, `static-topology-nodes`; Pafio `--emit-observable-static-snapshot[=<schema-version>]` and repeatable `--observable-capability <name>`.

### Inputs

1. A versioned immutable snapshot envelope.
2. Explicit capability and completeness declarations.
3. Opaque snapshot, node, edge, fact, evidence, and source-anchor identifiers where the published version provides them.
4. Privacy-safe producer fixtures, including unknown-field and unsupported-version cases.

### Planned work

1. Add a dedicated observable-topology decoder and consumer model rather than extending `ProjectGraphAdapter`.
2. Preserve unknown optional fields according to the negotiated version while failing closed on an unknown required major version.
3. Cache immutable snapshots by upstream snapshot identity with an explicit, bounded eviction policy.
4. Surface incomplete, unavailable, unsupported, and stale states without inventing missing topology.
5. Project only producer-authored facts and evidence into existing Vityo surfaces.

### Acceptance gate

1. Every accepted Styio snapshot fixture decodes deterministically.
2. Unsupported versions and missing required capabilities become stable blocked states, not crashes or guessed data.
3. Repeated intake of one snapshot is idempotent.
4. No absolute path, raw source, runtime value, compiler address, or compiler-private identifier is persisted or displayed unless a later public contract explicitly authorizes it.
5. Existing editing, build, run, and non-observable surfaces behave unchanged when the capability is absent.

## 4. V2 — Delta, Lineage, and Query Intake

**Status:** Delta and lineage implemented in Vityo. Bounded query remains deferred.

### Planned work

1. Require exact parent snapshot identity before applying a delta.
2. Reject stale, duplicate, out-of-order, or wrong-parent deltas with machine-readable reasons.
3. Retain only the bounded lineage and cache window required by the published contract.
4. Treat producer queries as views over published snapshot facts; do not call private language-service or compiler APIs as a fallback.
5. Replace a cached child only after the reconstructed result passes the upstream fixture expectations.

### Acceptance gate

1. Applying each accepted delta fixture to its declared parent yields the accepted child snapshot.
2. Query results match the equivalent facts in the accepted snapshot fixtures.
3. Wrong-parent, stale, duplicate, and unsupported-version cases leave the last valid projection intact and expose a clear degraded state.
4. Cache size and retained lineage remain bounded under repeated updates.

## 5. V3 — Runtime Correlation Intake

### Planned work

1. Extend the existing execution intake with a dedicated adapter layer for the Styio observable runtime-event contract.
2. Correlate events with static snapshots and semantic sites only through explicit snapshot, site, and instance identifiers.
3. Preserve causal, wait, scheduler, loss, sampling, and aggregation declarations from the producer.
4. Project one accepted event stream into graph, timeline, runtime surface, and debug console views without creating competing interpretations.
5. Bound event buffering and render pressure according to the published contract and Vityo cache policy.

### Acceptance gate

1. Accepted fixture streams yield deterministic projections across all consuming surfaces.
2. Events with an unknown snapshot or site remain visible as uncorrelated/degraded; they are never joined by names, timestamps, source positions, or ordering guesses.
3. Loss and sampling remain visible and prevent the UI from presenting an incomplete stream as complete.
4. Unknown optional event kinds degrade safely; unsupported required schema versions fail closed.
5. Observable intake adds no behavior change when the upstream capability is disabled.

## 6. Existing Contract Reconciliation

`vityo-nightly:docs/contracts/RuntimeEventAdapter.md` and `vityo-nightly:docs/adr/ADR-0012-runtime-event-protocol.md` remain the generic ordered compile/run shell used by current surfaces. They do not own the future Styio observable runtime schema. When V3 starts, the adapter must map the upstream versioned envelope into Vityo's existing session model without renaming, dropping, or redefining upstream semantics. Any incompatible duplicate field definition must be retired through one explicit contract migration before implementation is accepted.

`vityo-nightly:docs/contracts/ProjectGraphAdapter.md` remains the owner of package, workspace, dependency, target, and hosted-route projection. Observable semantic topology is a separate producer contract and must not be folded into the Pafio-backed project graph.

`vityo-nightly:docs/design/Vityo-Protocol-And-Capability-Negotiation.md` supplies Vityo's general versioning and degradation policy. A Styio contract-specific rule takes precedence for Styio payload semantics.

## 7. Non-Goals and Safety Rules

This plan does not authorize:

1. changes under `prototype/`, or removal, movement, or renaming of that directory,
2. an alternative topology or runtime protocol owned by Vityo,
3. compiler-private linkage or parsing human stderr,
4. semantic joins based on names, timestamps, content hashes, absolute paths, or UI heuristics,
5. backend telemetry storage, cloud ingestion, distributed tracing, replay, policy, or raw runtime-value capture,
6. starting V2 or V3 before its upstream fixture gate is accepted.

## 8. Activation Checklist

A stage can be converted into an authorized implementation plan only when all of the following are true:

1. the matching Styio plan is completed and its public contract version is advertised,
2. producer fixtures and privacy rules are available without access to compiler internals,
3. the Vityo owner records the exact supported version and capability names,
4. focused decoder, degradation, staleness, and projection tests are specified,
5. the benchmark repository has a corresponding performance measurement route,
6. the implementation scope preserves existing product behavior and the `prototype/` boundary.

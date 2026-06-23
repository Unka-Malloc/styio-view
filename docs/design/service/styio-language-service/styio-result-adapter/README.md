# Styio Result Adapter

**Purpose:** Define how Vityo adapts, binds, caches, and exposes StyioService results without turning Vityo state into Styio language truth.

**Last updated:** 2026-05-14

**Status:** Draft for review

## 1. Module Summary

`Styio Result Adapter` is the middle component inside the Vityo Service Layer.

It sits between:

| Side | Component | Role |
|------|-----------|------|
| Left | Styio Service Connector | Sends requests to StyioService and receives protocol responses. |
| Middle | Styio Result Adapter | Adapts StyioService results, binds them to Vityo document state, and decides whether to cache or persist them locally. |
| Right | Vityo Service Result Consumer | Consumes adapted service results for diagnostics, completion, hover, semantic tokens, code actions, rename, navigation, or future service-specific product intake. |

The Adapter owns the binding logic. The two sides are auxiliary: they provide input and consume output, but they do not decide how Styio results bind to Vityo state.

## 2. Core Rule

```text
Bidirectional protocol, unidirectional language-fact binding.
```

Protocol communication may be bidirectional:

```text
Vityo -> StyioService: request
StyioService -> Vityo: response or notification
```

Language-fact binding must be one-way:

```text
StyioService result -> Styio Result Adapter -> Vityo service-bound language state
```

Vityo service-bound language state must not flow back into StyioService as language truth.

## 3. Allowed Flows

| Flow | Allowed | Meaning |
|------|---------|---------|
| Vityo request -> StyioService | Yes | Vityo may request syntax checks, semantic snapshots, hover, completion, semantic tokens, rename, code actions, and references. |
| StyioService result -> Styio Result Adapter | Yes | StyioService returns language facts, diagnostics, tokens, references, edits, and capability-specific payloads. |
| Styio Result Adapter -> Vityo service-bound language state | Yes | The Adapter writes adapted results into Vityo-side caches, snapshots, or intake models. |
| Vityo applied edit -> StyioService revalidation request | Yes | After Vityo applies an edit to a document or workspace, it may request revalidation. |
| Vityo configuration -> StyioService startup/request | Yes | Toolchain path, protocol mode, endpoint, feature flags, and timeout policy may shape requests. |

## 4. Forbidden Flows

| Flow | Allowed | Reason |
|------|---------|--------|
| Vityo language cache -> StyioService semantic model | No | Cached Vityo results are not language truth. |
| Fallback result -> StyioService fact store | No | Fallback behavior preserves product usability only and must not pollute Styio truth. |
| UI state -> StyioService semantic state | No | Cursor, hover widget, popup, panel, and theme state are product state, not language facts. |
| Adapted Vityo DTO -> StyioService AST or semantic graph | No | The Adapter is not a reverse compiler or semantic serializer. |
| Stale result -> current Vityo state | No | Results must match the current document identity and revision before binding. |

## 5. Binding Responsibilities

The Adapter is responsible for:

| Responsibility | Description |
|----------------|-------------|
| Result normalization | Convert StyioService protocol payloads into Vityo internal DTOs. |
| Document binding | Attach document URI, document revision, snapshot ID, and validation mode to every adapted result. |
| Stale-result rejection | Reject results that do not match the current document identity or revision. |
| Capability binding | Attach capability metadata such as syntax, semantic, hover, completion, rename, and code action support. |
| Error binding | Normalize StyioService errors into Vityo diagnostic, status, or recovery records. |
| Cache write policy | Decide whether a valid adapted result should be written to `Language Result Cache`. |
| Persistence policy | Decide whether a result may be persisted locally for later startup, offline, or last-known-good use. |
| Degraded-state marking | Mark fallback or last-known-good results as degraded or stale before Vityo consumes them. |

## 6. Adapter Inputs

| Input | Source | Notes |
|-------|--------|-------|
| StyioService response | Styio Service Connector | Protocol response from CLI, LSP, daemon, or future embedded API. |
| Document identity | Vityo document model | URI, workspace root, language mode, and open-buffer identity. |
| Document revision | Vityo document model | Required for stale-result rejection. |
| Capability state | Capability Detector | Observes whether a response carried fresh payload, empty payload, unavailable, failed, protocol-error, or stale state for each capability. Empty payload must not be treated as unsupported. |
| Cache policy | Configuration Store | Controls TTL, persistence, last-known-good behavior, and cleanup. |
| Fallback policy | Fallback Registry | Controls degraded behavior and fallback visibility. |

## 7. Adapter Outputs

| Output | Consumer | Notes |
|--------|----------|-------|
| Adapted diagnostics | Diagnostic Intake | Editor squiggles, problems state, and quick-fix availability. |
| Adapted completion items | Completion Intake | Popup-ready completion records. |
| Adapted hover content | Hover Intake | Renderable hover payloads. |
| Adapted semantic tokens | Semantic Token Intake | Theme-mappable spans. |
| Adapted code actions | Code Action Intake | Previewable workspace edits. |
| Adapted rename result | Rename Intake | Safety result and workspace edit preview. |
| Bound language snapshot | Language Result Cache | Schema-state tracked local cache entry. |
| Capability or error status | App Shell surfaces | User-facing status and recovery guidance. |

## 8. Binding Decision Table

| Styio result state | Document revision match | Capability state | Adapter action |
|--------------------|-------------------------|------------------|----------------|
| success | match | available | Normalize, bind, cache if policy allows, then expose to Vityo intake. |
| success | mismatch | any | Drop as stale and optionally record a stale-result metric. |
| error | match | available | Normalize error into diagnostics or status, then expose to relevant Vityo intake or App Shell Surface. |
| unavailable | match | degraded allowed | Mark degraded, use local fallback only inside the responsible feature, and never label it Styio truth. |
| unavailable | match | disabled | Do not call fallback; surface disabled capability status. |
| success | match | incompatible | Do not bind as current truth; surface compatibility error. |

## 9. Cache And Persistence Rule

`Language Result Cache` is downstream of the Adapter.

```text
StyioService result -> Styio Result Adapter -> Language Result Cache
```

The cache stores adapted result snapshots. It does not own binding rules and does not decide Styio truth.

Persistence is optional and feature-specific. If a result is persisted for startup, offline, or last-known-good use, it must carry:

| Field | Reason |
|-------|--------|
| source | Must identify StyioService, fallback, or last-known-good source. |
| documentRevision | Required to prevent stale binding. |
| snapshotId | Required to correlate result families. |
| contractVersion | Required to detect Styio grammar or protocol drift. |
| degraded | Required when the result is not fresh StyioService truth. |
| createdAt | Required for retention and stale-state display. |

## 10. Ownership Boundary

| Responsibility | Owner |
|----------------|-------|
| Sending requests to StyioService | Styio Service Connector |
| Receiving protocol responses | Styio Service Connector |
| Binding Styio results to Vityo document state | Styio Result Adapter |
| Rejecting stale language results | Styio Result Adapter |
| Writing adapted results to cache | Styio Result Adapter |
| Storing cache entries | Language Result Cache |
| Consuming adapted results for editor behavior | Vityo Service Result Consumer |
| Rendering widgets, popups, panels, and themes | Interaction Layer and Appearance Layer |
| Producing Styio language truth | StyioService |

## 11. Non-Goals

1. This module does not implement Styio parsing or semantic analysis.
2. This module does not reverse Vityo state into StyioService state.
3. This module does not decide UI rendering.
4. This module does not own process startup, endpoint discovery, or toolchain selection.
5. This module does not make fallback results equivalent to StyioService results.

## 12. First Implementation Sketch

1. Define a `BoundStyioResult` DTO with document URI, document revision, snapshot ID, capability, source, freshness, and payload.
2. Implement adapter functions per result family: diagnostics, completion, hover, semantic tokens, code actions, rename, and references.
3. Reject mismatched document revisions before writing any result to Vityo state.
4. Write accepted results to `Language Result Cache` only through Adapter-controlled policy.
5. Mark fallback or last-known-good payloads as degraded before they reach Vityo intake.
6. Add fixture-based tests for fresh, stale, incompatible, unavailable, degraded, and disabled binding cases.

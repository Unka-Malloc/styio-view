# Observable Topology Adapter

**Purpose:** Freeze the Vityo consumer contract for Styio observable static snapshot schema v1 plus producer delta and lineage intake: negotiated capabilities, producer snapshot identity, fail-closed decode, transactional apply, bounded cache and lineage window, producer-delta change highlighting, refresh loop, workbench surface, and the remaining V3 seam.

**Last updated:** 2026-09-05

**Status:** Active (V1 implemented; V2 delta and lineage implemented; bounded query deferred)

**Owner:** `products/vityo_app/lib/src/view_ide/services/observable_topology/`
**Plan traceability:** [Styio Observable Integration Plan](../external/for-styio/Styio-Observable-Integration-Plan.md), [Workbench Shell Surfaces](./WorkbenchShellSurfaces.md), [Vityo Protocol And Capability Negotiation](../design/Vityo-Protocol-And-Capability-Negotiation.md)

---

## 1. Upstream constants (confirmed 2026-09-05)

These names were read from the Styio and Pafio sibling worktrees implementing the producer side. They are adapter constants, not Vityo-owned vocabulary.

| Constant | Value | Confirmation |
|---|---|---|
| Machine-info object key | `observable_static_snapshot` | Confirmed in Styio `src/main.cpp` |
| Contract name | `styio.observable.static-snapshot` | Confirmed in Styio static-snapshot contract |
| Schema version | `1` | Confirmed; Styio full variant advertises `[1]`, nano advertises `[]` |
| Stability | `incubating` | Confirmed |
| Required capabilities | `file-source-anchors`, `producer-evidence`, `static-topology-edges`, `static-topology-facts`, `static-topology-nodes` | Confirmed in Styio `StaticSnapshotContract.hpp` |
| Artifact suffix | `.observable-static-snapshot.json` | Confirmed |
| Pafio emit option | `--emit-observable-static-snapshot[=<schema-version>]` (default `1`) | Confirmed in Pafio CLI support |
| Pafio capability option | `--observable-capability <name>` (repeatable) | Confirmed in Pafio CLI support |
| Optional capability `snapshot-delta` | `snapshot-delta` | Confirmed in Styio machine-info `observable_static_snapshot.optional_capabilities` (also accepted if listed in `capabilities`) |
| Optional capability `producer-lineage` | `producer-lineage` | Confirmed in Styio machine-info `observable_static_snapshot.optional_capabilities` (also accepted if listed in `capabilities`) |
| Delta contract | `styio.observable.delta` schema `{major:0,minor:1}` stability `incubating` | Confirmed in Styio observable README |
| Compile-plan parent field | `emit.observable_static_snapshot.parent_snapshot_path` | Confirmed in Pafio compile-plan |
| Pafio parent option | `--observable-parent-snapshot <path>` | Confirmed in Pafio `Support.cpp` |
| Delta artifact suffix | `.observable-delta.json` | Confirmed in Styio `DeltaPublication.hpp`; listed in receipt `artifacts` after the snapshot |
| Receipt delta field | `observable_static_snapshot.delta` | Confirmed; Styio writes `published` or `full_snapshot_required` |
| Producer degradation | `full_snapshot_required` | Confirmed in Styio `Delta.hpp` |
| Pafio usage-error category | `UsageError` | Confirmed in Pafio `CommandError` |

Vityo never infers topology from names, timestamps, source text, absolute paths, or heuristics. Only producer-authored facts, exact opaque-ID comparison, and producer lineage records are shown.

---

## 2. Identity key

Consumer identity is the producer snapshot identity derived from the exact published artifact bytes:

`s1_` + the first 32 lowercase hex characters of SHA-256 over those bytes, including the trailing newline.

`SnapshotIdentity(snapshotId, compilationUnitKey)` equals another identity only on `snapshotId`. Cache lookup and parent/target comparison use that identity. The superseded V1 digest, producer, and schema identity components are gone.

---

## 3. Availability states and reason codes

Availability (wire values): `unavailable`, `unsupported`, `refreshing`, `fresh`, `stale`, `blocked`, `scalar-noop`.

Reason codes (wire values):

| Code | When |
|---|---|
| `no-toolchain` | Styio or Pafio missing |
| `no-manifest` | Workspace has no package manifest |
| `unsupported-platform` | Web/hosted/non-IO platform |
| `unsupported-schema-version` | Advertised schema versions do not include `1` |
| `missing-capability` | A required capability is absent |
| `publication-failed` | Pafio `check` failed after a previous valid graph |
| `invalid-snapshot` | Decoder rejected the artifact |
| `snapshot-too-large` | Node count exceeds the render bound (10,000) |
| `workspace-changed` | A refresh is in flight |
| `anchor-unresolved` | Selected node has no unique package-root match |
| `cancelled` | Internal only; never rendered |
| `full-snapshot-required` | Informational on `fresh` when no valid delta was applied |
| `wrong-parent` | Delta parent is not the retained head |
| `stale-delta` | Delta parent is a superseded retained ancestor |
| `duplicate-delta` | Delta target is the retained head |
| `out-of-order-delta` | Delta target is a retained ancestor |
| `unsupported-delta` | Delta major is not 0 or a required capability is unknown |
| `malformed-delta` | Envelope or apply rejected the delta |
| `invalid-delta` | Reconstruction identity or bytes do not match the published child |
| `delta-transport-unavailable` | Pafio `UsageError` on a parent-carrying run |

`invalid-snapshot` subcodes: `unsupported-contract`, `missing-field`, `duplicate-id`, `dangling-reference`, `evidence-cycle`, `unsupported-completeness`, `unsupported-schema-version`, `missing-capability`, plus `invalid-lineage` for kind, cardinality, identity prefix, or completeness.

Delta subcodes: `major-incompatible`, `unknown-required-capability`, `unsupported-contract`, `missing-field`, `malformed-identity`, `unknown-op`, `unknown-category`, `key-mismatch`, `duplicate-key`, `missing-record`, `before-mismatch`, `unknown-metadata-field`, `lineage-prior-unresolved`, `target-mismatch`, `reconstruction-mismatch`.

Full-snapshot details: `no-parent`, `no-delta-artifact`, `producer-full-snapshot-required`, `previous-delta-rejected`, `delta-transport-unavailable`.

Scalar-noop completeness `complete/proven-scalar-noop` is a first-class availability state: the snapshot is valid, topology collections are empty, and the canvas is not invented.

### Classification

Decode failure → `malformed-delta` or `unsupported-delta`. Major not 0 or unknown required capability → `unsupported-delta`. Parent equals head → apply. Target equals head and parent equals the predecessor → `duplicate-delta`. Target in the window but not head → `out-of-order-delta`. Parent in the window but not head → `stale-delta`. Otherwise `wrong-parent`.

### Recovery

A rejected delta keeps the previous projection as `stale` with its reason and subcode and forces the next run onto the full-snapshot path. That recovery run is `fresh` with `full-snapshot-required` and detail `previous-delta-rejected`. Deltas resume on the run after. A Pafio `UsageError` on a parent-carrying run disables deltas for the session and reruns once without the parent option.

The lineage window retains at most eight generations per compilation unit, oldest-first. The retained parent path never enters `ObservableGraphState`.

---

## 4. Refresh loop

1. Negotiate Styio machine-info and Pafio availability before any process or watcher. Optional `snapshot-delta` and `producer-lineage` are read from `observable_static_snapshot.optional_capabilities` (and still accepted if listed in `capabilities`) but never required for V1 admission.
2. On success, watch the workspace recursively. Trigger only on `.styio` files and `pafio.toml`. Ignore `*.observable-static-snapshot.json` and `*.observable-delta.json`.
3. Trailing debounce 500 ms. At most one publication in flight. A newer trigger cancels the in-flight Pafio process.
4. Publication: `pafio --json check --manifest-path <manifest> --styio-bin <styio> --emit-observable-static-snapshot=<n> --observable-capability <name>…` from the workspace root. When deltas are negotiated and a head artifact path exists, append `--observable-parent-snapshot <path>`. Without a parent reference the argument list is identical to V1.
5. Parse the Pafio stdout success envelope (`status: succeeded`; `{action, command, intent, message, mode, plan, profile, status, styio, sync, target}`), then read the Styio receipt file `<plan.build_root>/receipt.json` (receipt schema v1). Select the snapshot whose name ends `.observable-static-snapshot.json` and, when listed and contained, the delta whose name ends `.observable-delta.json`. Read receipt `observable_static_snapshot.delta` when present. Paths resolve only inside the workspace or Pafio output tree.
6. Hash the published child on the caller thread. Identical child bytes change no state; an unchanged delta riding along is still decoded, classified, applied, and verified, then changes no state. Otherwise one `compute()` intake classifies, applies, and verifies. An accepted delta uses `ObservableDeltaChangeSource`; any negotiated run without an applied delta uses V1 exact ID-set comparison and reports `full-snapshot-required` with the detail naming the cause (`no-parent` on the first run, `no-delta-artifact`, `producer-full-snapshot-required`, `previous-delta-rejected`, or `delta-transport-unavailable`). Layout stays off-thread.
7. Decode, apply, or publication failure keeps the last valid graph and marks it `stale` except for the recovery and transport rules above.

---

## 5. Workbench surface

- Bottom tab: `BottomSurfaceTab.observable`
- Title: `Observable`
- Panel id: `bottom.observable`
- Surface id: `observable.graph`
- Capabilities: `observable-topology`, `change-highlight`
- IDE capability id: `service.observable-topology`
- Widget: `products/vityo_app/lib/src/view_render/observable/`
- Keys: `observable-graph-surface`, `observable-banner`, `observable-legend`, `observable-counters`, `observable-detail`, `observable-open-anchor`, `observable-node-<id>`, `observable-badge-<id>`

Selecting a node shows kind, role, relative anchor path, producer facts, the evidence chain, Change (operations), Lineage (kind, counterparts, producer rule), and History (retained records mentioning the node). Open-anchor uses the published package identifier to join a relative path, then the existing workspace file route after a containment check. Absolute paths are never displayed. Changed items use the changed accent. Rename and move show continuity badges without prior ghosts. Split and merge draw dashed lineage links.

When the controller is absent, the tab still exists and renders `unavailable`.

---

## 6. V2 / V3 seams

- `ObservableChangeSource` has two implementations: V1 `IdSetComparisonChangeSource` and V2 `ObservableDeltaChangeSource`. The controller selects one per run. Bounded query intake remains deferred.
- Graph projection addresses nodes by `(snapshotIdentity, nodeId)`. V3 runtime overlays attach there and are not modelled here.
- Hosted/cloud publication and disk persistence of snapshots are out of scope.

---

## 7. Test map

| Area | Test file |
|---|---|
| Decoder goldens and invalid subcodes | `products/vityo_app/test/observable_snapshot_decoder_test.dart` |
| Delta envelope decoder | `products/vityo_app/test/observable_delta_decoder_test.dart` |
| Negotiation matrix | `products/vityo_app/test/observable_capability_negotiation_test.dart` |
| LRU cache and identical-byte hit | `products/vityo_app/test/observable_snapshot_cache_test.dart` |
| Transactional apply and classification | `products/vityo_app/test/observable_delta_apply_test.dart` |
| Lineage window bound | `products/vityo_app/test/observable_lineage_window_test.dart` |
| Exact ID-set and producer-delta change | `products/vityo_app/test/observable_change_set_test.dart` |
| Deterministic layout, bound, and rename slots | `products/vityo_app/test/observable_graph_layout_test.dart` |
| Pafio publisher IO / web | `products/vityo_app/test/observable_snapshot_publisher_io_test.dart` |
| Debounce, cancel, stale, delta gating, recovery | `products/vityo_app/test/observable_graph_controller_test.dart` |
| Banner, legend, counters, detail, badges, anchors | `products/vityo_app/test/observable_graph_surface_test.dart` |
| Tab, panel, capability | `products/vityo_app/test/shell_layout_plan_test.dart`, `products/vityo_app/test/ide_capability_framework_test.dart` |

Consumer snapshot fixtures live at `products/vityo_app/test/fixtures/observable_static_snapshot/v1/`. Topology, delta, lineage, and Vityo-negative fixtures live at `products/vityo_app/test/fixtures/observable_topology/` with provenance in that directory's README.

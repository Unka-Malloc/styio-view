# Observable Topology Adapter

**Purpose:** Freeze the Vityo consumer contract for Styio observable static snapshot schema v1: negotiated capabilities, snapshot identity, fail-closed decode, bounded cache, exact ID-set change highlighting, refresh loop, workbench surface, and the V2/V3 seams.

**Last updated:** 2026-09-05

**Status:** Active (V1 implemented)

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

Vityo never infers topology from names, timestamps, source text, absolute paths, or heuristics. Only producer-authored facts and exact opaque-ID comparison are shown.

---

## 2. Identity key

Schema v1 publishes no snapshot ID. Consumer identity is:

`(schema_version, compilation_unit, producer, artifactDigest)`

`artifactDigest` is SHA-256 of the exact published artifact bytes (`package:crypto`). It identifies one immutable artifact for cache and idempotency only. It is never displayed, never persisted to disk, and never used to compare topology items. Opaque node and edge IDs compare topology. When a later schema publishes a snapshot ID, identity switches at this single seam.

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

`invalid-snapshot` subcodes: `unsupported-contract`, `missing-field`, `duplicate-id`, `dangling-reference`, `evidence-cycle`, `unsupported-completeness`, plus decoder-closed `unsupported-schema-version` and `missing-capability`.

Scalar-noop completeness `complete/proven-scalar-noop` is a first-class availability state: the snapshot is valid, topology collections are empty, and the canvas is not invented.

---

## 4. Refresh loop

1. Negotiate Styio machine-info and Pafio availability before any process or watcher.
2. On success, watch the workspace recursively. Trigger only on `.styio` files and `pafio.toml`. Ignore `*.observable-static-snapshot.json`.
3. Trailing debounce 500 ms. At most one publication in flight. A newer trigger cancels the in-flight Pafio process.
4. Publication: `pafio --json check --manifest-path <manifest> --styio-bin <styio> --emit-observable-static-snapshot=<n> --observable-capability <name>…` from the workspace root.
5. Parse the Pafio stdout success envelope (`status: succeeded`; `{action, command, intent, message, mode, plan, profile, status, styio, sync, target}`), then read the Styio receipt file `<plan.build_root>/receipt.json` (receipt schema v1) and select the artifact whose name ends `.observable-static-snapshot.json`. The envelope carries no inline receipt; the build root and the receipt-named artifact are read only when both resolve inside the workspace or Pafio output tree.
6. Digest → cache lookup → decode → exact ID-set change against the previously displayed snapshot of the same compilation unit → off-thread layout → state.
7. Decode or publication failure keeps the last valid graph and marks it `stale`. Identical bytes are a cache hit and change no highlights.

---

## 5. Workbench surface

- Bottom tab: `BottomSurfaceTab.observable`
- Title: `Observable`
- Panel id: `bottom.observable`
- Surface id: `observable.graph`
- Capabilities: `observable-topology`, `change-highlight`
- IDE capability id: `service.observable-topology`
- Widget: `products/vityo_app/lib/src/view_render/observable/`
- Keys: `observable-graph-surface`, `observable-banner`, `observable-legend`, `observable-counters`, `observable-detail`, `observable-open-anchor`, `observable-node-<id>`

Selecting a node shows kind, role, relative anchor path, producer facts, and the evidence chain. Open-anchor uses the published package identifier to join a relative path, then the existing workspace file route after a containment check. Absolute paths are never displayed.

When the controller is absent, the tab still exists and renders `unavailable`.

---

## 6. V2 / V3 seams

- `ObservableChangeSource` has one V1 implementation (`IdSetComparisonChangeSource`). V2 adds a producer-delta source without changing the surface.
- Graph projection addresses nodes by `(snapshotIdentity, nodeId)`. V3 runtime overlays attach there and are not modelled in V1.
- Hosted/cloud publication and disk persistence of snapshots are out of scope.

---

## 7. Test map

| Area | Test file |
|---|---|
| Decoder goldens and invalid subcodes | `products/vityo_app/test/observable_snapshot_decoder_test.dart` |
| Negotiation matrix | `products/vityo_app/test/observable_capability_negotiation_test.dart` |
| LRU cache and identical-byte hit | `products/vityo_app/test/observable_snapshot_cache_test.dart` |
| Exact ID-set change | `products/vityo_app/test/observable_change_set_test.dart` |
| Deterministic layout and bound | `products/vityo_app/test/observable_graph_layout_test.dart` |
| Pafio publisher IO / web | `products/vityo_app/test/observable_snapshot_publisher_io_test.dart` |
| Debounce, cancel, stale, scalar-noop | `products/vityo_app/test/observable_graph_controller_test.dart` |
| Banner, legend, counters, detail, anchors | `products/vityo_app/test/observable_graph_surface_test.dart` |
| Tab, panel, capability | `products/vityo_app/test/shell_layout_plan_test.dart`, `products/vityo_app/test/ide_capability_framework_test.dart` |

Consumer fixtures live at `products/vityo_app/test/fixtures/observable_static_snapshot/v1/` with provenance in that directory's README.

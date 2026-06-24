# Vityo IDE Capability Maturity Model

**Purpose:** Define Vityo's own capability maturity levels. Each capability is assessed against Vityo's product trajectory, not against a competitor's feature list. "Like VSCode" or "like JetBrains" is never a maturity level.

**Last updated:** 2026-06-24

**Status:** Active maturity tracking

## 1. Maturity Levels

Vityo capability maturity is measured in six levels. A capability advances by crossing clear verification gates, not by accumulating features.

| Level | Name | Definition | Verification Gate |
|---|---|---|---|
| **L0** | Stub / Decorative | A placeholder exists: enum value, empty class, hardcoded mock, or UI-only surface with no backend model. | Code compiles; no product behavior. |
| **L1** | Local Model | A repo-local model exists with unit tests. May use local heuristics or fixtures. Does not consume upstream machine contracts. | Unit tests pass; model roundtrips through serialization. |
| **L2** | Contract-backed | The capability consumes a Vityo-owned adapter contract. Upstream may be stubbed, but the contract shape is stable. | Adapter contract consumption test passes; capability gap returns structured blocked reason when upstream is absent. |
| **L3** | Product Workflow | The capability is wired into the product shell: UI consumes the model, commands route through the registry, and at least one end-to-end workflow completes. | Widget/integration test for the full workflow; command palette entry functional. |
| **L4** | Cross-platform Reliable | The capability works on all target platforms (Desktop, Android, iOS cloud, Web hosted). Degradation on unsupported platforms is explicit and non-crashing. | Platform matrix test; blocked/unavailable state renders without crash on each platform. |
| **L5** | Styio-native Differentiated | The capability exploits Styio language properties (visual substitution, semantic blocks, minimal compilable unit, runtime graph, Styio project graph) in ways that a generic IDE cannot. | Styio-specific behavior test; capability cannot be replicated by a generic LSP client. |

## 2. Capability Assessment

### 2.1 Editor Input & Document Model

| Aspect | Current Level | Target Level | Evidence | Acceptance Criteria |
|---|---|---|---|---|
| Source Buffer fidelity | L3 | L4 | Document state, selection, undo/redo wired into shell | All platforms preserve Source Buffer through visual substitution toggle |
| Undo/redo | L3 | L4 | Undo/redo model exists; keyboard editing tests pass | Multi-step undo/redo across save boundary |
| Cursor & selection | L3 | L4 | Selection state, mouse drag, keyboard navigation exist | Selection preserved across visual substitution toggle |
| Multi-cursor | L0 | L2 | Not implemented | Multi-cursor edit produces correct undo group |
| Large file degradation | L1 | L3 | No explicit policy | >10K line file opens without blocking UI thread |
| IME composition | L1 | L3 | Basic text input works | CJK composition confirmed on at least one platform |

### 2.2 Visual Substitution

| Aspect | Current Level | Target Level | Evidence | Acceptance Criteria |
|---|---|---|---|---|
| Glyph substitution engine | L3 | L4 | Glyph substitution exists with user toggle | Toggle on/off preserves Source Buffer; copy uses raw text |
| Semantic block surface | L1 | L3 | Block range types exist in language contract | Function body blocks, state blocks render as semantic surfaces |
| Substitution-cursor mapping | L3 | L4 | Cursor mapping exists | Cursor position maps correctly between visual and source positions |
| Diagnostic range alignment | L2 | L3 | Diagnostics project to editor | Diagnostic ranges always map to Source Buffer positions, not visual |

### 2.3 Diagnostics

| Aspect | Current Level | Target Level | Evidence | Acceptance Criteria |
|---|---|---|---|---|
| Diagnostic model | L2 | L3 | Diagnostic type with severity, code, message, range exists | Model roundtrips through serialization |
| Document-bound diagnostics | L2 | L3 | WorkspaceProblemsService binds diagnostics to documents | Diagnostic always references a valid document |
| Revision-bound diagnostics | L1 | L2 | No explicit revision binding | Stale revision diagnostics are rejected |
| Severity normalization | L2 | L3 | Error/warning/hint severity enum exists | All diagnostics carry normalized severity |
| Stale result rejection | L0 | L2 | Not implemented | Diagnostics from old document revision do not display |
| Capability gap rendering | L1 | L2 | Partial implementation | Missing upstream diagnostics show blocked reason, not empty panel |
| Multi-diagnostic sort stability | L2 | L3 | Sort comparator exists | Same input always produces same sort order |
| Inline feedback | L2 | L3 | Inline language feedback exists | Diagnostics appear at correct Source Buffer position inline |

### 2.4 Hover / Completion / Formatting

| Aspect | Current Level | Target Level | Evidence | Acceptance Criteria |
|---|---|---|---|---|
| Hover model | L1 | L2 | HoverPayload type exists | Hover displays markdown at correct range |
| Completion model | L1 | L2 | CompletionItem type exists | Completion inserts text without breaking document model |
| Formatting model | L1 | L2 | FormattingEdit type exists | Formatting returns TextEdit; preview does not modify document |
| Formatting apply | L1 | L3 | Not wired | Formatting apply goes through workspace edit transaction |
| Upstream capability gap | L1 | L2 | Not explicitly modeled | Missing hover/completion/formatting shows blocked reason |

### 2.5 Rename / References

| Aspect | Current Level | Target Level | Evidence | Acceptance Criteria |
|---|---|---|---|---|
| Reference model | L2 | L3 | ReferenceSpan type exists; workspace reference search works | References classified as declaration vs usage |
| Rename model | L1 | L2 | RenamePlan type exists | Rename plan includes all affected ranges |
| Rename preview | L2 | L3 | Workspace rename dialog exists | Preview shows all changes without applying |
| Rename apply | L1 | L3 | Not wired through workspace edit transaction | Rename apply uses workspace edit, not string replace |
| Upstream blocked handling | L1 | L2 | Not explicitly modeled | Missing upstream rename/references shows blocked reason |

### 2.6 Project Graph

| Aspect | Current Level | Target Level | Evidence | Acceptance Criteria |
|---|---|---|---|---|
| Project graph model | L2 | L3 | ProjectGraphSnapshot with members, packages, dependencies, targets | Model roundtrips through serialization |
| Canonical file inference | L2 | L3 | Canonical file-based inference exists | Inferred state marked as partial; machine payload marked as authoritative |
| Hosted payload consumption | L2 | L3 | Hosted workspace record exists | Hosted payload and canonical files distinguished |
| Source marking | L1 | L2 | Not explicitly marked | Every project graph field has source: canonical-file, machine-payload, inferred, or capability-gap |
| Blocked/partial status | L1 | L2 | Not standardized | Missing data shows structured blocked reason |
| Agent-context serialization | L0 | L2 | Not implemented | Project graph summary serializable for Agent context |

### 2.7 Execution Route

| Aspect | Current Level | Target Level | Evidence | Acceptance Criteria |
|---|---|---|---|---|
| Run command | L3 | L4 | Run command exists with keyboard shortcut | Run command wired through command registry |
| Target selector | L2 | L3 | Minimal compilable unit concept exists | Ambiguous/missing target returns structured blocked reason |
| Workflow lanes | L3 | L4 | Run/fetch/vendor/environment/deploy lanes exist | Each lane has independent blocked/success/failed state |
| Capability gap blocking | L1 | L2 | Not explicitly modeled | Missing execution capability returns structured blocked reason |
| Route trace | L2 | L3 | Execution route summary exists | Route shows which adapter path was used |

### 2.8 Runtime Events

| Aspect | Current Level | Target Level | Evidence | Acceptance Criteria |
|---|---|---|---|---|
| Event envelope | L3 | L4 | RuntimeEventEnvelope with schema version, session, sequence, timestamp | All events carry stable envelope |
| Event replay | L3 | L4 | Replay summary exists | All published families replayable |
| Family-based lane summary | L3 | L4 | Lane summary by family exists | Unknown family degrades gracefully |
| Graph summary | L3 | L4 | Execution graph, node detail, edge timeline exist | Graph summary consumed by runtime surface and debug console |
| Agent-context serialization | L0 | L2 | Not implemented | Runtime summary serializable for Agent context |
| Live streaming | L1 | L3 | Currently compile-plan artifact replay | Live event streaming when upstream supports it |

### 2.9 Workspace Persistence

| Aspect | Current Level | Target Level | Evidence | Acceptance Criteria |
|---|---|---|---|---|
| Document store | L3 | L4 | FileSystemWorkspaceDocumentStore with save/load/watch | Works across local, remote, browser, virtual providers |
| Editor session persistence | L2 | L3 | EditorSessionDataStore exists | Tabs, active document, cursor restored across restart |
| Cross-session restore | L2 | L3 | Manual save/restore exists | Automatic policy defined |
| Hosted workspace lifecycle | L2 | L3 | Hosted workspace record exists | Close/export/retention/delete UX validated |

### 2.10 Command Palette

| Aspect | Current Level | Target Level | Evidence | Acceptance Criteria |
|---|---|---|---|---|
| Command registry | L3 | L4 | IdeCommandRegistry with 37 commands, categories, permissions | All commands have stable IDs, categories, descriptions |
| Fuzzy matching | L3 | L4 | CommandPaletteService with scoring | Pattern matching returns relevant results |
| Enablement | L2 | L3 | Permission requirements exist | Capability-gap commands show blocked reason |
| Keyboard navigation | L1 | L3 | Keyboard shortcuts exist | Palette fully navigable by keyboard |
| Agent-visible filtering | L0 | L2 | Not implemented | Dangerous/unavailable commands excluded from agent list |

### 2.11 Settings / Profile

| Aspect | Current Level | Target Level | Evidence | Acceptance Criteria |
|---|---|---|---|---|
| Settings schema | L1 | L2 | Configuration store exists | Schema-owned settings with migration |
| Settings roundtrip | L1 | L2 | Not explicitly tested | Settings serialize and deserialize without loss |
| Profile snapshot | L1 | L2 | AgentPromptProfile exists | Profile local-first, sync-optional |
| Visual substitution toggle | L2 | L3 | Toggle exists | Setting persists across sessions |
| Secret redaction | L1 | L2 | API key referenced by env var name | Display projection redacts secrets |
| Agent-context consumption | L0 | L2 | Not implemented | Settings/profile snapshot safe for Agent context |

### 2.12 Module Lifecycle

| Aspect | Current Level | Target Level | Evidence | Acceptance Criteria |
|---|---|---|---|---|
| Module manifest | L2 | L3 | Module manifest with kind, version, capabilities | Manifest roundtrips through serialization |
| Capability matrix | L2 | L3 | Platform capability matrix exists | Unsupported platform hides module entry |
| Staged update | L1 | L2 | Staged update flag exists | Real package download/staging/activation |
| Install/uninstall | L2 | L3 | Lifecycle states defined | Uninstall follows platform reclaim policy |

### 2.13 Agent Context

| Aspect | Current Level | Target Level | Evidence | Acceptance Criteria |
|---|---|---|---|---|
| Context channels | L1 | L2 | Context channel list in AgentPromptProfile | Each channel has defined scope and content |
| Context snapshot | L0 | L1 | Not implemented | Snapshot serializable; includes workspace/document/selection/diagnostics/project/runtime |
| Scope model | L0 | L1 | Not implemented | Scope controls which channels are included |
| Redaction policy | L0 | L1 | Not implemented | Secrets, tokens, personal paths redacted |
| Capability gap context | L0 | L1 | Not implemented | Agent receives structured capability gap summary |

### 2.14 Agent Action Permissions

| Aspect | Current Level | Target Level | Evidence | Acceptance Criteria |
|---|---|---|---|---|
| Permission levels | L2 | L3 | PermissionRequestScope, PermissionDecision exist | Each action category has minimum permission level |
| Permission audit | L2 | L3 | AgentAuditEvent exists | All permission decisions recorded |
| Dangerous action gating | L1 | L2 | Not explicitly modeled | Dangerous actions require higher permission |
| Agent command routing | L0 | L2 | Not implemented | Agent actions go through command registry |

### 2.15 Patch / Preview / Apply / Undo

| Aspect | Current Level | Target Level | Evidence | Acceptance Criteria |
|---|---|---|---|---|
| Patch preview | L2 | L3 | FileChangePreview, PatchApplyPlan exist | Preview does not modify documents |
| Patch apply | L1 | L2 | Not wired through workspace edit | Apply uses workspace edit transaction |
| Rollback | L0 | L1 | Not implemented | Last agent-applied edit can be rolled back |
| Document model bypass prevention | L1 | L2 | Architecture rule exists | Agent cannot write files directly |

### 2.16 Hosted Workspace Lifecycle

| Aspect | Current Level | Target Level | Evidence | Acceptance Criteria |
|---|---|---|---|---|
| Workspace record | L2 | L3 | HostedWorkspaceRecordSnapshot exists | All lifecycle fields populated |
| Retention window | L1 | L2 | retentionDays field exists | Close prompt shows retention deadline |
| Export | L1 | L2 | Export fields exist | Core file export functional |
| Platform matrix | L1 | L3 | Desktop local + hosted routes tested | All four platform routes verified |

## 3. Maturity Summary

| Domain | Current Floor | Current Ceiling | Target Floor | Key Blockers |
|---|---|---|---|---|
| Editor Input & Document | L1 | L3 | L3 | Multi-cursor (L0); large-file policy (L1) |
| Visual Substitution | L1 | L3 | L4 | Semantic block surface upstream dependency |
| Diagnostics | L0 | L2 | L3 | Stale revision rejection; capability gap rendering |
| Hover/Completion/Formatting | L1 | L2 | L3 | Upstream StyioService providers |
| Rename/References | L1 | L3 | L3 | Upstream rename safety; workspace edit wiring |
| Project Graph | L0 | L2 | L3 | Source marking; Agent serialization |
| Execution Route | L1 | L3 | L4 | Structured blocked reasons; route trace |
| Runtime Events | L1 | L3 | L4 | Live streaming (upstream); Agent serialization |
| Workspace Persistence | L2 | L3 | L4 | Cross-provider validation |
| Command Palette | L0 | L3 | L4 | Agent filtering; keyboard navigation |
| Settings/Profile | L0 | L2 | L3 | Schema migration; secret redaction |
| Module Lifecycle | L1 | L3 | L3 | Real staging path |
| Agent Context | L0 | L2 | L2 | Context snapshot; scope; redaction |
| Agent Permissions | L1 | L3 | L3 | Dangerous action gating; command routing |
| Patch Workflow | L0 | L2 | L3 | Workspace edit application; rollback |
| Hosted Workspace | L1 | L2 | L3 | Retention/export UX; platform matrix |

## 4. How to Advance a Capability

1. Identify the current maturity level from this document.
2. Pick the next level's verification gate.
3. Implement the minimum change that satisfies the gate.
4. Add a test that proves the gate is met.
5. Update this document with the new level and evidence.

Never claim a level without the corresponding verification evidence.

## 5. References

- [Vityo-IDE-Benchmark-Matrix.md](./Vityo-IDE-Benchmark-Matrix.md) — IDE benchmark mapping
- [Vityo-Product-Spec.md](./Vityo-Product-Spec.md) — Product SSOT
- [Vityo-Implementation-Gaps.md](./Vityo-Implementation-Gaps.md) — Active gap register

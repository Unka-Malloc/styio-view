# User Facing Workflows Contract

**Purpose:** Define the product workflow contract for first launch, workspace lifecycle, editing, command routing, run/debug, diagnostics, agent review, settings, modules, hosted export, and recovery UX.

**Owner:** `frontend/vityo_app/lib/src/` (app bootstrap, shell/runtime, workspace, editor, commands, runtime, agent, diagnostics, settings, module host, hosted lifecycle)
**Last updated:** 2026-06-29
**Checkpoint node:** `6e4b2a17-d0f1-4f3b-98e7-b1c54d3f8a02` (User Facing Workflows contract, `docs/plan/better-plan/user-facing-workflows/Checkpoints.json`)

---

## 1. Owned Artifacts

### 1.1 First Launch

| Artifact | File | Role |
|----------|------|------|
| `AppBootstrap` bootstrap flow | `frontend/vityo_app/lib/src/app/app_bootstrap.dart` | Orchestrates first-launch service wiring: seeds catalogs, language service. |
### 1.2 Workspace Lifecycle

| Artifact | File | Role |
|----------|------|------|
| `WorkspaceController` | `frontend/vityo_app/lib/src/view_ide/workspace/workspace_controller.dart` | `ChangeNotifier` managing active project snapshot, open files list, active file path. |
| `WorkspaceDocumentStore` | `frontend/vityo_app/lib/src/view_ide/workspace/workspace_document_store.dart` | Abstract document store interface. |
| `FileSystemWorkspaceDocumentStore` | `frontend/vityo_app/lib/src/view_ide/workspace/workspace_document_store_io.dart` | IO implementation: local filesystem read/write with metadata sidecars. |
| `HostedWorkspaceDocumentStore` | `frontend/vityo_app/lib/src/view_ide/workspace/hosted_workspace_document_store.dart` | Hosted backend document store. |
| `HostedWorkspaceLifecycle` | `frontend/vityo_app/lib/src/view_ide/workspace/hosted_workspace_lifecycle.dart` | Close-plan, pending-deletion, connector-parity. |
| `WorkspaceFileOperationService` | `frontend/vityo_app/lib/src/view_ide/workspace/workspace_file_operations.dart` | File CRUD operations with path validation. |
| `WorkspaceFileCommandRouter` | `frontend/vityo_app/lib/src/view_ide/workspace/workspace_file_command_router.dart` | Routes file commands. |
| `WorkspaceFileExplorerController` | `frontend/vityo_app/lib/src/view_ide/workspace/workspace_file_explorer_controller.dart` | File tree state: expanded nodes, selection, filtering. |
| `VFS` | `frontend/vityo_app/lib/src/view_ide/workspace/vfs.dart` | Virtual filesystem abstraction for path resolution. |

### 1.4 Command Palette

| Artifact | File | Role |
|----------|------|------|
| `AppCommandId` enum | `frontend/vityo_app/lib/src/view_ide/commands/app_commands.dart` | 80+ canonical command IDs. |
| `StyioCommandRegistry` | `frontend/vityo_app/lib/src/view_ide/commands/app_commands.dart` | Canonical command catalog. |
| `CommandPaletteService` | `frontend/vityo_app/lib/src/view_ide/commands/command_palette.dart` | Pure-Dart scoring, matching, filtering. |
| `CommandPaletteModel` | `frontend/vityo_app/lib/src/view_ide/commands/command_palette_model.dart` | Overlay state machine. |
| `CommandPaletteSurface` | `frontend/vityo_app/lib/src/view_render/commands/command_palette_surface.dart` | Flutter widget. |
| `CommandKeybindingProfile` | `frontend/vityo_app/lib/src/view_ide/commands/command_keybinding_profile.dart` | Keybinding profile, conflict detection. |
| `ExtensionCommandContributionCatalog` | `frontend/vityo_app/lib/src/view_ide/commands/extension_command_contributions.dart` | Dynamic command contributions. |

### 1.5 Run / Debug

| Artifact | File | Role |
|----------|------|------|
| `ExecutionAdapter` | `frontend/vityo_app/lib/src/view_ide/backend_toolchain/execution_adapter.dart` | Abstract compile/run adapter. |
| `ExecutionAdapterIO` | `frontend/vityo_app/lib/src/view_ide/backend_toolchain/execution_adapter_io.dart` | IO implementation via local CLI. |
| `HostedControlPlaneClient` | `frontend/vityo_app/lib/src/view_ide/backend_toolchain/hosted_control_plane.dart` | Cloud execution client. |
| `HostedExecutionCodec` | `frontend/vityo_app/lib/src/view_ide/backend_toolchain/hosted_execution_codec.dart` | Decodes backend responses into `ExecutionSession` + runtime events. |
| `RuntimeTaskDefinition` | `frontend/vityo_app/lib/src/view_ide/runtime/runtime_task_lifecycle.dart` | Canonical task definition with kind (`shell`, `run`, `build`, `test`, `debug`, `agent`, `toolchain`). |
| `RuntimeTaskLifecycleEvent` | `frontend/vityo_app/lib/src/view_ide/runtime/runtime_task_lifecycle.dart` | Unified lifecycle event: status transitions. |
| `RuntimeExecutionPlanner` | `frontend/vityo_app/lib/src/view_ide/runtime/runtime_execution_plan.dart` | Execution planning: plan, handoff, binding. |
| `RuntimeSurface` | `frontend/vityo_app/lib/src/view_render/runtime/runtime_surface.dart` | Runtime surface widget. |
| `RuntimeOutputChannelBuffer` | `frontend/vityo_app/lib/src/view_ide/runtime/runtime_output_channels.dart` | Output channel model: 7 channel kinds. |

### 1.6 Diagnostics

| Artifact | File | Role |
|----------|------|------|
| `Diagnostic` (core model) | `frontend/vityo_app/lib/src/view_ide/language/contract/language_contract.dart` | Severity + code + message + `SourceRange`. |
| `RevisionBoundDiagnostic` | `frontend/vityo_app/lib/src/view_ide/language/diagnostics/diagnostic_revision_gate.dart` | Diagnostic bound to a document revision; stale if mismatches. |
| `DiagnosticSource` / `DiagnosticConfidence` | `frontend/vityo_app/lib/src/view_ide/language/diagnostics/diagnostic_revision_gate.dart` | Source: `compiler`, `languageService`, `extension`. Confidence: `authoritative`, `heuristic`, `speculative`. |
| `WorkspaceDiagnosticsProducerExecutionPlan` | `frontend/vityo_app/lib/src/view_ide/workspace/workspace_diagnostics.dart` | Execution plan for a diagnostics producer. |
| `WorkspaceDiagnosticsSnapshot` | `frontend/vityo_app/lib/src/view_ide/workspace/workspace_diagnostics.dart` | Immutable snapshot of all workspace diagnostics. |
| `WorkspaceDiagnosticsController` | `frontend/vityo_app/lib/src/view_ide/workspace/workspace_diagnostics_controller.dart` | Orchestrates diagnostics producers and dispatches snapshots. |
| `ProblemsSurface` | `frontend/vityo_app/lib/src/view_render/problems/problems_surface.dart` | Renders per-document and workspace-wide diagnostics. |
| `StyioWorkspaceDiagnosticsProvider` | `frontend/vityo_app/lib/src/view_ide/language/service/styio_workspace_diagnostics_provider.dart` | Language-service-backed provider. |

### 1.7 Agent Review

| Artifact | File | Role |
|----------|------|------|
| `AgentSurface` | `frontend/vityo_app/lib/src/view_render/agent/agent_surface.dart` | Agent surface widget: provider profile, runtime status, pending patch. |
| `AgentCodingSessionController` | `frontend/vityo_app/lib/src/view_ide/agent/agent_coding_session_controller.dart` | Coding session lifecycle: dispatch, recovery, patch queue. |
| `AgentCodePatchApplier` | `frontend/vityo_app/lib/src/view_ide/agent/agent_code_patch_applier.dart` | Patch application: `WorkspaceEditPlan` from patch text. |
| `AgentWorkspaceSnapshot` | `frontend/vityo_app/lib/src/view_ide/agent/agent_workspace_snapshot.dart` | Workspace snapshot for agent context. |
| `AgentToolCallDispatcher` | `frontend/vityo_app/lib/src/view_ide/agent/agent_tool_call_dispatcher.dart` | Tool call dispatch with permission check. |
| `AgentToolPermissionPolicyStore` | `frontend/vityo_app/lib/src/view_ide/agent/agent_tool_permission_policy_store.dart` | Per-tool permission policies (allow/deny/confirm). |

### 1.8 Settings

| Artifact | File | Role |
|----------|------|------|
| `SettingsSurface` | `frontend/vityo_app/lib/src/view_render/settings/settings_surface.dart` | Settings widget: toolchain, prefs, theme, capabilities. |
| `ToolchainSettingsSurface` | `frontend/vityo_app/lib/src/view_ide/interaction/toolchain_status_surface.dart` | Toolchain status and install plan. |
| `VityoThemeOverride` / `ThemeOverrideStore` | `frontend/vityo_app/lib/src/view_ide/environment/configuration/` | Theme configuration. |
| `ShellConfigurationStore` | `frontend/vityo_app/lib/src/view_ide/environment/configuration/shell_configuration_store.dart` | Shell configuration persistence. |

### 1.9 Modules

| Artifact | File | Role |
|----------|------|------|
| `ModuleManifest` | `frontend/vityo_app/lib/src/view_ide/module_host/module_manifest.dart` | Module manifest: moduleId, kind, slot. |
| `ModuleLifecyclePlan` / `ModuleLifecycleState` | `frontend/vityo_app/lib/src/view_ide/module_host/module_lifecycle.dart` | Lifecycle action and state. |
| `ModuleDefinition` | `frontend/vityo_app/lib/src/view_ide/module_host/module_definition.dart` | Manifest + capability matrix. |
| `ExtensionLifecycleRecord` | `frontend/vityo_app/lib/src/view_ide/module_host/extension_lifecycle.dart` | Extension lifecycle status. |
| `ExtensionContributionRouter` | `frontend/vityo_app/lib/src/view_ide/module_host/extension_contribution_router.dart` | Routes contributions to surfaces. |

### 1.10 Hosted Export

| Artifact | File | Role |
|----------|------|------|
| `HostedWorkspaceLifecycle` | `frontend/vityo_app/lib/src/view_ide/workspace/hosted_workspace_lifecycle.dart` | Close-plan, pending-deletion, connector-parity. |
| `HostedWorkspaceClosePlan` | `frontend/vityo_app/lib/src/view_ide/workspace/hosted_workspace_lifecycle.dart` | Export state, URL, expiration. |
| `HostedWorkspacePendingDeletionPlan` | `frontend/vityo_app/lib/src/view_ide/workspace/hosted_workspace_lifecycle.dart` | Deletion plan: retention, deadline, remaining. |
| `HostedWorkspaceLifecycleBanner` | `frontend/vityo_app/lib/src/view_render/shell/hosted_workspace_lifecycle_banner.dart` | UI banner: close guard, export link. |
| `HostedBackendRetryExecutor` | `frontend/vityo_app/lib/src/view_ide/workspace/hosted_backend_retry_executor.dart` | Retry action execution. |

### 1.11 Recovery UX

| Artifact | File | Role |
|----------|------|------|
| `ToolchainRecoveryAction` / handler | `frontend/vityo_app/lib/src/view_render/runtime/runtime_surface.dart` | Recovery action for toolchain failures. |
| `ToolchainStatusSurface` | `frontend/vityo_app/lib/src/view_ide/interaction/toolchain_status_surface.dart` | Toolchain status with recovery actions. |
| `StyioServiceRuntimeSessionEvent` | `frontend/vityo_app/lib/src/view_ide/language/service/styio_service_runtime.dart` | Language service runtime state: `active`, `refreshing`, `failed`, `disposed`. |
| `LanguageServiceStatusSurface` | `frontend/vityo_app/lib/src/view_ide/interaction/language_service_status_surface.dart` | Language service status indicator. |

### 1.12 Cross-Surface State Projection

| Artifact | File | Role |
|----------|------|------|
| `ShellModel` | `frontend/vityo_app/lib/src/view_render/shell/shell_model.dart` | Central state model: layout, tab routing, command dispatch. |
| `ShellScope` | `frontend/vityo_app/lib/src/view_render/shell/shell_scope.dart` | `InheritedNotifier<ShellModel>` for shell-wide access. |
| `FoundationLifecycleCoordinator` | `frontend/vityo_app/lib/src/view_ide/foundation/lifecycle_coordinator/` | 6-state lifecycle coordination. |
| `IdeCapabilityFramework` | `frontend/vityo_app/lib/src/view_ide/foundation/ide_capability_framework.dart` | 12 layers, 32 required capabilities. |
| `IdeCapabilityRegistry` | `frontend/vityo_app/lib/src/view_ide/workbench/ide_capability_registry.dart` | Single truth for capability metadata. |
| `SurfaceRegistry` | `frontend/vityo_app/lib/src/view_ide/workbench/surface_registry.dart` | Surface registry with placement types. |
| `BottomSurfaceTab` enum | `frontend/vityo_app/lib/src/view_render/shell/shell_model.dart` | 27 bottom-surface tabs. |

---

## 2. Product Boundaries

| Boundary | Description | Crossing Mechanism |
|----------|-------------|-------------------|
| Bootstrap -> Shell | First-launch wiring seeds editor, toolchain, language service. | `AppBootstrap` -> `ShellRuntimeModel` adapters |
| Shell -> Editor | File-open/close routes to editor facade. | `ShellModel.executeCommand()` -> `openFile`/`closeFile` |
| Editor -> Diagnostics | Edits trigger diagnostics refresh. | `EditorSessionFacade` -> `WorkspaceDiagnosticsController` |
| Diagnostics -> Agent | Agent session consumes diagnostics. | `AgentWorkspaceSnapshot` includes diagnostics |
| Run/Debug -> Output | Execution streams to runtime/debug surfaces. | `RuntimeOutputChannelBuffer` -> surfaces |
| Agent -> Edit | Agent patches routed to edit plan. | `AgentCodePatchApplier` -> `WorkspaceEditPlan` |
| Modules -> All | Module changes update visibility, commands, capabilities. | `ModuleRegistry` -> registries |
| Hosted Export -> Shell | Export generation closes lifecycle. | `HostedWorkspaceLifecycle.closePlanFor` -> banner |
| Recovery -> All | Recovery actions dispatch across affected surfaces. | Toolchain/language service -> surfaces |
| Settings -> All | Config changes propagate through stores and event bus. | Stores -> model, theme, language service |

---

## 3. Workflow Invariants

### Bootstrap
1. `AppBootstrapServiceWiringSnapshot` has one entry per service with state `injected` or `absent`.
2. First-launch catalogs merge defaults without overwriting selections.
3. Language service transitions `refreshing` -> `active`/`failed` before editor usable.

### Workspace Lifecycle
4. `WorkspaceController.openFile` adds path to `_openFilePaths` and updates `_activeFilePath`.
5. `WorkspaceController.closeFile` removes path and selects previous; no-op for non-open.
6. `restoreOpenFiles` filters and deduplicates.
7. `createFile` validates paths and checks existence.
8. File operation results carry `applied`, `path`, `message`.

### Edit / Save / Reload / Conflict
9. `DocumentState` immutable; `replaceRange` returns new instance.
10. `WorkspaceEditPrecondition` validates revision and/or content hash before applying.
11. Mismatch returns `staleRevision` or `staleContentHash`.
12. `WorkspaceEditSource` tracked on every edit plan.
13. `blockedUnsavedChanges` provides `canSave`/`canDiscard`/`canSwitchToFile`.

### Command Palette
14. Search includes all commands when `includeBlocked=true`.
15. Blocked commands get 250-point penalty and `enabled=false`.
16. Recent commands boosted; `recentRank` populated.
17. `CommandShortcutCapturePolicy` respects `platformTarget`.
18. Keybinding conflict review detects overlapping shortcuts.

### Run / Debug
19. `RuntimeTaskKind` exhaustive: `shell`, `run`, `build`, `test`, `debug`, `agent`, `toolchain`.
20. Status order: `queued` -> `starting` -> `running` -> terminal.
21. `RuntimeExecutionHandoffTarget`: one of 4 targets.
22. Route selection surfaces adapter kind + capability level.

### Diagnostics
23. `DiagnosticConfidence` maps to distinct styling; `speculative` never blocks operations.
24. `RevisionBoundDiagnostic` carries revision; stale discarded.
25. Producer plan carries handoff + binding.

### Agent Review
26. Recovery dispatch status: `blocked`, `dispatched`, `failed`.
27. Patches produce `WorkspaceEditPlan` with `WorkspaceEditSource.agent`.
28. Tool calls check permission before dispatch.

### Settings
29. `SettingsSurface` renders toolchain, prefs, theme, capabilities.
30. Theme changes persisted and reflected immediately.

### Modules
31. `canMount` requires `installed && enabled && trusted`.
32. Extension lifecycle: `registered` -> `activated` (or `blocked`/`failed`).
33. Module visibility resolved per `PlatformTarget`.

### Hosted Export
34. Close plan includes `requiresClearConfirmation` when not deleted.
35. Export URL and expiration in banner when `exportReady`.
36. Pending deletion computes retention/deadline/remaining/expired.

### Recovery UX
37. Toolchain recovery dispatched via `onToolchainRecoveryAction`.
38. Language service recovery transitions through session event states.
39. Retry action result reports `completed`/`blocked`/`unsupported`/`failed`.

### Cross-Surface State Projection
40. `ShellModel` is single entry point via `ShellScope.of(context)`.
41. `IdeCapabilityRegistry` is single truth; no widget-tree inference.
42. `FoundationLifecycleCoordinator` registers all before `initializeAll`.
43. `BottomSurfaceTab` has exactly one mapping to `ShellPanelDescriptor`.

---

## 4. Success / Blocked / Recovery Paths

### 4.1 First Launch
- **Success:** All required services wired, catalogs seeded, language active.
- **Blocked service wiring:** Critical service absent; reduced capability.
- **Blocked toolchain discovery:** No compiler; settings shows install prompt.
- **Recovery:** User installs toolchain; catalogs merge.

### 4.2 Workspace Lifecycle
- **Success:** Project graph loaded, open files restored.
- **Blocked missing project:** No editor files; explorer shows root only.
- **Blocked file not found:** Seed content; no error.
- **Blocked hosted offline:** Banner shows retry actions.

### 4.3 Edit / Save / Reload / Conflict
- **Success:** Edit applied, revision incremented, undo updated.
- **Blocked stale revision:** User prompted to reload.
- **Blocked stale content hash:** User accepts or overwrites.
- **Blocked unsaved changes:** Save/discard/cancel dialog.
- **Recovery:** `acceptExternalChange` command.

### 4.4 Run / Debug
- **Success:** CompileAndRun succeeds; output to runtime surface.
- **Blocked compiler not installed:** Install prompt.
- **Blocked unrunnable:** `RuntimeExecutionPlanStatus.blockedUnrunnable`.
- **Blocked hosted:** Retry actions.
- **Recovery:** Install toolchain or retry.

### 4.5 Diagnostics
- **Success:** Snapshot dispatched; problems surface updated.
- **Blocked producer failure:** Terminal `failed`; retry.
- **Recovery:** `refreshWorkspaceDiagnostics`.

### 4.6 Agent Review
- **Success:** Patch preview; user applies or cancels.
- **Blocked provider unavailable:** Recovery draft.
- **Blocked patch conflict:** Conflict reported; user reverts.
- **Recovery:** Adjust provider or retry.

### 4.7 Settings / Toolchain
- **Success:** Selection or install completes.
- **Blocked download failure:** Retry.
- **Blocked provenance:** Security warning.
- **Recovery:** Switch toolchain or retry.

### 4.8 Hosted Export
- **Success:** Core file export generated; download URL.
- **Blocked no workspace:** Banner not shown.
- **Recovery:** Retry export generation.

---

## 5. Keyboard / No-Overflow Expectations

### Keyboard Expectations

| Surface | Expected Behavior |
|---------|------------------|
| Editor | Arrow keys, Ctrl+S save, Ctrl+Z/Ctrl+Shift+Z undo/redo, Ctrl+F find, Ctrl+P command palette, F5 debug |
| Command Palette | Up/Down navigate, Enter execute, Ctrl+Shift+P open, Escape close |
| Problems | Ctrl+Shift+M open, Up/Down navigate, Enter jump to source |
| Runtime | Ctrl+` toggle |
| Agent | Ctrl+Shift+I open, Ctrl+Enter apply patch |
| Source Control | Ctrl+Shift+G open |
| Settings | Ctrl+, open |

### No-Overflow Expectations
1. Command palette results: `maxResults` default 50.
2. Problems panel: scrollable list; no row limit.
3. File explorer: no depth limit.
4. Runtime output channels: capped per channel; oldest evicted.
5. Agent contexts: 6 caps in `AgentCodingSessionController` (12/6/20/12/10/12).
6. Editor undo: `HistoryController.maxEntries` configurable.
7. Search results: `maxResults` per query.

---

## 6. Downstream Consumers

| Consumer | Consumed Artifacts |
|----------|-------------------|
| `RuntimeEventAdapter` contract | `ExecutionAdapter`, `HostedExecutionCodec`, `RuntimeEventEnvelope` |
| `WorkbenchShellSurfaces` contract | `ShellModel`, `ShellScope`, `BottomSurfaceTab`, `AppCommandId` |
| `ProblemsTestingSourceControlSurfaces` contract | `WorkspaceDiagnosticsSnapshot`, `Diagnostic`, `WorkspaceEditPlan` |
| `ExecutionAdapter` contract | `ExecutionAdapter`, `ExecutionSession`, `RuntimeTaskDefinition` |
| `ToolchainManagementAdapter` contract | `ToolchainStatusSurface`, `ToolchainRecoveryAction` |
| `LanguageServiceAdapter` contract | `StyioLanguageService`, `Diagnostic`, `StyioServiceRuntimeSessionEvent` |

---

## 7. Single Implementation Path

- **No duplicate document stores:** `WorkspaceDocumentStore` is single interface; 3 implementations.
- **No parallel command registries:** `StyioCommandRegistry` is single catalog.
- **No duplicate workspace controllers:** `WorkspaceController` is single entry point.
- **No legacy edit paths:** All edits through `EditorTransactionService`.
- **No alternative agent patch paths:** All patches through `AgentCodePatchApplier`.
- **No versioned hosts:** Single `HostedWorkspaceLifecycle` path.
- **No duplicate capability frameworks:** `IdeCapabilityRegistry` is single truth.
- **No parallel shell models:** `ShellModel` is single state holder.
- **No platform-specific diagnostic paths:** `WorkspaceDiagnosticsController` is single orchestrator.

---

## 8. Verification Evidence

### Static Structure Evidence
- Barrel files: `workspace.dart`, `runtime.dart`, `commands.dart`, `module_host.dart`, `app_bootstrap.dart`
- `AppCommandId` enum: 80+ unique command IDs.
- `requiredVityoIdeCapabilityIds`: 32 capabilities, 12 layers.
- `BottomSurfaceTab`: 27 unique tabs.
- `RuntimeOutputChannelKind`: 7 channel kinds.
- `IdeCapabilityLayer`: 12 layers.

### Test Evidence (27+ test files)
| Test | Key Assertions |
|------|----------------|
| `workspace_controller_test.dart` | File open/close/restore, project replacement |
| `workspace_document_store_io_test.dart` | Load/save/delete, metadata, absolute path support |
| `workspace_edit_applier_test.dart` | Precondition validation, revision gate, content hash |
| `workspace_file_operations_test.dart` | Create/rename/delete/reveal, path validation |
| `command_palette_test.dart` | Scoring, recent-rank boosting, blocked filtering |
| `command_palette_surface_test.dart` | Widget rendering, keyboard nav, keybinding editor |
| `runtime_task_lifecycle_test.dart` | Status transitions, serialization |
| `runtime_execution_plan_test.dart` | Planning, handoff, binding, dispatch |
| `runtime_output_channel_test.dart` | Event production, subscription, channel summary |
| `debug_console_surface_test.dart` | Replay, graph digest, debug lanes |
| `workspace_diagnostics_controller_test.dart` | Producer lifecycle, snapshot dispatch, retry |
| `diagnostic_revision_gate_test.dart` | Revision matching, stale detection |
| `agent_coding_session_controller_test.dart` | Dispatch, recovery, patch queue |
| `agent_code_patch_applier_test.dart` | Patch application, conflict detection |
| `agent_tool_call_dispatcher_test.dart` | Permission checks, dispatch lifecycle |
| `settings_surface_test.dart` | Toolchain management, preferences, theme |
| `module_lifecycle_test.dart` | State transitions, trust, mount eligibility |
| `extension_lifecycle_test.dart` | Registration, activation, blocking |
| `hosted_workspace_lifecycle_test.dart` | Close plan, export, deletion plan |
| `hosted_backend_retry_executor_test.dart` | Retry action execution |
| `shell_no_overflow_test.dart` | Desktop/compact layout, finite caps |
| `shell_model_test.dart` | Toolchain recovery routing, command-to-tab |
| `workbench_registry_test.dart` | Context key evaluation, surface registration |
| `foundation_lifecycle_coordinator_test.dart` | Component registration, state transitions |
| `editor_session_facade_test.dart` | Edits, selection, undo/redo |
| `editor_transaction_test.dart` | Precondition validation, content hash |
| `hosted_execution_codec_test.dart` | Response decoding, session construction |

### Invariant Coverage
- [x] All 43 invariants in Section 3 backed by test assertions.
- [x] All `AppCommandId` values (80+) unique.
- [x] All 27 `BottomSurfaceTab` values map to `ShellPanelDescriptor`.
- [x] Single implementation path enforced by barrel exports and no duplicates.
- [x] All 7 `RuntimeOutputChannelKind` values consumed by runtime/debug surfaces.
- [x] All 32 required capabilities documented.
- [x] No-Overflow caps enforced in constants, limits, and max results.

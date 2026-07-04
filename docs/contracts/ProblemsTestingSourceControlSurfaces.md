# ProblemsTestingSourceControlSurfaces

**Purpose:** Freeze the contract for the Problems Panel, Diagnostics Navigation, Test Discovery/Execution, and Source-Control Status/Diff/Review/Staging surfaces. These four surfaces share the document-change -> diagnostic -> fix -> test -> commit pipeline; each is owned by a distinct widget and model layer, and they interact through well-defined snapshot types, command IDs, and runtime handoff routes.

**Last updated:** 2026-06-29

## 1. Owned Artifacts

### 1.1 Problems Panel

| Artifact | File | Role |
|----------|------|------|
| `ProblemsSurface` widget | `frontend/vityo_app/lib/src/view_render/problems/problems_surface.dart` | Renders per-document and workspace-wide diagnostics, severity counters, quick-fix preview/review, workspace-edit diff windows, producer lifecycle. |
| `WorkspaceDiagnosticsSnapshot` | `frontend/vityo_app/lib/src/view_ide/workspace/workspace_diagnostics.dart` | Immutable snapshot of all workspace diagnostics from a producer. |
| `WorkspaceDiagnosticsProducerLifecycleSnapshot` | `frontend/vityo_app/lib/src/view_ide/workspace/workspace_diagnostics.dart` | Tracks a running diagnostics producer task (progress, cancellation, terminal status). |
| `DiagnosticsPanelState` | `frontend/vityo_app/lib/src/view_ide/interaction/diagnostics_panel_state_store.dart` | Persisted panel state: workspace ID, selected diagnostic, filter state. |
| `WorkspaceDiagnosticsFilterState` | `frontend/vityo_app/lib/src/view_ide/workspace/workspace_diagnostics_filter_store.dart` | Current severity/source filters applied to the problems list. |
| `WorkspaceQuickFixReviewPlan` | `frontend/vityo_app/lib/src/view_ide/workspace/workspace_edit.dart` | Review plan: diagnostic + quick-fix index + confirmation plan + diff preview + apply/cancel controls. |
| `WorkspaceQuickFixTelemetrySnapshot` | (in workspace_problems.dart / workspace_edit.dart) | Telemetry for quick-fix apply rate, accept/reject counts. |
| `WorkspaceEditPreview` | `frontend/vityo_app/lib/src/view_ide/workspace/workspace_edit.dart` | Diff preview snapshot: document diffs, file operations, missing-document list. |
| `WorkspaceEditApplyResultViewModel` | `frontend/vityo_app/lib/src/view_ide/workspace/workspace_edit.dart` | Result of applying a workspace edit: success/failure per document. |
| `SemanticSnapshotPanelViewModel` | `frontend/vityo_app/lib/src/view_ide/language/semantic_snapshot_panel.dart` | Side panel showing semantic snapshot alongside problems. |
| `DiagnosticsInteractionAction` / `DiagnosticsQuickFixCommandRoute` | `frontend/vityo_app/lib/src/view_ide/interaction/diagnostics_interaction_model.dart` | Command routes for preview/apply quick-fix, open-document, filter-by-source. |

### 1.2 Diagnostics Navigation (revision-bound)

| Artifact | File | Role |
|----------|------|------|
| `Diagnostic` (core model) | `frontend/vityo_app/lib/src/view_ide/language/contract/language_contract.dart` | Severity + code + message + SourceRange. |
| `RevisionBoundDiagnostic` | `frontend/vityo_app/lib/src/view_ide/language/diagnostics/diagnostic_revision_gate.dart` | Diagnostic bound to a document revision; stale if revision mismatches. |
| `DiagnosticSource` / `DiagnosticConfidence` | `frontend/vityo_app/lib/src/view_ide/language/diagnostics/diagnostic_revision_gate.dart` | Source (compiler, languageService, extension) and confidence level (authoritative, heuristic, speculative). |
| `DiagnosticRangeIndex` | `frontend/vityo_app/lib/src/view_ide/language/diagnostics/diagnostic_range_index.dart` | Spatial index for range-based diagnostic lookup. |
| `StyioDiagnosticCatalog` | `frontend/vityo_app/lib/src/view_ide/language/diagnostics/styio_diagnostic_catalog.dart` | Catalog of Styio-specific diagnostic codes and messages. |
| `StyioCompilerDiagnostics` | `frontend/vityo_app/lib/src/view_ide/language/diagnostics/styio_compiler_diagnostics.dart` | Parser for Styio compiler diagnostic output. |
| `StyioNumericDiagnostics` | `frontend/vityo_app/lib/src/view_ide/language/diagnostics/styio_numeric_diagnostics.dart` | Numeric-level diagnostic mapping. |
| `WorkspaceDiagnosticsController` | `frontend/vityo_app/lib/src/view_ide/workspace/workspace_diagnostics_controller.dart` | Orchestrates diagnostics producers and dispatches snapshots. |
| `WorkspaceProblemsService.collectProblems` | `frontend/vityo_app/lib/src/view_ide/workspace/workspace_problems.dart` | Collects problems across workspace documents via `ProjectStyioLanguageService`. |

### 1.3 Test Discovery / Execution

| Artifact | File | Role |
|----------|------|------|
| `TestingSurface` widget | `frontend/vityo_app/lib/src/view_render/testing/testing_surface.dart` | Renders test discovery, latest run result, run history, failed-test retries, configuration picker, debug cancellation. |
| `TestRunRequest` | `frontend/vityo_app/lib/src/view_ide/testing/testing_provider.dart` | Request to run tests: workspaceRoot + targetId + filter + debug flag. |
| `TestDiscoveryRequest` | `frontend/vityo_app/lib/src/view_ide/testing/testing_provider.dart` | Request to discover tests: workspaceRoot + targetId + filter. |
| `TestDiscoveryResult` | `frontend/vityo_app/lib/src/view_ide/testing/testing_provider.dart` | Test discovery result: test count, test list, provider metadata. |
| `TestRunResult` | `frontend/vityo_app/lib/src/view_ide/testing/testing_provider.dart` | Run result: runner, status, counts (total/passed/failed/skipped/error), failed test list, diagnostics. |
| `TestRunConfiguration` | `frontend/vityo_app/lib/src/view_ide/testing/testing_provider.dart` | Configuration for a test run: id, label, providerId, targetId, filter, debug. |
| `TestRunConfigurationSet` | `frontend/vityo_app/lib/src/view_ide/testing/test_run_configuration_store.dart` | Persisted set of configurations with selection. |
| `TestRunHistoryStore` | `frontend/vityo_app/lib/src/view_ide/testing/test_run_history_store.dart` | Persisted run history and failed-test retry records. |
| `FailedTestDebugCancellationRoute` | `frontend/vityo_app/lib/src/view_ide/testing/testing_session_controller.dart` | Route for cancelling a failed-test debug session; bridges testing to runtime task lifecycle. |
| `FailedTestRetryRecord` | `frontend/vityo_app/lib/src/view_ide/testing/test_run_history_store.dart` | Record of a failed-test retry attempt. |

### 1.4 Source Control (status / diff / review / staging)

| Artifact | File | Role |
|----------|------|------|
| `SourceControlSurface` widget | `frontend/vityo_app/lib/src/view_render/source_control/source_control_surface.dart` | Renders SCM status, staged/unstaged changes, diff preview, branch switch, commit draft dialog, history summary. |
| `SourceControlStatusSnapshot` | `frontend/vityo_app/lib/src/view_ide/workspace/source_control_status.dart` | Immutable status from a provider: providerKind, branchName, changes list. |
| `SourceControlFileChange` | `frontend/vityo_app/lib/src/view_ide/workspace/source_control_status.dart` | A single file change: path, staged/unstaged status, originalPath. |
| `SourceControlDiffSnapshot` | `frontend/vityo_app/lib/src/view_ide/workspace/source_control_diff_session_store.dart` | Diff for one or more changed files. |
| `SourceControlDiffWindowBinding` | `frontend/vityo_app/lib/src/view_ide/workspace/source_control_diff_session_store.dart` | Binding between diff snapshot and diff window UI. |
| `SourceControlCommitDraft` | `frontend/vityo_app/lib/src/view_ide/workspace/source_control_commit_draft_store.dart` | Draft commit message and staging selection. |
| `SourceControlCommitDialogState` | `frontend/vityo_app/lib/src/view_ide/workspace/source_control_commit_draft_store.dart` | Dialog open/closed state and validation. |
| `SourceControlBranchSnapshot` | `frontend/vityo_app/lib/src/view_ide/workspace/source_control_status.dart` | All branches + current branch + branch-switch plan API. |
| `SourceControlHistorySnapshot` | `frontend/vityo_app/lib/src/view_ide/workspace/source_control_status.dart` | Commit history entries (revision, shortRevision, author, summary). |
| `SourceControlProviderAdapterRegistry` | `frontend/vityo_app/lib/src/view_ide/workspace/source_control_status.dart` | Capability-based adapter registry: register/resolve by capability. |
| `SourceControlProviderAdapterDescriptor` | `frontend/vityo_app/lib/src/view_ide/workspace/source_control_status.dart` | Descriptor: id, label, providerKind, capabilities. |
| `SourceControlStatusController` | `frontend/vityo_app/lib/src/view_ide/workspace/source_control_status_controller.dart` | Orchestrates status polling, diff loading, and action dispatch. |
| `GitPorcelainStatusParser` | `frontend/vityo_app/lib/src/view_ide/workspace/source_control_status.dart` | Parses `git status --porcelain` output into `SourceControlStatusSnapshot`. |
| `GitLogHistoryParser` | `frontend/vityo_app/lib/src/view_ide/workspace/source_control_status.dart` | Parses `git log` output into history entries. |
| `SourceControlHunkDiscardConfirmationPlan` | `frontend/vityo_app/lib/src/view_ide/workspace/source_control_status.dart` | Confirmation plan for discarding a hunk. |
| `SourceControlPartialPatchResult` | `frontend/vityo_app/lib/src/view_ide/workspace/source_control_diff_session_store.dart` | Result of a partial patch (hunk-level stage/unstage/discard). |

### 1.5 Shared / Cross-Cutting

| Artifact | File | Role |
|----------|------|------|
| `AppCommandId` enum | `frontend/vityo_app/lib/src/view_ide/commands/app_commands.dart` | Canonical command IDs: `runTests`, `rerunFailedTests`, `debugFailedTests`, `runTestConfiguration`, `debugTestConfiguration`, `refreshWorkspaceDiagnostics`, `refreshSourceControl`, `previewSourceControlDiff`, `stageSourceControl`, `unstageSourceControl`, `planSourceControlBranchSwitch`, `planSourceControlCommitDraft`, `previewQuickFix`, `applyQuickFix`, `nextDiagnostic`, `previousDiagnostic`, `showWorkspaceProblems` |
| `RuntimeTaskLifecycleEvent` | `frontend/vityo_app/lib/src/view_ide/runtime/runtime_task_lifecycle.dart` | Unified lifecycle event for test, build, run, debug tasks. |
| `RuntimeTaskDefinition` / `RuntimeTaskSnapshot` | `frontend/vityo_app/lib/src/view_ide/runtime/runtime_task_lifecycle.dart` | Definition + snapshot model consumed by testing and diagnostics. |
| `RuntimeReplaySummary` / `RuntimeLaneSummary` | `frontend/vityo_app/lib/src/view_ide/runtime/runtime_replay_summary.dart` | Lane-based event replay for runtime surface; consumed alongside test results. |
| `Breakpoint` / `BreakpointSet` | `frontend/vityo_app/lib/src/view_ide/runtime/debug_workbench_contract.dart` | Breakpoint model, reused by debug test configuration. |
| `RunConfigurationTarget` | `frontend/vityo_app/lib/src/view_ide/runtime/debug_workbench_contract.dart` | Run target model, reused by test configuration. |

## 2. Product Boundaries

Each surface is independent in UI but shares data through the workspace state layer:

```
+-----------------+     +----------------------+     +----------------------+
|  ProblemsSurface |---->| WorkspaceDiagnostics |---->| WorkspaceEditPlan    |
|  (diagnostics)   |     | Controller            |     | (quick-fix apply)    |
+-----------------+     +----------------------+     +----------------------+
                                                             |
+-----------------+     +----------------------+             v
| TestingSurface  |---->| TestRunHistoryStore  |     +----------------------+
|  (discovery+run)|     | TestConfigStore      |     | SourceControlSurface |
+-----------------+     +----------------------+     | (stage/commit)       |
                                                      +----------------------+
                                                             |
+-----------------+     +----------------------+             |
| RuntimeEvent     |<---| RuntimeTaskLifecycle |<------------+
| ReplaySummary    |     | (test/run/build/debug)|
+-----------------+     +----------------------+
```

- **Problems Panel** does NOT own the command palette, file explorer, or editor gutter decorations. It owns only the diagnostics list panel.
- **Testing Surface** does NOT own the runtime surface, debug console, or breakpoint gutter. It owns only the test-specific configuration and result list.
- **Source Control Surface** does NOT own file system watchers, workspace document store dirty-file tracking, or remote push/pull. It owns only the staged/unstaged change list, diff preview, commit draft, branch switch, and history.
- Diagnostics navigation (next/previous diagnostic, quick-fix preview/apply) is owned by `DiagnosticsInteractionModel` and dispatched via `AppCommandId` routes.

## 3. Invariants

### 3.1 Problems Panel

1. **Diagnostics are revision-bound.** Every `RevisionBoundDiagnostic` carries a `documentId` + `revision` pair. A diagnostic is *stale* if `revision != currentDocumentRevision`; stale diagnostics are never rendered.
2. **Producer lifecycle is tracked.** `WorkspaceDiagnosticsProducerLifecycleSnapshot` maps a provider ID to a `RuntimeTaskSnapshot`. The UI reads `active`, `terminal`, `cancellationRequested`, and `progress` from this snapshot, never from raw task objects.
3. **Quick-fix review is two-phase.** `WorkspaceQuickFixReviewPlan` requires explicit `onPreviewWorkspaceQuickFix` and `onApplyWorkspaceQuickFix` callbacks. Preview and apply never happen implicitly.
4. **Severity filter is declarative.** `severityFilter` is a `List<DiagnosticSeverity>` passed into the widget. The widget never computes severity filtering; it reflects what the consumer provides.
5. **Panel state is externally persisted.** `diagnosticsPanelState` and `onDiagnosticsPanelStateChanged` are owned by the consumer. The widget reads and writes panel state through these props, never through internal storage.
6. **Missing preview documents are surfaced.** `WorkspaceEditPreview.hasMissingDocuments` is rendered as an error section; the UI never silently skips missing docs.

### 3.2 Diagnostics Navigation

1. **Revision gate is strict.** `DiagnosticRevisionGate` rejects diagnostics whose `documentId` or `revision` do not match the current document state. No fallback to stale diagnostics.
2. **Unknown event kinds degrade gracefully.** Unknown `eventKind` values in runtime events are shown with a generic label; the UI never crashes or produces empty state for unrecognized kinds.
3. **Workspace diagnostic requests are bounded.** `WorkspaceProblemsQuery.maxResults` caps the number of problems collected; exceeding the limit produces `WorkspaceProblemsStatus.hitLimit`, not a crash.
4. **Diagnostic sources are tracked.** Each `RevisionBoundDiagnostic` has a `source` field (`compiler`, `languageService`, `extension`, `builtin`). The problems panel passes `onFilterBySource` through `DiagnosticsInteractionAction`.

### 3.3 Test Discovery / Execution

1. **Test results are snapshot-based.** `TestingSurface` renders from `TestRunResult` snapshots, not from live streams. `runHistory` and `failedRetryHistory` are immutable lists.
2. **Run configuration is separate from execution.** `TestRunConfiguration` is a persistent store record. Execution is triggered through `onRunConfiguration`/`onDebugConfiguration` callbacks, which translate to `RuntimeTaskDefinition` + `RuntimeExecutionHandoff`.
3. **Failed-test debug cancellation is lifecycle-routed.** `FailedTestDebugCancellationRoute` is built from a `RuntimeTaskSnapshot` and a `TestRunConfiguration`. It verifies: the runtime task exists, is a debug task, and is still active. If any check fails, `ready` is `false` and a structured `blockedReason` is produced.
4. **Discovery is optional.** `TestingSurface.discovery` is nullable. When `null`, only the "Run Tests" action header is shown; no test list is rendered.
5. **Native tool results are command-keyed.** The testing surface filters `nativeToolResults` by `AppCommandId.runTests`. Other native tool results are ignored.
6. **Retry records preserve metadata.** `FailedTestRetryRecord` stores `status`, `providerId`, `filter`, `failedCount`, and `retryTimestamp`. No retry state is inferred from the live run history.

### 3.4 Source Control (status / diff / review / staging)

1. **Status is provider-abstracted.** `SourceControlStatusSnapshot.providerKind` is an enum (`localDirtyDocuments`, `git`, `custom`). The UI reads `branchName`, `changes`, `available`, and `message` generically, never assuming a Git backing.
2. **Capability-based adapter resolution.** `SourceControlProviderAdapterRegistry.resolve(capability:)` is the single entry point for finding an adapter that supports a given operation. Callers never iterate adapters manually.
3. **Branch switch is plan-gated.** `SourceControlBranchSwitchPlan.canRun` returns `false` if: the snapshot is unavailable, target branch is empty, already on the target branch, or target is not in the branch list. The plan itself is the gate.
4. **Diff preview is a snapshot.** `SourceControlDiffSnapshot` is an immutable value. The widget never holds a streaming diff connection; it renders what is passed.
5. **Commit draft is stored locally.** `SourceControlCommitDraftStore` keeps draft state in memory. The `commitDialogState` controls whether the commit dialog is open; the widget never opens the dialog autonomously.
6. **Hunk-level actions produce partial results.** `SourceControlPartialPatchResult` captures the outcome of a hunk-level stage/unstage/discard, with structured `accepted`, `message`, and `metadata`.
7. **History entries are parsed deterministically.** `GitLogHistoryParser` uses `\x1f` as the field separator. Entries with fewer than 5 fields are still recorded but with empty optional fields, never discarded.
8. **Porcelain parsing covers all status codes.** `_statusFromPorcelainCode` maps space (32) through `?` (63), `A`, `C`, `D`, `M`, `R`, `U` into the corresponding `SourceControlFileStatus`. Unknown codes map to `unknown`.

## 4. Downstream Consumers

| Consumer | What it consumes | Surface |
|----------|----------------|---------|
| `WorkspaceController` | `WorkspaceDiagnosticsController`, `SourceControlStatusController`, workspace file operations | All surfaces via commands |
| `DiagnosticsPanelStateStore` | `DiagnosticsPanelState` | Problems panel state persistence |
| `WorkspaceDiagnosticsFilterStore` | `WorkspaceDiagnosticsFilterState` | Problems panel filter persistence |
| `TestRunHistoryStore` | `TestRunResult`, `TestRunConfiguration`, `FailedTestRetryRecord` | Testing surface history |
| `SourceControlCommitDraftStore` | `SourceControlCommitDraft`, `SourceControlCommitDialogState` | Source control commit dialog |
| `SourceControlDiffSessionStore` | `SourceControlDiffSnapshot`, `SourceControlDiffWindowBinding`, `SourceControlPartialPatchResult` | Diff preview window |
| `RuntimeTaskLifecycle` / `DebugWorkbenchContract` | `RuntimeTaskSnapshot`, `Breakpoint`, `RunConfigurationTarget` | Test debug routing |
| `HostedWorkspaceLifecycle` | Workspace-level lifecycle events | Diagnostics producer cancel on workspace close |
| `CommandPaletteModel` | `AppCommandId` entries for test/diagnostics/SCM | Keyboard-accessible command dispatch |
| `WorkbenchContextKeyService` | Context keys for problems/testing/SCM visibility | Conditional UI enablement |

## 5. Blocked / Recovery States

| State | Surface | Condition | Recovery |
|-------|---------|-----------|----------|
| Producer unavailable | Problems | `WorkspaceDiagnosticsSnapshot` is `null` | Show "No diagnostics producer" message; call `onRefreshWorkspaceDiagnostics` |
| Producer lifecycle active | Problems | `WorkspaceDiagnosticsProducerLifecycleSnapshot.active == true` | Show spinner + "Running diagnostics..." + optional progress bar; show `onCancelDiagnosticsProducer` |
| Producer lifecycle stalled | Problems | `active == true` for > expected duration | User-initiated cancel via `onCancelDiagnosticsProducer`; no auto-timeout |
| Stale diagnostics | Problems | `RevisionBoundDiagnostic.isStaleForRevision` returns true | Gate rejects the diagnostic; wait for next snapshot |
| Missing preview documents | Problems | `WorkspaceEditPreview.hasMissingDocuments == true` | Render error section with `missingDocumentIds`; prevent apply |
| Quick fix plan blocked | Problems | `WorkspaceQuickFixReviewPlan.ready == false` | Render `confirmationPlan.status` + blocked message; disable apply button |
| No test discovery | Testing | `discovery == null` | Only show "Run Tests" action; no test list |
| No test results | Testing | `lastRun == null` and `nativeToolResults` empty | Show "No test results" message |
| Test debug cancellation blocked | Testing | `FailedTestDebugCancellationRoute.ready == false` | Show `message` (e.g. "No active test debug runtime task"); disable cancel button |
| Source control provider unavailable | Source Control | `status.available == false` | Show "provider unavailable" chip; disable stage/unstage/switch actions |
| Source control empty workspace | Source Control | `status.changes.isEmpty` | Show "No changes" message; enable commit draft only if there are staged changes |
| Branch switch blocked | Source Control | `SourceControlBranchSwitchPlan.canRun == false` | Show `blockedReason` as subtitle; disable switch button |
| Hunk discard pending confirmation | Source Control | `pendingHunkDiscardConfirmation` is non-null | Show confirmation card; await `onConfirmHunkDiscard` or dismiss |
| Commit draft invalid | Source Control | `commitDialogState.ready == false` | Show validation message; disable commit button |
| No adapter for capability | Source Control | `SourceControlProviderAdapterRegistry.resolve` returns null | Capability is not exposed in UI; no fallback |

## 6. Single Implementation Path

Each surface has exactly one widget implementation and one set of model types:

| Surface | Widget | Model Barrel |
|---------|--------|--------------|
| Problems | `ProblemsSurface` | `view_render/problems/problems.dart` -> exports `problems_surface.dart` |
| Testing | `TestingSurface` | `view_render/testing/testing.dart` -> exports `testing_surface.dart` |
| Source Control | `SourceControlSurface` | `view_render/source_control/source_control.dart` -> exports `source_control_surface.dart` |
| Diagnostics | (part of ProblemsSurface) | `view_ide/language/diagnostics/diagnostics.dart` -> exports five diagnostic modules |
| Diagnostics Interaction | `DiagnosticsInteractionModel` | `view_ide/interaction/interaction.dart` -> exports `diagnostics_interaction_model.dart` |
| Runtime Events | (part of runtime surface) | `view_ide/runtime/runtime_replay_summary.dart` |

All three surface widgets import from the same `view_ide/` model layer. There is no alternative widget for any of these surfaces.

## 7. Verification Evidence

### 7.1 Problems Panel Tests

- `frontend/vityo_app/test/problems_surface_test.dart` - Widget test: renders diagnostics, keyboard navigation (arrow down, enter), workspace diagnostics snapshot, severity filtering, empty state, workspace edit preview, quick-fix review card.
- `frontend/vityo_app/test/workspace_problems_test.dart` - `WorkspaceProblemsService.collectProblems` unit test.
- `frontend/vityo_app/test/workspace_diagnostics_problems_test.dart` - Workspace diagnostics -> problem item conversion.

### 7.2 Diagnostics / Revision Gate Tests

- `frontend/vityo_app/test/diagnostic_revision_gate_test.dart` - Revision-bound diagnostic staleness, capability gaps, JSON roundtrip.
- `frontend/vityo_app/test/diagnostics_interaction_model_test.dart` - `DiagnosticsInteractionModel`, quick-fix command routes, interaction actions.
- `frontend/vityo_app/test/styio_compiler_diagnostics_test.dart` - Styio compiler diagnostic output parsing.
- `frontend/vityo_app/test/styio_diagnostic_catalog_test.dart` - Diagnostic catalog code lookup, severity mapping.
- `frontend/vityo_app/test/styio_diagnostic_snapshot_test.dart` - Diagnostic snapshot to `WorkspaceDiagnosticsSnapshot` conversion.
- `frontend/vityo_app/test/styio_numeric_diagnostics_test.dart` - Numeric severity mapping, range validation.
- `frontend/vityo_app/test/styio_syntax_diagnostics_test.dart` - Syntax diagnostic parsing from compiler output.
- `frontend/vityo_app/test/styio_workspace_diagnostics_test.dart` - Workspace-level diagnostic aggregation.

### 7.3 Testing Surface Tests

- `frontend/vityo_app/test/testing_surface_test.dart` - Widget test: renders test result, run/rerun/diagnostics buttons, configuration selection, failed-test list, debug cancellation route.
- `frontend/vityo_app/test/testing_runtime_task_history_store_test.dart` - `TestRunHistoryStore` unit tests.
- `frontend/vityo_app/test/test_run_configuration_store_test.dart` - `TestRunConfigurationStore` upsert/select/remove.

### 7.4 Source Control Tests

- `frontend/vityo_app/test/source_control_surface_test.dart` - Widget test: renders status, diff preview, branch switch, commit dialog, history, adapter registry.
- `frontend/vityo_app/test/source_control_status_test.dart` - `GitPorcelainStatusParser` parse output, `GitLogHistoryParser` parse output, `SourceControlBranchSnapshot` branch switch plan, `SourceControlProviderAdapterRegistry` register/resolve.
- `frontend/vityo_app/test/source_control_adapter_test.dart` - Adapter descriptor and capability tests.
- `frontend/vityo_app/test/source_control_commit_draft_store_test.dart` - Commit draft store mutation and validation.
- `frontend/vityo_app/test/source_control_diff_session_store_test.dart` - Diff session store, window binding, partial patch result.
- `frontend/vityo_app/test/source_control_hunk_action_test.dart` - Hunk action plan and discard confirmation.

### 7.5 Source Files (Primary Evidence)

| File | Lines (approx) | Coverage |
|------|----------------|----------|
| `frontend/vityo_app/lib/src/view_render/problems/problems_surface.dart` | 1170 | Surface widget, all UI states |
| `frontend/vityo_app/lib/src/view_render/testing/testing_surface.dart` | 423 | Surface widget, all UI states |
| `frontend/vityo_app/lib/src/view_render/source_control/source_control_surface.dart` | 1002 | Surface widget, all UI states |
| `frontend/vityo_app/lib/src/view_ide/language/contract/language_contract.dart` | 300+ | Core diagnostic/enum models |
| `frontend/vityo_app/lib/src/view_ide/language/diagnostics/diagnostic_revision_gate.dart` | 300+ | Revision-bound gate, capability gaps |
| `frontend/vityo_app/lib/src/view_ide/language/diagnostics/styio_diagnostic_catalog.dart` | 200+ | Catalog codes -> severity |
| `frontend/vityo_app/lib/src/view_ide/workspace/workspace_diagnostics.dart` | 400+ | Snapshot + producer lifecycle |
| `frontend/vityo_app/lib/src/view_ide/workspace/workspace_problems.dart` | 250+ | Problems query + service |
| `frontend/vityo_app/lib/src/view_ide/workspace/workspace_edit.dart` | 500+ | Edit plan, quick-fix review, diff preview |
| `frontend/vityo_app/lib/src/view_ide/workspace/source_control_status.dart` | 2753 | Full SCM status model + parsers + adapters |
| `frontend/vityo_app/lib/src/view_ide/workspace/source_control_status_controller.dart` | 400+ | Status polling + action dispatch |
| `frontend/vityo_app/lib/src/view_ide/workspace/source_control_diff_session_store.dart` | 300+ | Diff session + window binding |
| `frontend/vityo_app/lib/src/view_ide/testing/testing_provider.dart` | 400+ | Test request/result/config models |
| `frontend/vityo_app/lib/src/view_ide/testing/testing_session_controller.dart` | 350+ | Debug cancellation route + handlers |
| `frontend/vityo_app/lib/src/view_ide/testing/test_run_configuration_store.dart` | 200+ | Configuration persistence |
| `frontend/vityo_app/lib/src/view_ide/testing/test_run_history_store.dart` | 150+ | History + retry records |
| `frontend/vityo_app/lib/src/view_ide/commands/app_commands.dart` | 200+ | Canonical command IDs |
| `frontend/vityo_app/lib/src/view_ide/runtime/runtime_task_lifecycle.dart` | 400+ | Task definition/lifecycle/snapshot |
| `frontend/vityo_app/lib/src/view_ide/runtime/runtime_replay_summary.dart` | 200+ | Event replay lanes |
| `frontend/vityo_app/lib/src/view_ide/runtime/debug_workbench_contract.dart` | 200+ | Breakpoint + run config models |

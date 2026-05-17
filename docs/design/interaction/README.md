# Interaction

**Purpose:** Document the `docs/design/interaction/` collection scope, ownership, and maintenance rules.
**Last updated:** 2026-05-17

Interaction owns user and editor behavior: commands, controller coordination, edit transactions, document state, text buffers, input routing, focus, selection, keybindings, and workspace edit application.

Only boundary or complex interaction modules get their own README. Ordinary editor submodels are recorded here and in the Editor vertical flow view until they need dedicated design documents.

## Module Inventory

| Module | Responsibility | Separate doc |
|---|---|---|
| `command-router` | Routes commands to the correct interaction owner without owning command behavior. | No |
| `editor-controller` | Coordinates editor behavior and state owners without becoming a God Object. | No |
| `edit-transaction` | Groups coherent edits, state updates, undo grouping, dirty-state changes, service invalidation, and marker/decoration updates. | No |
| `document-model` | Owns document identity, URI, provider id, language id, revision, dirty state, and binding state. | No |
| `text-buffer` | Owns current in-memory text content and text mutation primitives. | No |
| `selection-model` | Owns cursor, selection, multi-cursor, and selection history. | No |
| `undo-redo-model` | Owns edit history, undo grouping, redo grouping, and command integration. | No |
| `document-resource-binding` | Binds editor documents to File System Manager resources and coordinates open/save/reload/conflict behavior. | No |
| `language-service-status-surface` | Projects Service-layer StyioService runtime snapshots into Interaction-owned status surface models for editor/status UI consumption without owning language truth or rendering. | No |
| `toolchain-status-surface` | Projects Toolchain-owned project state and command result envelopes into Interaction-owned status and recovery surface models without owning tool execution or rendering. | No |
| `marker-model` | Holds diagnostics, warnings, errors, stale-service states, and structured runtime failures independently from rendering. | No |
| `decoration-model` | Holds visual decoration intent independently from rendering. | No |
| `workspace-edit-applier` | Applies structured edits from language services, user commands, or code actions to open documents and file-backed resources. | No |
| `focus-coordinator` | Coordinates active focus, active editor, active panel, and input ownership. | No |
| `keybinding-router` | Maps keyboard input to commands without owning command execution logic. | No |

## Boundary

Interaction consumes Service results and Environment capabilities, but it must not own rendering, language truth, toolchain installation, or file-system implementation.

Editor file binding owns the product-side transition from resource changes into
editor document state:

```text
DocumentResourceEvent / external document
  -> EditorDocumentResourceBinding
    -> snapshotEvents
      -> ShellRuntimeModel
        -> acceptEditorExternalChange
      -> EditorSessionController.loadDocument
        -> Language Service re-analysis for the new document revision
```

This boundary is required because Language Service caches are revision-scoped.
Accepting an external file change must load a new `DocumentState.revision` before
diagnostics, completion, hover, semantic spans, references, or rename can be
served again. Interaction performs the state transition; Service decides language
facts for the resulting document revision.

For clean editor state, Shell may accept an external `DocumentResourceEvent`
automatically and reload the editor. For dirty editor state, the binding must
enter `conflicted` and Shell must not replace local content until the user chooses
a conflict resolution path.

Toolchain status follows the same projection rule:

```text
Toolchain / ProjectGraphSnapshot.toolchain
Toolchain / ToolchainCommandResult
Toolchain / ToolchainManagerStatusReport
  -> Interaction / ToolchainStatusSurface
    -> Appearance / toolchain-status-renderer
      -> Runtime Surface / status card and recovery actions
      -> Settings Surface / toolchain settings status card
```

Interaction may classify ready, unavailable, blocked, or failed toolchain states
from either the legacy project graph route or the manager-backed status report,
and expose recovery action ids. It must not run installers, choose tool
versions, interpret raw payloads, mutate configuration, or render widgets.

`ToolchainSettingsSurface` extends the same projection for Settings. It may
expose manager-backed catalog candidates, capability states, recovery state, and
install history. It still must not execute selection or installation; those
remain Shell/Toolchain command flows.

Registered candidate selection follows this interaction path:

```text
Settings Surface candidate action
  -> ShellModel.selectToolchainCandidate
    -> ToolchainManager.selectToolchain
      -> ToolchainConfigurationStore
        -> Configuration Store
          -> Foundation DataStore
```

This keeps Settings as a product entry and keeps catalog mutation in Toolchain
and Configuration ownership.

Active candidate clearing uses the same ownership path through
`ShellModel.clearToolchainCandidate` and `ToolchainManager.clearActiveToolchain`.
Settings supplies only the candidate kind; Toolchain owns the catalog mutation.

Managed-install recovery currently enters the Toolchain planning path:

```text
Settings / Recovery action
  -> ShellModel.handleToolchainRecoveryAction
    -> ShellRuntimeModel.planManagedToolchainInstallation
      -> ToolchainManager.planInstallation
        -> ToolchainInstallPlan
```

This creates a policy-backed install plan without executing download, external
installer commands, or registration side effects.

`ToolchainInstallPlanSurface` projects that plan to Settings so the user can see
the status, mode, target kind, and policy message before any future confirmed
execution flow exists.

The Settings "continue" action is intentionally limited to manual-selection
plans:

```text
Settings / Continue install plan
  -> ShellRuntimeModel.executeLastToolchainInstallPlan
    -> ToolchainManager.executeInstallPlan
      -> ToolchainInstallExecutionResult(requiresUserAction)
      -> ToolchainInstallHistorySnapshot refresh
```

This records the product workflow state without triggering downloads, external
commands, or toolchain registration.

Recovery action invocation is a Shell interaction concern:

```text
Runtime Surface button
  -> ShellModel.handleToolchainRecoveryAction
    -> ShellRuntimeModel command/log/route intent
```

The implemented action routing can retry `tool use` and `tool pin` when the
active project already has a resolved compiler, can route log viewing to the
Debug bottom tab, can open the Settings bottom surface, and can record
select/install/degraded-mode route requests. Actual toolchain selection and
managed install wizards remain separate product flows.

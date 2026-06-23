# IDE Sources Comparative Audit For Vityo

**Purpose:** Compare Vityo with external IDE and agentic-coding sources in `../ide-sources/`, identify architecture, feature, and algorithm gaps, and define an optimization route for making Vityo a Styio-first IDE with mainstream IDE core capabilities.

**Last updated:** 2026-06-21

**Date:** 2026-06-21
**Scope:** `frontend/vityo_app/lib/src/`, `docs/design/`, `docs/contracts/`, and external source trees under `../ide-sources/vscode`, `../ide-sources/intellij-community`, `../ide-sources/codex`, and `../ide-sources/opencode`.
**Method:** Main-thread source review plus four read-only subagent shards for VS Code, IntelliJ Community, Codex, and opencode.
**Status:** Open planning audit.

## Bottom Line

Vityo's product direction is correct: it should stay a Styio-specific IDE, runtime viewport, and AI collaboration surface rather than becoming a generic VS Code or IntelliJ clone. The current codebase already has strong product contracts and many IDE feature entries, especially around Styio language facts, workspace navigation, execution adapters, runtime replay, module capability matrices, and command palette search.

The major gap is not feature naming. The gap is infrastructure maturity:

1. Vityo has many IDE actions, but command execution and surfaces still lean on static enums and large switch points instead of registries, context keys, and contribution lifecycle.
2. Vityo has a custom editor, but `DocumentState` is still a full `String` snapshot and `EditorSessionController` owns too many mutation, undo, selection, and analysis refresh responsibilities.
3. Vityo has language-service contracts and fallback facts, but does not yet have a hard Styio semantic core, persistent project indexes, dumb/smart mode, or refactoring transactions grounded in compiler truth.
4. Vityo has execution and runtime adapters, but lacks a typed task runtime with streaming process events, terminal session registry, problem matching, and debug/run configuration models.
5. Vityo has AI provider profile concepts, but lacks agent sessions, tool calls, permission approvals, patch previews, append-only audit logs, and resumable agent/task state.

The best path is to absorb mechanisms, not platforms:

- From VS Code: contribution registries, command/context-key model, piece-tree-like text buffer, language feature providers, search/task/terminal/debug service boundaries.
- From IntelliJ: PSI-lite, file-based/stub indexing, WorkspaceModel-lite, VirtualFile identity and modification stamps, dumb/smart mode, safe refactoring pipeline.
- From Codex: protocolized agent sessions, turn/item event model, permission profiles, streaming command execution, patch approval events, auditable logs.
- From opencode: practical tool permission broker, patch/edit history, read-before-write guard, LSP/diagnostic feedback into tool results, session/message ledger.

## Adoption Classification

This audit separates recommendations into two decision classes:

1. **Direct best practice:** A proven IDE or agentic-coding mechanism that can be adopted with local Dart/Flutter implementation choices. These items do not change Vityo's product identity or Styio language semantics.
2. **Vityo/Styio design discussion:** A valuable pattern that must be shaped by Styio syntax, semantic facts, runtime model, platform policy, or Vityo's product surface before implementation.

Direct best practices to apply now:

1. Command, context-key, and view/surface registries. These are workbench hygiene patterns and should replace large switch points gradually.
2. Transactional file edits with expected revision/hash validation, non-overlapping edit checks, undo grouping, and stale-document rejection.
3. Durable process/task session records with stdout/stderr deltas, cancellation, exit status, and redacted environment metadata.
4. Permission gates for command execution, toolchain actions, file writes, patch apply, and external-resource access.
5. Patch preview before workspace writes, followed by append-only audit events for approval and apply results.
6. Progress, cancellation, include/exclude filters, and result caps for workspace search and symbol search.
7. Capability-gated module contributions instead of arbitrary runtime extension code.
8. Degraded mode when indexes or semantic facts are stale, so unsafe refactors are disabled while editing and simple navigation remain available.

Vityo/Styio design topics to discuss before implementation:

1. The exact shape of `StyioSemanticCore`: AST vs PSI-lite boundaries, symbol identity, reference edges, semantic block facts, resource/task graph facts, and compiler/toolchain ownership.
2. Which Styio facts are authoritative in the compiler/service and which may remain editor-local fallbacks.
3. Whether `DocumentState` should move directly to a piece-table implementation or first introduce a smaller transaction layer around the current string model.
4. How module contributions should map to Styio-specific surfaces, runtime visualizers, agent tools, mobile constraints, and hosted/local platform policy.
5. How task, run, debug, replay, and runtime-event models should represent Styio workflows rather than generic shell commands.
6. How AI approvals should present semantic intent: affected Styio symbols, resources, tasks, runtime lanes, diagnostics, and execution routes.
7. How much LSP/DAP/MCP compatibility Vityo should expose externally while keeping Styio-native contracts internally.
8. What "mobile-first Styio IDE" interactions should look like instead of simply compressing a desktop workbench.

## Source Inventory

| Source | Relevant external paths | Vityo value |
|--------|-------------------------|-------------|
| VS Code | `src/vs/workbench/`, `src/vs/platform/commands/`, `src/vs/platform/contextkey/`, `src/vs/editor/common/model/pieceTreeTextBuffer/`, `src/vs/editor/common/languageFeatureRegistry.ts`, `src/vs/platform/quickinput/common/quickAccess.ts` | Workbench contribution lifecycle, command registry, context keys, quick access routing, piece tree text buffer, language provider registry. |
| IntelliJ Community | `platform/core-api/src/com/intellij/psi/`, `platform/indexing-api/`, `platform/backend/workspace/`, `platform/core-api/src/com/intellij/openapi/vfs/`, `platform/lang-impl/src/com/intellij/refactoring/rename/` | PSI/reference model, incremental indexes, workspace entity snapshots, VFS identity/stamps, safe refactoring workflow. |
| Codex | `codex-rs/app-server/src/command_exec.rs`, `codex-rs/app-server/src/thread_state.rs`, `codex-rs/protocol/src/protocol.rs`, `codex-rs/apply-patch/src/parser.rs` | Agent thread/turn lifecycle, typed command execution, approval and permission protocol, patch grammar, event/audit model. |
| opencode | `internal/permission/permission.go`, `internal/session/session.go`, `internal/message/content.go`, `internal/llm/tools/edit.go`, `internal/llm/tools/patch.go`, `internal/lsp/client.go` | Tool-level permission broker, message/session ledger, file edit and patch flow, read-before-write guard, diagnostics after tool execution. |

## Vityo Baseline

Current Vityo strengths:

1. Product scope is explicit in `docs/design/Vityo-Product-Spec.md` and `docs/design/Vityo-System-Architecture.md`: Flutter UI, custom editor engine, module host, language workspace service, project graph, execution, runtime events, and agent/profile layer are separated by product-owned contracts.
2. Language-service contracts are broad: `frontend/vityo_app/lib/src/view_ide/language/contract/language_contract.dart` and `frontend/vityo_app/lib/src/view_ide/language/service/capability_routed_styio_language_service.dart` cover diagnostics, completion, hover, semantic tokens, formatting, document symbols, references, definition, rename, safe delete, extract function, change signature, parameter info, inlay hints, and semantic blocks.
3. Workspace features already cover mainstream IDE entry points: `workspace_search.dart`, `workspace_quick_open.dart`, `workspace_symbol_search.dart`, `workspace_definition.dart`, `workspace_reference_search.dart`, `workspace_rename.dart`, `workspace_call_hierarchy.dart`, `workspace_code_actions.dart`, `workspace_code_lens.dart`, and related tests.
4. Backend boundaries exist: `backend_toolchain/project_graph_contract.dart`, `project_graph_adapter_io.dart`, `execution_adapter.dart`, `execution_adapter_io.dart`, `runtime_event_adapter.dart`, and hosted-control-plane codecs distinguish local CLI and hosted routes.
5. Module boundaries exist: `module_manifest.dart`, `module_capability_matrix.dart`, `module_registry.dart`, and `module_lifecycle.dart` already model core/optional modules, platform capability, mounted state, installability, and staged update intent.
6. Toolchain and platform foundations exist: `environment/system_compatibility/process/process_manager.dart`, `shell/shell_manager.dart`, `pty/pty_manager.dart`, `toolchain/terminal_runtime.dart`, and `toolchain/toolchain_runtime.dart` provide lower-level primitives for future task/terminal systems.

Current Vityo limitations:

1. `frontend/vityo_app/lib/src/view_ide/editor/document/document_state.dart` is a full-string document model. It recalculates line starts from `text.split('\n')`, which is simple and correct for small files but not an IDE-grade text buffer.
2. `frontend/vityo_app/lib/src/view_ide/editor/controller/editor_controller.dart` centralizes editing, selection, undo/redo, language feature reads, and repeated `_refreshAnalysis()` calls. `editor/transactions/transactions.dart` is still an empty boundary marker.
3. `frontend/vityo_app/lib/src/view_ide/shell_runtime/shell_runtime_model.dart` and `frontend/vityo_app/lib/src/view_render/shell/vityo_shell_scaffold.dart` still contain large command/surface dispatch surfaces instead of a contribution registry.
4. `frontend/vityo_app/lib/src/view_ide/language/semantic/styio_symbol_index.dart` is valuable fallback logic, but it is token/rule-derived and should not become the long-term source of truth for cross-file Styio semantics.
5. Search and symbol services currently load documents and scan/tokenize per operation. That is acceptable for early functionality, but it does not scale to large workspaces or hosted/local parity without indexes, progress, and cancellation.
6. `ExecutionAdapter.runActiveDocument` returns completed sessions and parsed logs. It does not yet expose typed process ids, stdout/stderr deltas, stdin, resize, kill, permission profile, or task lifecycle events.
7. `AgentPromptProfile` defines provider route and context channels, but there is no `AgentSession`, `AgentTurn`, `ToolCall`, `PermissionRequest`, `PatchPreview`, or durable agent ledger.

## Architecture Differences

### Workbench And Contributions

VS Code uses registries and contribution lifecycle to keep the workbench extensible without every feature depending on one shell controller. The useful pattern is `registry + descriptor + activation/context`, not the exact Electron or DOM implementation.

Vityo currently has static command descriptors in `commands/app_commands.dart`, search scoring in `commands/command_palette.dart`, and a large shell runtime that maps command ids to behavior. This is workable for bootstrap, but it will fight module-driven growth.

Optimization:

1. Add a pure Dart `IdeCommandRegistry` with command id, label, category, shortcut, precondition, handler, permission requirement, and disposal.
2. Add a `ContextKeyService` subset for conditions such as `styio.hasProject`, `styio.executionReady`, `editor.hasSelection`, `agent.hasProvider`, `runtime.hasReplay`, and `module.localRuntimeMounted`.
3. Add `SurfaceRegistry` and `IdeViewDescriptor` for bottom/side panels. Start by moving runtime, agent, problems, search, debug, settings, and toolchain status out of hardcoded switch points.
4. Let `module_host` contribute only controlled extension points: commands, surfaces, themes, Styio language providers, tasks, runtime visualizers, and debug visualizers.

Do not copy VS Code's Node extension host or marketplace at this stage.

### Module And Extension Model

VS Code and IntelliJ both have broad plugin ecosystems. Vityo should not. Vityo's `ModuleManifest` and `ModuleCapabilityMatrix` are a better product fit because Styio-specific modules need platform policy, distribution channel, iOS safety, mounted state, and staged update semantics.

Optimization:

1. Keep Vityo modules product-owned and capability-gated.
2. Add explicit contribution sections to module manifests rather than arbitrary code execution:
   - `commands`
   - `views`
   - `languageProviders`
   - `tasks`
   - `runtimeVisualizers`
   - `agentTools`
3. Require every contribution to declare platform support, permission needs, activation condition, and fallback message.

## Editor And Text Model Differences

VS Code's `PieceTreeTextBuffer` is the most relevant algorithmic reference. It supports efficient inserts/deletes, line/offset mapping, snapshots, edits, inverse edits, and content-change events. Vityo currently replaces substrings on a full `String` and derives line starts on demand.

Short-term optimization:

1. Implement `EditorTransaction` and `WorkspaceEdit` first. This is lower risk than immediately replacing the text buffer.
2. Every edit should carry:
   - `documentId`
   - expected `revision`
   - optional `contentHash`
   - non-overlapping ranges
   - undo group id
   - source: user, format, code action, rename, search replace, agent patch
3. Apply multiple text edits in descending offset order and reject stale documents.
4. Route format, rename, code action, search replace, quick fix, and AI patch through the same transaction service.

Medium-term optimization:

1. Replace full-string `DocumentState` internals with a piece-table or rope-like `TextBuffer`.
2. Cache line starts or line metadata and publish delta events.
3. Keep Source Buffer and visual substitution strictly separate, preserving the product invariant from `Vityo-Product-Spec.md`.
4. Move undo/redo out of `EditorSessionController` into transaction history.

Recommended sequence:

1. `DocumentSnapshot` remains immutable at public boundaries.
2. `MutableTextBuffer` owns efficient mutation and offset/line mapping.
3. `EditorTransactionService` validates and applies edits.
4. `EditorSessionController` becomes orchestration and selection state, not the owner of every mutation rule.

## Language Intelligence And Indexing Differences

IntelliJ's most valuable contribution is the model behind language intelligence:

1. PSI-like syntax/semantic tree with stable ranges and element identity.
2. References that resolve to declarations and can be rebound or renamed.
3. File-based indexes and stub indexes that avoid reprocessing every file for every query.
4. Dumb/smart mode to protect correctness while indexes are stale.
5. Safe refactoring pipeline: collect usages, resolve again, check conflicts, preview, apply transaction, undo.

Vityo has the right language-service surface, but it still needs a Styio-native semantic core.

Recommended `StyioSemanticCore`:

1. `DocumentSnapshot(documentId, fileId, revision, contentHash, languageVersion)`
2. `StyioAst` or PSI-lite with nodes, parent/child relationships, source ranges, and semantic kind.
3. `SymbolId(package, module, fileId, kind, qualifiedName, declarationHash)`
4. `ReferenceEdge(sourceFileId, rangeAnchor, targetSymbolId, accessKind)`
5. `DiagnosticFact(source, code, rangeAnchor, severity, dependencyKeys)`
6. `StyioSemanticSnapshot(projectGraphVersion, toolchainId, configHash, factsVersion)`

Recommended indexes:

1. Per-file forward index: declarations, imports, exports, references, resources, tasks, function signatures, semantic blocks, local diagnostics.
2. Project inverted index: symbol name/kind/export/package to declarations, target symbol to usages, import target to dependents.
3. Dependency graphs: file import graph, package graph, task/resource call graph. Use SCC detection for cycles and topological invalidation for dependent facts.

Cache keys must include more than document revision:

```text
contentHash
projectGraphVersion
toolchainId
languageProtocolVersion
styioConfigHash
lock/vendor state
platform target
capability state
```

Fallback policy:

1. Tokenization and basic syntax highlighting may stay local and immediate.
2. `StyioSymbolIndex` remains an offline/degraded fallback.
3. Cross-file rename, safe delete, type facts, call hierarchy, and import resolution should move to StyioService facts as soon as upstream exposes them.
4. When semantic indexes are stale, enter a dumb/degraded mode: keep editing, local tokens, and simple search available; disable or mark unsafe advanced refactors.

## Search, Navigation, And Refactoring Differences

VS Code provides search providers with progress, cancellation, include/exclude rules, and result limits. IntelliJ provides index-backed navigation and usage queries. Vityo currently offers good user-facing commands, but many services scan documents per request.

Optimization:

1. Introduce `WorkspaceFileIndex` with file categories:
   - source
   - test
   - vendor
   - build
   - generated
   - hosted
   - scratch
2. Back `WorkspaceSymbolSearchService`, `WorkspaceReferenceSearchService`, and rename preview with `StyioSemanticCore`.
3. Add progress and cancellation to text search and symbol search.
4. Use ripgrep on desktop as a provider implementation, not as the internal API.
5. Keep hosted search behind the same provider contract.

Refactoring transaction rules:

1. Find target symbol through semantic facts.
2. Query usage index by `SymbolId`.
3. Re-resolve candidate references against current snapshots.
4. Detect conflicts and shadowing.
5. Generate a preview grouped by file.
6. Validate every target document revision/hash.
7. Apply non-overlapping edits transactionally.
8. Persist undo metadata.
9. Re-run diagnostics and show changed problem count.

## Execution, Tasks, Terminal, And Debug Differences

VS Code separates tasks, terminal, and debug. Codex separates task command execution from long-lived process/PTY sessions. Vityo has lower-level primitives but not yet the IDE-grade orchestration layer.

Current Vityo anchors:

1. `backend_toolchain/execution_adapter.dart` models `ExecutionSession`.
2. `backend_toolchain/execution_adapter_io.dart` runs local/hosted workflows and parses outputs.
3. `backend_toolchain/runtime_event_adapter.dart` and `runtime/runtime_replay_summary.dart` summarize runtime events.
4. `environment/system_compatibility/process/process_manager.dart`, `shell/shell_manager.dart`, and `pty/pty_manager.dart` expose process and terminal primitives.
5. `toolchain/terminal_runtime.dart` and `toolchain/toolchain_runtime.dart` wrap toolchain execution.

Optimization:

1. Add `TaskExecutionRuntime`:
   - operation id
   - process id
   - command argv
   - cwd
   - environment overlay with redaction
   - permission profile
   - stdout/stderr deltas
   - diagnostics
   - runtime events
   - exit status
   - cancellation
2. Add `TerminalRuntimeRegistry`:
   - start/list/write/resize/kill/cleanup
   - PTY session metadata
   - output cap
   - restore-after-restart as historical, not live
3. Add `StyioTask` descriptors:
   - build
   - run
   - test
   - fetch dependencies
   - vendor dependencies
   - pack
   - prepare publish
   - preflight
4. Add problem matcher equivalents for Styio diagnostics and JSONL facts.
5. Add `RunConfiguration`-lite:
   - target package
   - target name
   - target kind
   - execution route
   - before-run tasks
   - environment overlays
   - platform policy

Debug should be Styio-specific first. A DAP bridge can come later; internally Vityo should model runtime event lanes, state/resource graphs, breakpoints, current unit, variables, and replay windows.

## Agentic IDE Differences

Codex and opencode show that useful AI integration is an execution system, not a chat box. The valuable pattern is:

1. durable session and turn state
2. structured message parts
3. tool calls and tool results
4. permission requests
5. patch preview and approval
6. command execution with output deltas
7. append-only audit log
8. resumable history
9. diagnostics after edits

Vityo already has `agent/agent_profile.dart`, provider routes, and context channel concepts. It needs the runtime layer.

Recommended P0 agent model:

1. `AgentSession`
2. `AgentTurn`
3. `AgentMessagePart`
4. `ToolInvocation`
5. `ToolResult`
6. `PermissionRequest`
7. `FileChangePreview`
8. `PatchApplyPlan`
9. `AgentAuditEvent`

Permission model:

1. `readOnly`: search, read files, read diagnostics, inspect project graph.
2. `workspaceWrite`: modify workspace files after diff preview approval.
3. `toolchainManaged`: run whitelisted Styio/spio/toolchain tasks.
4. `fullAccessDisabledByDefault`: any non-workspace or unclassified command requires explicit user opt-in.

Approval decisions:

1. allow once
2. allow for this session
3. deny
4. cancel turn

Agent patch flow:

1. parse Codex-style apply-patch subset or Vityo-native `WorkspaceChangeSet`
2. validate paths and workspace containment
3. generate side-by-side or grouped diff preview
4. request permission
5. apply through `EditorTransactionService` or `WorkspaceDocumentStore`
6. run Styio diagnostics
7. feed diagnostics and changed files back as tool result
8. append audit event

Vityo-specific advantage:

The user should approve semantic intent, not only text edits. For Styio, a patch preview should eventually show affected surfaces, resources, tasks, runtime graph nodes, diagnostics, and execution routes. The approval prompt should be able to say: this change updates a Styio workflow/resource surface and affects these files, symbols, and runtime events.

## Priority Roadmap

### P0: Stabilize Contracts And Safety

1. **Direct best practice:** Add `EditorTransaction` and `WorkspaceEdit` and route formatting, rename, quick fixes, search replace, and agent patch through it.
2. **Direct best practice:** Add `IdeCommandRegistry`, `ContextKeyService`, and `SurfaceRegistry` while keeping existing `AppCommandId` as compatibility ids.
3. **Direct best practice:** Add document/project result staleness metadata: revision, content hash, project graph version, toolchain id, and capability state.
4. **Direct best practice:** Add `AgentSession`, `ToolInvocation`, `PermissionRequest`, and `FileChangePreview` data models.
5. **Direct best practice:** Add `CommandPermissionService` in front of process, shell, toolchain, and execution adapter routes.
6. **Direct best practice:** Add append-only audit events for command, permission, patch preview, patch apply, execution exit, and diagnostics result.

### P1: Build IDE-Grade Internal Services

1. **Vityo/Styio design discussion:** Replace full-string-only document internals with a piece-table or rope-like text buffer. The algorithm is proven, but rollout should respect current editor contracts and Source Buffer/visual substitution invariants.
2. **Vityo/Styio design discussion:** Add `StyioSemanticCore` with PSI-lite, forward index, inverted symbol index, and dependency graph invalidation. The exact facts and ownership must match Styio compiler/service semantics.
3. **Vityo/Styio design discussion:** Add `WorkspaceModelLite` and `WorkspaceFileIndex` derived from `ProjectGraphSnapshot`. File categories and invalidation rules should follow Styio package/resource conventions.
4. **Direct best practice:** Add `TaskExecutionRuntime` and `TerminalRuntimeRegistry` with streaming output and cancellation.
5. **Direct best practice:** Add search providers with progress, cancellation, desktop ripgrep implementation, and hosted implementation.
6. **Direct best practice:** Add dumb/degraded mode for stale semantic indexes.

### P2: Move Styio Truth Upstream And Deepen Runtime UX

1. **Vityo/Styio design discussion:** Integrate real StyioService scope graph, type facts, signature facts, import resolution facts, and semantic block facts.
2. **Vityo/Styio design discussion:** Move cross-file rename, safe delete, call hierarchy, and type hierarchy from fallback heuristics to semantic facts.
3. **Vityo/Styio design discussion:** Add Styio run/debug configuration model and runtime-event-backed debug adapter.
4. **Vityo/Styio design discussion:** Add module contribution points for commands, views, tasks, language providers, themes, runtime visualizers, and agent tools.
5. **Direct best practice:** Add session resume for agent sessions, task runs, terminal history, and runtime event windows.

### P3: Product Differentiation

1. **Vityo/Styio design discussion:** Add Styio-aware AI context broker: file, selection, diagnostics, semantic index, project graph, runtime graph, tasks, terminal logs, module graph.
2. **Vityo/Styio design discussion:** Make AI-generated changes report affected Styio symbols, resources, tasks, runtime lanes, and diagnostics.
3. **Vityo/Styio design discussion:** Add mobile-specific Styio editing and execution interactions rather than shrinking the desktop workbench.
4. **Vityo/Styio design discussion:** Add optional bridges for LSP/DAP/MCP only where they serve Styio workflows.

## Do Not Absorb Yet

1. VS Code's Electron workbench, arbitrary Node extension host, generic marketplace, and broad language/plugin compatibility goals.
2. IntelliJ's full platform, Swing UI, heavy plugin APIs, and generic multi-language project model.
3. Codex's full MCP/skills/plugin marketplace, proactive/multi-agent systems, realtime audio, and complete OS sandbox implementations.
4. opencode's broad provider matrix as a product dependency.
5. A generic LSP/DAP-first internal architecture. Vityo should use Styio-native contracts internally and bridge to LSP/DAP only when needed.

## Acceptance Signals

Vityo is moving toward a Styio-first mainstream IDE when these statements become true:

1. A user can run, search, navigate, refactor, and ask AI without leaving the IDE shell.
2. Every file edit from format, rename, quick fix, search replace, or AI patch is a validated `WorkspaceEdit`.
3. Cross-file navigation and rename are backed by semantic facts or clearly marked degraded fallback.
4. Large files and repeated edits do not require full-string replacement and full analysis refresh on every keystroke.
5. Tasks and terminals stream output, support cancellation, and produce typed runtime events.
6. AI actions cannot write files, run commands, or reach external resources without permission profiles and audit events.
7. Module-contributed functionality is visible only when capability matrices and platform policy allow it.
8. Hosted, desktop, Android, iOS, and Web execution routes share contracts even when implementations differ.

## Follow-Up Work Items

1. Draft `EditorTransaction` and `WorkspaceEdit` contracts under `frontend/vityo_app/lib/src/view_ide/editor/transactions/`.
2. Draft `IdeCommandRegistry`, `ContextKeyService`, and `SurfaceRegistry` in `view_ide/commands` or a new `view_ide/workbench` boundary.
3. Draft `StyioSemanticCore` and index contracts in `view_ide/language/semantic`.
4. Draft `WorkspaceModelLite` and `WorkspaceFileIndex` in `view_ide/workspace`.
5. Draft `AgentSession` and permission/audit models in `view_ide/agent`.
6. Draft `TaskExecutionRuntime` and `TerminalRuntimeRegistry` around existing process, shell, PTY, execution, and toolchain managers.

# Vityo Delivered Design Baseline

**Purpose:** Consolidate completed Vityo implementation-plan outcomes into stable design documentation after retiring `docs/plan/` as an active documentation area.

**Last updated:** 2026-05-16

**Status:** Design baseline

## 1. Scope

This document records work that has already been closed at the design, adapter-surface, code-anchor, or test-anchor level.

It is not a fresh validation report. It preserves the delivered architecture baseline so active gaps can move into [Vityo-Implementation-Gaps.md](./Vityo-Implementation-Gaps.md) instead of remaining in plan documents.

Evidence levels:

| Evidence level | Meaning |
|---|---|
| Design baseline | The architecture boundary is documented and accepted for current design work. |
| Code anchor | A repo-local implementation path exists for the capability. |
| Test anchor | A repo-local test path exists for the capability. This document does not claim the test was run today. |
| Minimum closure | The current product slice is represented, but not necessarily product-complete. |

## 2. Product And System Foundation

Vityo's product shape is stable:

| Area | Delivered baseline |
|---|---|
| Product identity | Vityo is the dedicated Styio IDE and runtime surface, not a VS Code skin or generic editor shell. |
| Frontend shape | Flutter UI runtime, custom editor engine, runtime/AI/theme panels, and module host runtime. |
| Backend/toolchain shape | Product-owned adapter layer, local CLI/FFI route, hosted control plane route, and upstream machine-contract consumption. |
| Adapter ownership | Vityo owns product adapter contracts; upstream services adapt to those contracts. |
| Capability gap behavior | Missing upstream capability is represented as blocked or partial status instead of guessed state. |
| Repository naming | Current product and repo language uses Vityo / vityo-nightly. |

Primary design documents:

| Document | Role |
|---|---|
| [Vityo-Product-Spec.md](./Vityo-Product-Spec.md) | Product SSOT. |
| [Vityo-System-Architecture.md](./Vityo-System-Architecture.md) | System architecture SSOT. |
| [architecture-views/vertical-flow-diagrams/editor/README.md](./architecture-views/vertical-flow-diagrams/editor/README.md) | Editor vertical-line design. |

## 3. Delivered Workstream Baseline

| Workstream | Delivered baseline | Evidence level |
|---|---|---|
| Product Foundation | Product contracts, repository boundary, adapter boundary, capability gap rules, and platform execution matrix are documented. | Design baseline |
| Editor Engine | Document state, selection state, undo/redo, keyboard editing, source buffer fidelity, glyph substitution cursor mapping, and language interaction smoke anchors exist. | Minimum closure |
| Adapter Layer | Backend toolchain adapter surface exists for project graph, execution, runtime events, dependency source, deployment, toolchain management, and capability snapshots. | Minimum closure |
| Project Model | Canonical project graph, workspace members, dependencies, targets, toolchain, lock/vendor/build state, and hosted payload consumption are represented. | Minimum closure |
| Execution Routing | Scratch single-file route, project build/run/test route, JIT route intent, deploy preflight, command routing, and blocked handoff UI are represented. | Minimum closure |
| Runtime Surface | Runtime event envelope, event registry, thread lanes, graph summary, and debug console replay are represented. | Minimum closure |
| AI Surface | OpenAI-compatible endpoint profile, platform provider route, and context-channel persistence contract are represented. | Minimum closure, not product-complete |
| Theme System | Theme preset and user override token round-trip are represented. | Minimum closure, not product-complete |
| Mobile And Hosted | iOS cloud route, Web hosted workspace route, and hosted project/dependency/deployment/execution payload route are represented. | Minimum closure, not product-complete |
| Module Runtime | Core/optional lifecycle, staged update flag, and optional uninstall reclamation policy are represented. | Minimum closure, not product-complete |

## 4. Code And Test Anchors

These anchors are preserved from the retired planning docs.

| Area | Code anchor | Test anchor |
|---|---|---|
| Editor | `frontend/vityo_app/lib/src/editor/` | `frontend/vityo_app/test/editor_controller_editing_test.dart`, `frontend/vityo_app/test/styio_language_service_smoke_test.dart` |
| Backend toolchain | `frontend/vityo_app/lib/src/backend_toolchain/` | `frontend/vityo_app/test/integration_compatibility_exports_test.dart`, `frontend/vityo_app/test/hosted_control_plane_client_test.dart` |
| Project model | `frontend/vityo_app/lib/src/backend_toolchain/project_graph*` | `frontend/vityo_app/test/project_graph_adapter_test.dart`, `frontend/vityo_app/test/toolchain_management_adapter_test.dart` |
| Execution | `frontend/vityo_app/lib/src/backend_toolchain/execution_adapter.dart` | `frontend/vityo_app/test/execution_adapter_test.dart`, `frontend/vityo_app/test/execution_route_summary_test.dart`, `frontend/vityo_app/test/deployment_adapter_test.dart`, `frontend/vityo_app/test/app_commands_test.dart` |
| Runtime surface | `frontend/vityo_app/lib/src/runtime/`, `frontend/vityo_app/lib/src/backend_toolchain/runtime_event_adapter.dart` | `frontend/vityo_app/test/runtime_surfaces_test.dart` |
| Agent profile | `frontend/vityo_app/lib/src/agent/agent_profile.dart` | `frontend/vityo_app/test/agent_profile_test.dart` |
| Theme tokens | `frontend/vityo_app/lib/src/theme/vityo_theme.dart` | `frontend/vityo_app/test/vityo_theme_test.dart` |
| Module lifecycle | `frontend/vityo_app/lib/src/module_host/module_lifecycle.dart` | `frontend/vityo_app/test/module_lifecycle_test.dart` |
| Hosted control plane | `frontend/vityo_app/lib/src/backend_toolchain/hosted_control_plane*.dart` | `frontend/vityo_app/test/hosted_control_plane_client_test.dart`, `frontend/vityo_app/test/hosted_payload_codec_test.dart` |

## 5. Runtime Layer Baseline

Vityo currently treats runtime architecture as these product layers:

| Layer | Responsibility |
|---|---|
| Appearance Layer | Rendering, layout, theme, icons, semantic color mapping, visual states, and widgets. |
| Interaction Layer | Editor behavior, command routing, keybindings, selection, cursor, workspace edit application, and focus management. |
| Service Layer | Service integration boundary for StyioService, remote services, toolchain-facing services, optional user service, result adaptation, version binding, service caches, fixture expectation, and Vityo-facing intake. |
| Foundation Layer | Shared mechanics for DataStore API, DataStore Owner contract, registry, workspace scope, and resource coordination. |
| Environment Layer | Toolchain, system compatibility, extensions, fallback registration, configuration, execution, and platform-specific services. |

The layer model is a design boundary, not a mandatory runtime call chain.

Ordinary submodules are documented in their owning layer README instead of requiring one README per directory. Dedicated README files are reserved for layer boundaries, direct services, complex internal designs, and architecture views.

## 6. Vertical Flow View Baseline

Vityo tracks primary vertical flows as design review views. They are not implementation directories. App Shell Surface remains the top visible surface, but user/account/profile is an optional Service Layer module:

| Vertical flow view | Baseline |
|---|---|
| Registry Line | Register discoverable boundaries only: schema, provider, command, capability, renderer, and policy. |
| DataStore Line | Stateful layers use explicit DataStore Owners; Foundation DataStore may use File System Manager, but File System Manager must not depend on DataStore. |
| Configuration Line | User-configurable settings are schema-owned and migration-aware. |
| Theme Line | Theme crosses User, Appearance, Interaction, and Environment while intentionally skipping Language. |
| Editor Flow | Editor crosses all product layers as a design view without becoming a new top-level layer or runtime directory. |
| Service Line | Service providers own provider truth; Vityo owns protocol interaction, adaptation, caching, product interaction, rendering, and application. For StyioService specifically, Styio owns language truth. |
| Execution Line | Execution Manager owns execution semantics; Process Manager owns process lifecycle; Toolchain Encoder/Decoder own process/protocol IO conversion. |
| Extension Line | Extensions contribute capabilities through registry, permission, capability, and configuration boundaries. |
| System Compatibility Line | Platform, file system, process, shell, network, permission, and resource behavior are normalized behind manager interfaces and facts. |

## 7. Service Layer Baseline

The Service Layer generalizes service integration. Language service is one service family, not the whole layer.

For Styio language service, ownership is split as follows:

| Side | Owns |
|---|---|
| StyioService | Styio grammar, parser, syntax diagnostics, semantic facts, type facts, scope graph, references, definitions, completion candidates, hover raw content, semantic tokens, language-level code actions, rename safety, and import/workspace language graph. |
| Vityo | Service discovery, transport, adapter, document-version binding, stale-result rejection, product presentation, editor interaction, fallback UI, and workspace edit application. |

Vityo must not become a second Styio compiler.

Design modules already extracted:

| Module | Design document |
|---|---|
| Styio Language Service | [service/styio-language-service/README.md](./service/styio-language-service/README.md) |
| Styio Result Adapter | [service/styio-language-service/styio-result-adapter/README.md](./service/styio-language-service/styio-result-adapter/README.md) |
| Language Fixture Confidence Matrix | [service/styio-language-service/language-fixture-confidence-matrix/README.md](./service/styio-language-service/language-fixture-confidence-matrix/README.md) |


## 7.1 Optional User Service Baseline

User/account/profile capabilities are optional Service Layer capabilities exposed through the `user-service/` root service.

```text
App Shell Surface
  -> local IDE behavior
  -> optional User Service
      -> local profile store
      -> optional profile sync adapter
      -> optional account/session service
```

Rules:

| Rule | Meaning |
|---|---|
| No login required | Local editing, settings, themes, toolchain selection, and local projects must work without login. |
| Local-first profile | Local profile state is available even when sync/account service is missing. |
| Optional sync | Cross-device profile sync is an optional user service capability. |
| App shell separation | UI surfaces show account/recovery state but do not own account logic. |

Design document: [service/user-service/README.md](./service/user-service/README.md)

## 8. Foundation Baseline

Foundation is the shared mechanics layer. It does not own settings, tools, platform APIs, language truth, editor behavior, or rendering.

| Module | Delivered design boundary |
|---|---|
| DataStore API | Shared persistence mechanics, schema states, migrations, and record writes through File System Manager. |
| DataStore Owner | Layer-local state ownership with Foundation DataStore API below it and File System Manager below DataStore. |
| Registry | Shared registration mechanics without owning feature semantics. |
| Workspace | Workspace identity, scope, lifecycle, and scoped service references. |
| Resource Coordinator | Namespace-to-location routing and budget handoff to Environment Resource Manager. |

Design documents:

| Module | Design document |
|---|---|
| Foundation | [foundation/README.md](./foundation/README.md) |
| DataStore Owner | [foundation/data-store-owner/README.md](./foundation/data-store-owner/README.md) |

## 9. Environment Baseline

| Module | Delivered design boundary |
|---|---|
| Platform Context | Facts-only platform context. Application configuration stays in Configuration Store. |
| File System Manager | Stable file-system manager interface with system-specific implementations for local, remote, browser-backed, virtual, or hosted file systems. |
| Manager-local permission handling | Permission checks are local to the concrete manager that owns the operation; failures still expose explicit denial reasons and recovery hints. |
| Environment Variable Configuration | Vityo persists IDE-owned env overlays, not OS-level environment variables. |

Design documents:

| Module | Design document |
|---|---|
| Environment Variable Configuration | [environment/configuration-store/environment-variable-configuration/README.md](./environment/configuration-store/environment-variable-configuration/README.md) |
| Platform Context | [environment/system-compatibility-manager/platform-context/README.md](./environment/system-compatibility-manager/platform-context/README.md) |
| File System Manager | [environment/system-compatibility-manager/file-system-manager/README.md](./environment/system-compatibility-manager/file-system-manager/README.md) |
| System Compatibility Manager | [environment/system-compatibility-manager/README.md](./environment/system-compatibility-manager/README.md) |

## 10. Editor Baseline

Editor is a vertical flow view. Its implementation remains split across horizontal layers:

```text
Appearance Layer
  -> Editor Surface / Editor Renderer / Decoration Renderer
Interaction Layer
  -> Command Router / Editor Controller / Edit Transaction
  -> Document Model / Text Buffer / Selection Model / Undo Redo Model
  -> Document Resource Binding / Marker Model / Decoration Model
Service Layer
  -> Styio Language Service / optional User Service status
Foundation Layer
  -> DataStore API / Resource Coordinator / Workspace scope / Registry
Environment Layer
  -> Configuration Store / File System Manager / Toolchain / Execution
```

The accepted file-system-to-editor shape is documented in [vertical-lines/README.md](./vertical-lines/README.md) and [architecture-views/vertical-flow-diagrams/editor/README.md](./architecture-views/vertical-flow-diagrams/editor/README.md). The short form is:

```text
File System Manager
  -> Document Resource Binding
    -> Editor Controller
      -> Edit Transaction
      -> Document Model / Text Buffer / Selection Model / Undo Redo Model
      -> Marker Model / Decoration Model
      -> Styio Language Service
      -> Editor Renderer
        -> Editor UI
```

`Document Model`, `Text Buffer`, `Selection Model`, `Undo Redo Model`, `Marker Model`, `Decoration Model`, and `Editor DataStore Owner` are coordinated editor mechanisms, not strict parent-child layers. `DataStore API` belongs to Foundation, and `Styio Result Adapter` remains internal to Styio Language Service.

## 11. Toolchain Backend Baseline

Toolchain backend ownership is split:

| Area | Owner |
|---|---|
| `toolchain/` | Vityo toolchain backend profile assets, normalization notes, handoff examples, and local backend surface. |
| `docs/contracts/` | Vityo product adapter contracts. |
| `styio-nightly` | Compiler binary truth, managed toolchain install/use/pin semantics, machine-info, service capability, and capability SSOT. |
| `styio-pafio` | Package/workflow/backend-service truth, hosted control plane, project graph, toolchain state, dependency, and deployment backend services. |

Frontend should consume product contracts and normalized machine payloads, not raw profile files, compiler symlinks, cache layout, or `.pafio` internals on the main runtime path.

`StyioService` is not an OS-level foundation. It is launched from the selected Styio toolchain through Vityo's Toolchain Manager, Process Manager, and Styio Service Connector. OS APIs provide process, file, permission, and network foundations only.

## 11. Retired Plan Documents

The following local plan documents were retired after their completed content was consolidated here and their unfinished content was moved to [Vityo-Implementation-Gaps.md](./Vityo-Implementation-Gaps.md):

| Retired document | Replacement |
|---|---|
| `docs/plan/Vityo-Implementation-Plan.md` | This delivered design baseline plus the gap register. |
| `docs/plan/Vityo-Independent-Work-Breakdown.md` | This delivered design baseline plus the gap register. |
| `docs/plan/StyioService-VityoIDE-Language-Boundary-Plan.md` | Service Layer design docs and the gap register. |
| `docs/plan/Vityo-Runtime-Dependencies.md` | Runtime design docs, vertical-flow architecture views, and this baseline. |
| `docs/plan/Vityo-Runtime-Layer-Stack.md` | Runtime design docs, vertical-flow architecture views, and this baseline. |
| `docs/plan/Vityo-Vertical-Lines.md` | Runtime design docs, vertical-flow architecture views, and this baseline. |
| `docs/plan/Vityo-Toolchain-Backend-Handoff-Plan.md` | Toolchain backend baseline in this document and the gap register. |
| `docs/plan/Styio-Ecosystem-Delivery-Master-Plan.md` | Upstream canonical plan remains outside this repo; this repo keeps only delivered baseline and gaps. |
| `docs/plan/Styio-Ecosystem-File-Governance-Alignment-Plan.md` | Documentation policy and docs/delivery runbook now own repo-local governance boundaries. |

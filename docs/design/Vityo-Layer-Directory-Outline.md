# Vityo Layer Directory Outline

**Purpose:** Define the directory outline for Vityo by horizontal architecture layer, covering current design docs, current implementation anchors, and intended implementation homes. Vertical flows are design views only and must not become implementation roots.

**Last updated:** 2026-05-17

**Status:** Draft for review

## 1. Rule

Directories should make the architecture visible.

The preferred structure is:

```text
docs/design/
  <horizontal-layer>/
    <module>/
      README.md

frontend/vityo_app/lib/src/view_ide/
  <horizontal-layer>/
    <module>/

frontend/vityo_app/lib/src/view_render/
  <appearance-or-render-domain>/
    <module>/
```

Layer rule:

| Layer | Purpose |
|---|---|
| Appearance | Rendering, layout, theme, visual widgets, icons, decorations, and responsive presentation. |
| Interaction | Commands, editor behavior, controller state, input, focus, selection, and workspace edit application. |
| Service | Direct service providers consumed by upper layers, such as Styio Language Service and optional User Service. Connectors/adapters/caches are internal to concrete services. |
| Foundation | Shared mechanics used by upper layers: DataStore API, DataStore Owner contract, registry, workspace scope, resource coordination, lifecycle coordination, lock service, event bus, and infrastructure diagnostics sink. It is not Configuration, Toolchain, Extension, or a broad `FoundationManager`. |
| Environment | Seven-part environment stack: Platform Manager is the top system call surface above Platform Adapter, Platform Context, and Platform Detector; Configuration, Toolchain, and Extension are application-side environment modules. |

Foundation directory gate:

```text
foundation/
  allowed: datastore, registry, workspace, resource routing, lifecycle, locks,
           foundation events, infrastructure diagnostics

foundation/
  forbidden: configuration schemas, credential policy, tool installers,
             tool encoders/decoders, shell runtime, terminal runtime,
             platform-specific OS calls
```

If a module defines what a setting means, place it under `environment/configuration-store`.
If a module defines what a tool/runtime does, place it under `environment/toolchain-manager`.
If a module talks directly to OS capabilities, place it under `environment/system-compatibility-manager`.

## 2. Directory Tree Overview

The directory tree is the primary view. Ordinary submodules are listed in their owning layer README instead of getting placeholder README files.

```text
docs/design/
  Vityo-Product-Spec.md
  Vityo-System-Architecture.md
  Vityo-Delivered-Design-Baseline.md
  Vityo-Implementation-Gaps.md
  Vityo-Layer-Directory-Outline.md

  architecture-views/                 # design-only review views; not runtime roots
    README.md
    vertical-flow-diagrams/
      README.md
      editor/
        README.md

  appearance/
    README.md                         # renderer/theme/editor visual module inventory lives here
    app-shell-surface/
      README.md

  interaction/
    README.md                         # editor behavior/model module inventory lives here

  service/
    README.md
    styio-language-service/
      README.md                       # connector/cache internals are documented here
      styio-result-adapter/           # complex internal design
        README.md
      language-fixture-confidence-matrix/  # complex internal design
        README.md
    user-service/
      README.md

  foundation/
    README.md                         # datastore/registry/workspace/resource/lifecycle/lock/event/diagnostics inventory lives here
    foundation-development-unit/
      README.md
    foundation-layer-contract/
      README.md
    foundation-service-boundary/
      README.md
    data-store-owner/
      README.md

  environment/
    README.md                         # extension/fallback/execution inventory lives here
    configuration-store/
      environment-variable-configuration/
        README.md
      shell-configuration/
        README.md
    system-compatibility-manager/
      README.md
      platform-detector/
        README.md
      platform-context/
        README.md
      file-system-manager/
        README.md
    toolchain-manager/
      styio-toolchain-management/
        README.md
    shell-runtime/
      README.md
```

## 3. Appearance Layer App Shell Surface

App Shell Surface is part of the Appearance Layer, not a separate product-ui layer and not an account/login layer.

User/account/profile behavior is handled by the optional User Service under the Service Layer.

Design docs:

```text
docs/design/appearance/app-shell-surface/
  README.md
  surfaces/
  recovery-surface/
  capability-status-surface/
  onboarding-surface/
  settings-surface/
```

Current implementation anchors:

```text
frontend/vityo_app/lib/src/app/
frontend/vityo_app/lib/src/frontend_shell/
frontend/vityo_app/lib/src/view_ide/commands/
frontend/vityo_app/lib/src/view_ide/workspace/
```

Intended implementation outline:

```text
frontend/vityo_app/lib/src/view_render/app_shell/
  surfaces/
  recovery/
  capability_status/
  onboarding/
  settings_entry/
```

Ownership:

| Module | Owns |
|---|---|
| surfaces | Product-visible entry points. |
| recovery | Recovery choices and guidance after structured failures. |
| capability_status | Display of available, blocked, degraded, or unsupported capabilities. |
| onboarding | Product onboarding that works without login. |
| settings_entry | Entry points to Configuration Store, not settings persistence itself. |

## 4. Appearance Layer

Design docs:

```text
docs/design/appearance/
  README.md
  renderer/
  theme-rendering/
  editor-renderer/
  diagnostics-renderer/
  hover-renderer/
  completion-renderer/
  terminal-renderer/
```

Current implementation anchors:

```text
frontend/vityo_app/lib/src/theme/
frontend/vityo_app/lib/src/view_render/
frontend/vityo_app/lib/src/view_render/editor/
frontend/vityo_app/lib/src/view_render/theme/
frontend/vityo_app/lib/src/view_render/runtime/
frontend/vityo_app/lib/src/view_render/shell/
```

Intended implementation outline:

```text
frontend/vityo_app/lib/src/view_render/appearance/
  renderer/
  theme/
  editor/
  diagnostics/
  hover/
  completion/
  runtime/
  shell/
  icons/
```

Ownership:

| Module | Owns |
|---|---|
| renderer | Visual rendering contracts. |
| theme | Color, typography, icon, semantic color, and renderer binding. |
| editor | Text, gutter, cursor, selection, diagnostics, and widget rendering. |
| diagnostics | Problems, underline, gutter markers, and severity visuals. |
| hover/completion | Visual widgets only; service data comes from Service Layer. |

## 5. Interaction Layer

Design docs:

```text
docs/design/interaction/
  README.md
  command-router/
  editor-controller/
  document-model/
  text-buffer/
  cursor-selection/
  workspace-edit-applier/
  focus-coordinator/
  keybinding-router/
```

Current implementation anchors:

```text
frontend/vityo_app/lib/src/editor/
frontend/vityo_app/lib/src/view_ide/editor/
frontend/vityo_app/lib/src/view_ide/editor/actions/
frontend/vityo_app/lib/src/view_ide/editor/controller/
frontend/vityo_app/lib/src/view_ide/editor/document/
frontend/vityo_app/lib/src/view_ide/editor/selection/
frontend/vityo_app/lib/src/view_ide/editor/transactions/
frontend/vityo_app/lib/src/app/commands/
frontend/vityo_app/lib/src/view_ide/commands/
```

Intended implementation outline:

```text
frontend/vityo_app/lib/src/view_ide/interaction/
  command_router/
  keybinding_router/
  editor_controller/
  document_model/
  text_buffer/
  cursor_selection/
  undo_redo/
  workspace_edit_applier/
  focus_coordinator/
```

Ownership:

| Module | Owns |
|---|---|
| command_router | User command dispatch and product action routing. |
| editor_controller | Editing behavior and coordination of editor foundations. |
| document_model | Document identity, revision, binding state, dirty state, and language id. |
| text_buffer | In-memory current text content for open documents. |
| workspace_edit_applier | Applies edits to open documents and file-backed resources. |

## 6. Service Layer

Design docs:

```text
docs/design/service/
  README.md
  styio-language-service/
    README.md
    styio-result-adapter/
      README.md
    language-fixture-confidence-matrix/
      README.md
  user-service/
    README.md
  service-connector/
  remote-service-adapter/
  service-result-cache/
  service-capability-detector/
  user-service/
    local_profile_service/
    account_session_service/
    profile_sync_adapter/
```

Current implementation anchors:

```text
frontend/vityo_app/lib/src/language/
frontend/vityo_app/lib/src/view_ide/language/
frontend/vityo_app/lib/src/view_ide/language/contract/
frontend/vityo_app/lib/src/view_ide/language/diagnostics/
frontend/vityo_app/lib/src/view_ide/language/features/
frontend/vityo_app/lib/src/view_ide/language/semantic/
frontend/vityo_app/lib/src/view_ide/language/service/
frontend/vityo_app/lib/src/view_ide/language/syntax/
frontend/vityo_app/lib/src/view_ide/language/syntax_validation/
```

Intended implementation outline:

```text
frontend/vityo_app/lib/src/view_ide/service/
  language_service/
    styio_service_connector/
    protocol/
    transport/
    client/
    capability_detector/
    styio_result_adapter/
      dto/
      version_binding/
      stale_rejection/
      result_cache/
    vityo_service_result_consumer/
    diagnostics/
    completion/
    hover/
    semantic_tokens/
    code_action/
    rename/
    fixture_confidence_matrix/
    syntax_validation_fallback/
  remote_service/
    hosted_workspace/
    hosted_execution/
    project_graph/
  toolchain_service/
    capability_handshake/
    managed_install/
```

Ownership:

| Module | Owns |
|---|---|
| styio_service_connector | Talking to StyioService via protocol, transport, client, and capability detection. |
| remote_service_adapter | Adapts hosted workspace, hosted execution, project graph, or future remote-service payloads. |
| service_result_cache | Caches service results using service identity, request identity, version, capability, and freshness metadata. |
| styio_result_adapter | Normalize StyioService results and bind them to document versions. |
| vityo_service_result_consumer | Vityo-facing intake for language-service results and future service-specific results. |
| fixture_confidence_matrix | `.true.styio` / `.false.styio` expectation and actual-result classification. |
| syntax_validation_fallback | Degraded syntax checks only; not Styio truth. |

## 7. Foundation Layer

Design docs:

```text
docs/design/foundation/
  README.md
  foundation-development-unit/
    README.md
  foundation-layer-contract/
    README.md
  foundation-service-boundary/
    README.md
  data-store-owner/
    README.md
```

Current implementation anchors:

```text
frontend/vityo_app/lib/src/view_ide/foundation/
frontend/vityo_app/lib/src/view_ide/foundation/datastore/
frontend/vityo_app/lib/src/view_ide/foundation/registry/
frontend/vityo_app/lib/src/view_ide/foundation/workspace/
frontend/vityo_app/lib/src/view_ide/foundation/resource_coordinator/
frontend/vityo_app/lib/src/view_ide/foundation/lifecycle_coordinator/
frontend/vityo_app/lib/src/view_ide/foundation/lock_service/
frontend/vityo_app/lib/src/view_ide/foundation/event_bus/
frontend/vityo_app/lib/src/view_ide/foundation/diagnostics_sink/
```

Intended implementation outline:

```text
frontend/vityo_app/lib/src/view_ide/foundation/
  datastore/
    datastore.dart
    schema.dart
    migration_runner.dart
  registry/
    registry.dart
    manifest_index.dart
  workspace/
    workspace.dart
    workspace_scope.dart
    service_container.dart
  resource_coordinator/
    resource_coordinator.dart
    resource_location.dart
    budget_hint.dart
  lifecycle_coordinator/
    lifecycle_coordinator.dart
  lock_service/
    lock_service.dart
  event_bus/
    event_bus.dart
  diagnostics_sink/
    diagnostics_sink.dart
```

Ownership:

| Module | Owns |
|---|---|
| datastore | Shared persistence mechanics, schema states, migrations, and atomic record writes through File System Manager. |
| data-store-owner | Contract for layer-local state ownership, mutation authority, persistence policy, and subscription policy. |
| registry | Generic register/unregister/lookup/list mechanics and manifest index mechanics. |
| workspace | Workspace identity, root, scope, lifecycle, and scoped foundation service container. |
| resource_coordinator | Namespace-to-location routing and resource budget handoff to Environment Resource Manager. |
| lifecycle_coordinator | Shared startup, reload, shutdown, and disposal sequencing for foundation services. |
| lock_service | Shared mutual-exclusion and transaction lock mechanics. |
| event_bus | In-process foundation state notifications only. |
| diagnostics_sink | Foundation infrastructure health and status events. |

Boundary:

```text
Foundation owns shared mechanics.
Configuration owns settings.
Toolchain owns tools and runtimes.
Environment owns OS/platform capabilities.
```

Non-overlap rule:

```text
Foundation may provide shared DataStore, Registry, Workspace, Resource
Coordinator, Lifecycle, Lock, Event, and Diagnostics mechanics.

Foundation must not provide Configuration schemas, credential policy,
Toolchain selection, Toolchain codecs, Shell Runtime, Terminal Runtime,
File System Manager, Process Manager, or Resource Manager behavior.
```

## 8. Environment Layer

Design docs:

```text
docs/design/environment/
  configuration-store/
    environment-variable-configuration/
      README.md
  system-compatibility-manager/
    platform-context/
      README.md
    file-system-manager/
      README.md
  toolchain-manager/
    styio-toolchain-management/
      README.md
  extension-manager/
  fallback-registry/
  execution-manager/
```

Current implementation anchors:

```text
frontend/vityo_app/lib/src/backend_toolchain/
frontend/vityo_app/lib/src/platform/
frontend/vityo_app/lib/src/view_ide/backend_toolchain/
frontend/vityo_app/lib/src/view_ide/platform/
frontend/vityo_app/lib/src/view_ide/shell_runtime/
frontend/vityo_app/lib/src/runtime/
frontend/vityo_app/lib/src/module_host/
frontend/vityo_app/lib/src/view_ide/module_host/
toolchain/
```

Intended implementation outline:

```text
frontend/vityo_app/lib/src/view_ide/environment/
  toolchain_manager/
    styio_toolchain_management/
    discovery/
    installer/
    capability_handshake/
    environment_builder/
    encoder_decoder/
  system_compatibility_manager/
    platform_detector/
    platform_context/
    platform_adapter/
    file_system_manager/
    process_api_manager/
    shell_manager/
    network_manager/
    pty_manager/
    resource_manager/
  configuration_store/
    settings_schema/
    workspace_preferences/
    profile_configuration/
    environment_variable_configuration/
    cache_policy/
    endpoint_policy/
  extension_manager/
    manifest_loader/
    lifecycle_manager/
    provider_registry/
    capability_registry/
    permission_model/
  fallback_registry/
    family_registry/
    policy_registry/
    reason_catalog/
  execution_manager/
    command_runner/
    process_manager/
    artifact_manager/
```

Ownership:

| Module | Owns |
|---|---|
| toolchain_manager | Styio/Pafio discovery, selected toolchain, managed install, process launch context, and capability handshake. |
| system_compatibility_manager | Platform context, system-specific managers, manager-local permission handling, structured failures, and platform capability. |
| configuration_store | User/workspace/profile settings, env overlays, cache policy, endpoint policy, and migrations. |
| extension_manager | Plugin manifests, lifecycle, provider contribution, capability contribution, and extension permissions. |
| fallback_registry | Global fallback registration only; feature-local fallback behavior stays in feature owners. |
| execution_manager | Command execution semantics, process lifecycle coordination, artifacts, and task status. |

## 9. Layer-Owned Contracts

Contracts are not a top-level runtime layer and must not become a shared feature hub.

Rule:

```text
A contract lives with the horizontal layer that owns its truth.
Other layers may consume the contract, but implementation files stay in their owning layer.
```

Design docs:

```text
docs/design/foundation/data-store-owner/
  README.md
```

Implementation placement:

| Contract type | Owning horizontal home | Rule |
|---|---|---|
| DataStore Owner | `view_ide/foundation/datastore` plus layer-local owners | Foundation DataStore API may persist through File System Manager; feature owners define state ownership and mutation rules. |
| Registry Contract | Each horizontal layer's `registry/` module | Registry records manifests and discoverable boundaries; it must not centralize feature behavior. |
| Cache Contract | The layer that owns the cached fact | Cache key, invalidation, freshness, and dependency tracking stay next to the producer/consumer boundary. |
| Policy Contract | The feature or environment module that enforces it | Policy definitions may be shared, but enforcement remains local to the responsible module. |

## 10. Vertical Flow Views (Design Only)

Vertical flows are review diagrams, not implementation directories.

Design docs:

```text
docs/design/architecture-views/vertical-flow-diagrams/
  README.md
  editor/
    README.md
```

Implementation placement for the Editor flow:

| Flow concern | Horizontal implementation home |
|---|---|
| Editor surface and recovery UI | `view_render/app_shell` or `view_render/editor` |
| Editor renderer, decorations, hover popup, completion popup | `view_render/editor` |
| Text buffer, document model, selection, undo/redo, edit transactions, marker model, decoration model, and commands | `view_ide/interaction/editor` |
| Styio diagnostics, completion, hover, semantic tokens, references | `view_ide/service/styio_language_service` |
| User profile/account/sync entry state | `view_ide/service/user_service` |
| Document resource binding | `view_ide/interaction/document_resource_binding` |
| DataStore API, registry, workspace scope, resource coordinator | `view_ide/foundation/*` |
| Configuration, file-system manager, toolchain, platform context | `view_ide/environment/*` |

Rule:

```text
Do not create view_ide/vertical_lines/ or a vertical-lines runtime module.
A vertical flow may be drawn for review, but its concrete modules must be placed in horizontal layers.
```

## 11. Current Legacy / Compatibility Paths

Some current paths are legacy anchors or compatibility exports. They should not keep growing as new architecture roots.

```text
frontend/vityo_app/lib/src/editor/              # existing editor anchor; migrate into horizontal interaction/service/appearance/environment modules over time
frontend/vityo_app/lib/src/language/            # existing language anchor; migrate into view_ide/service/styio_language_service over time
frontend/vityo_app/lib/src/backend_toolchain/   # existing backend/toolchain anchor; can remain as product adapter facade
frontend/vityo_app/lib/src/integration/         # compatibility exports only
```

Rule:

```text
New code should prefer view_ide/<layer> or view_render/<appearance-domain>.
Compatibility exports may remain, but should not become new implementation roots.
```

## 12. Naming Conventions

| Design directory | Implementation directory | Notes |
|---|---|---|
| `app-shell-surface` | `view_render/app_shell` | Visible shell surfaces and recovery; not login/account ownership. |
| `appearance` | `view_render/appearance` or `view_render/<domain>` | Rendering and visual mapping. |
| `interaction` | `view_ide/interaction` | Controllers, commands, editor state behavior. |
| `service` | `view_ide/service` | Root contains only direct service providers; connectors, adapters, caches, and fixtures are internal to concrete services. |
| `foundation` | `view_ide/foundation` | Shared mechanics only: DataStore, registry, workspace, resource coordination. |
| `environment` | `view_ide/environment` | Platform Detector/Facts/Adapter/Manager plus Configuration, Toolchain, Extension, and Shell Runtime. |

## 13. First Directory Gaps

| Missing design directory | Why it is needed |
|---|---|
| `docs/design/<horizontal-layer>/registry/` | Registry rules must be documented inside each owning horizontal layer instead of a cross-layer directory. |

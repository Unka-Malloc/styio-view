# Foundation

**Purpose:** Document the `docs/design/foundation/` collection scope, ownership, and maintenance rules.
**Last updated:** 2026-05-17

`Foundation` is the shared application foundation for upper Vityo services. It provides common coordination mechanics that are required by Configuration, Toolchain, Extension, Service, Interaction, and Appearance modules.

It must not become a catch-all layer. Foundation owns shared mechanics only.

```text
Foundation owns shared mechanics.
Configuration owns settings.
Toolchain owns tools.
Environment owns OS capabilities.
```

## Scope Decision

The layer name is `Foundation`.

Use it for shared application mechanics that multiple upper layers need before they can build real product behavior.

Do not use `Foundation` as a softer name for Environment, Configuration, Toolchain, Extension, or Service.

Primary design documents:

| Document | Purpose |
|---|---|
| [Foundation Development Unit](./foundation-development-unit/README.md) | Defines Foundation as the independent shared-mechanics development unit and records the non-overlap contract with Configuration, Toolchain, and Environment. |
| [Foundation Layer Contract](./foundation-layer-contract/README.md) | Defines the layer boundary, allowed Foundation services, rejection rules, and dependency direction. |
| [Foundation Service Boundary](./foundation-service-boundary/README.md) | Explains the service-level boundary between Foundation, upper layers, and the platform stack. |
| [DataStore Owner](./data-store-owner/README.md) | Defines how upper layers own state while using Foundation DataStore mechanics. |

Foundation is not a product feature layer and not an environment layer. It is the horizontal base that makes upper layers able to store state, register capabilities, scope workspaces, coordinate shared resources, and sequence lifecycle work without each layer inventing its own incompatible mechanism.

The design decision is:

```text
Foundation = shared application mechanics.
Configuration = IDE settings and policy values.
Toolchain = external tools and runtime composition.
Environment = OS/platform compatibility and system calls.
Service = domain services exposed to interaction and appearance.
```

The settled service boundary is:

```text
Foundation contains:
  datastore
  data-store-owner contract
  registry
  workspace
  resource-coordinator
  lifecycle-coordinator
  lock-service
  event-bus
  diagnostics-sink

Foundation does not contain:
  configuration-store
  credential policy
  toolchain-manager
  encoder-decoder
  shell-runtime
  terminal-runtime
  file-system-manager
  process-manager
  resource-manager
```

This keeps `Foundation` from overlapping the application-side environment
modules. `Configuration` and `Toolchain` may call Foundation services, but their
policies, schemas, selected tools, codecs, and runtime behavior remain outside
Foundation.

The settled vertical position is:

```text
Upper product/service layers
  -> Foundation
    -> Platform Manager
      -> Platform Adapter
        -> Platform Context
          -> Platform Detector
            -> OS / host APIs
```

Foundation is therefore an application base, not a system-compatibility layer.
It may call Platform Manager surfaces when shared mechanics need file-system,
resource, or runtime-compatible primitives. It must not call Platform Detector,
Platform Context, Platform Adapter, concrete probers, or OS APIs directly.

The strongest boundary is against `Configuration` and `Toolchain`.

```text
Foundation may persist and coordinate.
Foundation must not decide configuration meaning.
Foundation must not decide tool behavior.
```

This is a hard architecture rule, not a naming preference.

```text
Configuration owns what values mean.
Toolchain owns what tools do.
Foundation only owns the shared mechanics they use.
```

## Configuration / Toolchain Non-Overlap Gate

Every proposed Foundation module must pass this gate before being accepted.

```text
Question 1: Does the module define a setting, default, profile, environment
overlay, credential rule, or user-visible policy?

If yes:
  It belongs to Configuration.

Question 2: Does the module discover, install, select, execute, encode, decode,
or health-check an external tool/runtime?

If yes:
  It belongs to Toolchain.

Question 3: Does the module only store, register, scope, lock, route, notify, or
sequence state on behalf of an owning layer?

If yes:
  It may belong to Foundation.
```

The anti-pattern is:

```text
Foundation / DataStore
  -> understands settings
  -> understands credentials
  -> understands tool versions
  -> understands shell/runtime behavior
```

The intended pattern is:

```text
Configuration Owner
  -> Foundation / DataStore
  -> Foundation / Registry

Toolchain Owner
  -> Foundation / DataStore
  -> Foundation / Registry
  -> Environment / Platform Manager
```

This means Foundation can support Configuration and Toolchain, but it cannot
become either layer by accumulating their state semantics.

| Candidate concern | Foundation decision |
|---|---|
| DataStore API | Yes. It is shared persistence mechanics. |
| DataStore Owner contract | Yes. It defines how each layer owns state while using DataStore. |
| Registration / Registry mechanics | Yes. It is shared registration and lookup mechanics. `Registration` is the capability; `registry` is the implementation module. |
| Workspace identity and scope | Yes. It is shared scope mechanics. |
| System resources | No as a direct owner. Use `Resource Coordinator` to route requests to Environment Resource Manager. |
| Lifecycle coordination | Yes. It is shared initialize/dispose sequencing for foundation-owned services. |
| Lock coordination | Yes. It is shared write/update serialization mechanics. |
| In-process event routing | Yes, only for foundation-level state notifications. |
| Infrastructure diagnostics sink | Yes, only for foundation health/status events. |
| Configuration values | No. Configuration owns values, defaults, migrations, and schemas. |
| Toolchain behavior | No. Toolchain owns tools, runtimes, selection, download, and execution composition. |
| Extension behavior | No. Extension owns activation, contributions, and extension lifecycle semantics. |
| Language truth | No. StyioService owns language syntax and semantics. |

## Settled Foundation Service Shape

The first Foundation cut is intentionally small:

```text
foundation/
  datastore/
  data-store-owner/
  registry/
  workspace/
  resource-coordinator/
  lifecycle-coordinator/
  lock-service/
  event-bus/
  diagnostics-sink/
```

These modules are admitted because they are shared, meaning-free, product-neutral,
tool-neutral, and OS-neutral mechanics.

| Service | Why it is Foundation | Why it is not Configuration or Toolchain |
|---|---|---|
| `datastore` | It persists records, applies migrations, serializes updates, and publishes scoped changes. | It does not define setting keys, defaults, tool records, or runtime behavior. |
| `data-store-owner` | It forces every state family to have a layer-local mutation owner. | The owner lives with the layer that owns meaning. |
| `registry` | It registers, looks up, lists, and projects manifests without exposing runtime values. | It does not activate extensions, validate settings, select tools, or execute providers. |
| `workspace` | It provides workspace identity, scope, root, lifecycle, and scoped foundation services. | It does not own editor documents, project semantics, or tool execution policy. |
| `resource-coordinator` | It routes storage/cache/runtime namespaces to Environment-managed resource locations. | It does not probe resources, create directories, enforce quotas, or choose cache policy. |
| `lifecycle-coordinator` | It sequences startup, reload, shutdown, and disposal for Foundation services. | It does not own product onboarding, extension activation, or tool runtime launch. |
| `lock-service` | It serializes shared foundation updates. | It does not approve user actions, decide permissions, or enforce security policy. |
| `event-bus` | It publishes Foundation-local state changes. | It is not the UI command bus, extension event bus, or language protocol transport. |
| `diagnostics-sink` | It records Foundation infrastructure health. | It is not Styio diagnostics, problem-panel rendering, or telemetry product UI. |

The rejection rule for new Foundation modules is:

```text
If a module understands a setting, a tool, an extension contribution,
a language fact, an editor command, a visual surface, or an OS API,
it does not belong in Foundation.
```

## Scope Fence Against Configuration and Toolchain

Foundation is intentionally below `Configuration` and `Toolchain`, but it is not allowed to absorb either layer.

| Concern | Foundation may own | Must stay outside Foundation |
|---|---|---|
| Settings persistence | Record IO, schema-state storage mechanics, atomic writes, locks. | Setting keys, defaults, value semantics, validation rules, migration policy, UI grouping. |
| Environment variables | Generic record storage when requested by a DataStore Owner. | Environment-variable overlay meaning, merge policy, shell injection policy. |
| Credentials | Generic storage mechanics only when called by the credential owner. | Secret classification, encryption policy, credential lookup semantics, token lifecycle. |
| Toolchain records | Persisting records and routing cache/state paths. | Tool discovery, install, version selection, executable resolution, protocol semantics. |
| Encoders / decoders | No. | Toolchain-owned encoding and decoding contracts exposed upward. |
| Shell / terminal runtime | No. | Runtime composition, shell launch model, terminal lifecycle, process execution. |
| Extension manifests | Generic registry mechanics. | Activation rules, contribution points, extension permissions, extension host lifecycle. |

The practical test:

```text
If the module can answer "what does this setting/tool/service mean?",
it is not Foundation.

If the module can only answer "where is this record stored, registered,
locked, scoped, or coordinated?",
it can be Foundation.
```

## Foundation Non-Overlap Contract

Foundation is a substrate for upper layers, not a substitute for upper-layer
ownership.

```text
Foundation service
  -> owns reusable mechanics
  -> does not own domain interpretation

Upper-layer owner
  -> owns the meaning of records, providers, policies, tools, and UI behavior
  -> may call Foundation for storage, registration, locking, scope, lifecycle,
     and resource routing
```

This contract prevents `Foundation` from growing into a hidden
`Configuration`, `Toolchain`, or `Environment` layer.

| If code starts to own... | Correct owner |
|---|---|
| setting keys, defaults, validation, user preferences, environment overlay semantics | Configuration |
| credential classification, credential storage policy, secret lifecycle | Configuration / Credential DataStore |
| Styio compiler discovery, installation, selected version, executable resolution | Toolchain |
| encoder/decoder protocol contracts for external tools | Toolchain |
| shell runtime, terminal runtime, task/runtime composition | Toolchain |
| OS facts, probing, file/process/network/shell/PTY APIs | Environment / System Compatibility |
| language syntax, semantic facts, diagnostics, completion, hover, reference truth | Service / StyioService |
| editor commands, document mutation, workspace edit application | Interaction |
| visual rendering, theme mapping, panels, widgets | Appearance |

The dependency must point downward only:

```text
Correct:
  Configuration Store -> Foundation DataStore
  Toolchain Manager -> Foundation Registry
  Editor Controller -> Foundation Workspace

Wrong:
  Foundation DataStore -> Configuration Store
  Foundation Registry -> Toolchain Manager
  Foundation Workspace -> Editor Controller
```

## Anti-Overlap Rule

Foundation must stay below `Configuration` and `Toolchain`.

It may provide persistence, locking, registration, workspace scope, resource routing, lifecycle sequencing, and infrastructure-status primitives to both layers.

It must not contain configuration schemas, defaults, environment overlay rules, credential policy, tool discovery, tool installation, tool version resolution, encoder/decoder contracts, shell runtime, terminal runtime, process composition, or external protocol meaning.

| If the design says... | It belongs to |
|---|---|
| "This setting key means..." | Configuration |
| "This environment variable should override..." | Configuration |
| "This credential is secret and should be stored..." | Configuration / Credential DataStore |
| "This Styio version should be selected..." | Toolchain |
| "This executable should be downloaded or installed..." | Toolchain |
| "This payload should be encoded or decoded..." | Toolchain |
| "This shell/runtime/process should be composed..." | Toolchain |
| "This record should be stored atomically..." | Foundation / DataStore |
| "This provider should be registered and discovered..." | Foundation / Registry |
| "This workspace-scoped resource needs a location..." | Foundation / Resource Coordinator |

## Implementation Contract

Foundation is developed as reusable application mechanics, not as a runtime umbrella.

Its public surface is intentionally small:

```text
Foundation public API
  -> DataStore API
  -> DataStore Owner contract
  -> Registration / Registry API
  -> Workspace Scope API
  -> Resource Coordinator API
  -> Lifecycle / Lock / Event / Diagnostics primitives
```

Every upper layer must enter Foundation through a layer-owned boundary.

```text
Upper-layer feature
  -> Upper-layer owner / registrar
    -> Foundation service
      -> Environment platform manager when OS access is required
```

The upper-layer owner is mandatory because Foundation does not know domain meaning.

| Upper layer | Foundation entry point | Meaning that stays outside Foundation |
|---|---|---|
| Configuration | Configuration DataStore Owner, configuration provider registration. | Setting keys, defaults, schemas, environment-variable overlays, credential policy. |
| Toolchain | Toolchain DataStore Owner, toolchain provider registration, cache namespace routing. | Tool discovery, download, install, version selection, encoder/decoder, shell runtime, terminal runtime. |
| Extension | Extension DataStore Owner, manifest registry entry. | Activation, contribution points, extension host lifecycle, extension permission model. |
| Service | Service DataStore Owner, service provider registration, service result storage. | Styio syntax/semantic truth, remote-service protocol meaning, diagnostics, completion, hover, semantic tokens. |
| Interaction | Interaction DataStore Owner, workspace scope, locks, event subscriptions. | Editor document model, text buffer mutation, commands, selection, workspace edit application. |
| Appearance | Appearance DataStore Owner, visual state subscriptions. | Rendering, theme mapping, panels, widgets, editor surface. |

Explicit exclusions:

| Excluded from Foundation | Correct owner |
|---|---|
| Credential DataStore and secret policy | Configuration |
| Environment-variable overlay semantics | Configuration |
| Tool encoders and decoders | Toolchain |
| Shell Runtime and Terminal Runtime | Toolchain |
| File System Manager, Process Manager, Shell Manager, PTY Manager | Environment / System Compatibility |
| Resource Manager and system resource probing | Environment / System Compatibility |
| Editor document model and editor file binding | Interaction |
| Theme rendering and visual theme mapping | Appearance |

## Foundation Service Model

Foundation is a service set, not a single `FoundationManager`.

The layer should expose a small group of reusable mechanics that upper layers compose through their own owners, registrars, or controllers:

```text
Configuration / Toolchain / Extension / Service / Interaction / Appearance
  -> layer-local Owner / Registrar / Controller
    -> Foundation service
      -> Environment / Platform Manager surface when system access is needed
```

The first stable Foundation service set is:

| Service | Primary role | Upper-layer contract |
|---|---|---|
| `datastore` | Schema-state record persistence, atomic writes, migration execution, transactional JSON updates, explicit write/delete/keep edit decisions, scoped change subscriptions, and record serialization. | Upper layers define state meaning through DataStore Owners. |
| `data-store-owner` | Mutation authority contract for one state family. | Owners live with the layer that owns the state. |
| `registry` | Register, unregister, lookup, list, lifecycle state, and manifest projection mechanics. | Domain layers interpret registered values. |
| `workspace` | Workspace identity, root, scope, lifecycle, and scoped service container. | Editor, service, toolchain, and configuration behavior remain above it. |
| `resource-coordinator` | Namespace-to-location routing and resource-budget handoff. | Environment Resource Manager owns real system resource facts and operations. |
| `lifecycle-coordinator` | Startup, reload, shutdown, and disposal sequencing for Foundation services. | Product onboarding and extension activation stay outside it. |
| `lock-service` | Shared mutual exclusion for Foundation updates. | It does not perform permission, security, or user-approval checks. |
| `event-bus` | Foundation-local state notifications. | It does not become the UI command router or extension event bus. |
| `diagnostics-sink` | Infrastructure health/status events from Foundation services. | Language diagnostics and problem rendering stay in Service/Appearance. |

This service set is intentionally smaller than the list of reusable concepts in the IDE. A concept is allowed into Foundation only when it is cross-layer, meaning-free, product-neutral, tool-neutral, and OS-neutral.

## Boundary Against Configuration And Toolchain

`Configuration` and `Toolchain` are above Foundation because they own domain policy.

Foundation may provide the mechanics they use, but it must not absorb their decisions:

| Concern | Foundation can provide | Must remain outside Foundation |
|---|---|---|
| Configuration records | DataStore IO, owner boundary, locks, schema-state mechanics. | Setting keys, defaults, validation, environment-variable overlay semantics, credential policy. |
| Toolchain records | DataStore IO, registry metadata, workspace scope, resource namespace routing. | Tool discovery, installation, version selection, executable resolution, payload codecs, Shell Runtime, Terminal Runtime. |
| Shared manifests | Registry storage and manifest projection. | Extension activation, tool execution, configuration validation, service protocol interpretation. |
| Shared resources | Resource Coordinator request routing. | OS facts, directory creation, cleanup, quota enforcement, cache eviction policy. |

The rule for implementation review is:

```text
If the code names a setting key, a credential policy, a Styio version,
an executable path resolution rule, an encoder/decoder format, or a shell
runtime policy, it is not Foundation.
```

## 1. Position

```text
Service / Interaction / Appearance
Toolchain / Extension / Configuration
  -> Foundation
    -> Environment / Platform Managers
```

`Foundation` sits above OS compatibility and below product/service modules.

It consumes Environment capabilities through Platform Manager surfaces such as `FileSystem Manager` and `Resource Manager`, but it does not directly own OS probing, OS API adaptation, `Platform Detector`, `Platform Context`, or `Platform Adapter`.

## 2. Hard Boundary Rule

```text
If a module owns user intent, external tool behavior, or OS compatibility, it does not belong to Foundation.
```

| Concern | Owner |
|---|---|
| Shared storage mechanics | Foundation |
| Shared registry mechanics | Foundation |
| Workspace identity and scope mechanics | Foundation |
| Resource location coordination | Foundation |
| User settings values | Configuration |
| Shell Configuration | Configuration |
| Credential DataStore | Configuration |
| Styio compiler selection | Toolchain |
| Terminal Runtime / Shell Runtime | Toolchain |
| FileSystem / Process / Shell / PTY managers | Environment |
| Extension activation semantics | Extension |
| Editor document model and UI binding | Interaction / Appearance |

Detailed boundary design: [foundation-service-boundary/README.md](./foundation-service-boundary/README.md)

Layer contract design: [foundation-layer-contract/README.md](./foundation-layer-contract/README.md)

## 3. First-Level Modules

Recommended initial directory:

```text
foundation/
  datastore/
  data-store-owner/
  registry/
  workspace/
  resource-coordinator/
  lifecycle-coordinator/
  lock-service/
  event-bus/
  diagnostics-sink/
```

Optional later modules:

```text
foundation/
  cache-coordinator/
  transaction-service/
  manifest-index/
```

Only add optional modules when at least two upper layers need the same meaning-free mechanism.

Do not add broad names such as `cache`, `state-store`, `task-runner`, `manifest`, or `policy` unless the proposal proves the module is not absorbing Configuration, Toolchain, Extension, Service, Interaction, or Appearance behavior.

Module summary:

| Module | Owns | Must not own |
|---|---|---|
| `datastore` | Storage mechanics, schema-state tracking, migration runner, atomic record writes. | Settings meaning, secrets, toolchain behavior. |
| `data-store-owner` | Layer-local state ownership rules above DataStore. | A global state model or feature behavior. |
| `registry` | Shared registration, lookup, lifecycle state, manifest index mechanics. | Extension activation, toolchain commands, service truth, provider protocol meaning. |
| `workspace` | Workspace identity, scope, root, lifecycle, and scoped service container. | Editor document model or project language semantics. |
| `resource-coordinator` | Namespace-to-location routing and resource budget handoff. | OS probing, file operations, cleanup execution. |
| `lifecycle-coordinator` | Shared startup, shutdown, reload, and disposal sequencing for Foundation services. | Product onboarding, extension activation, process execution. |
| `lock-service` | Shared mutual-exclusion and transaction lock mechanics for DataStore and registry updates. | Permission checks, security policy, user workflow approval. |
| `event-bus` | In-process foundation state notifications and subscription mechanics. | UI command routing, extension events, language server protocol messages. |
| `diagnostics-sink` | Foundation infrastructure health/status events. | Language diagnostics, user-facing problem rendering, telemetry UI. |

## 3.1 Foundation Boundary Against Upper Layers

Foundation exists because DataStore, Registration, Workspace, and shared resource routing are required by nearly every upper layer. That does not mean Foundation owns the upper-layer meaning of those records.

| Upper module | May use Foundation for | Must still own itself |
|---|---|---|
| Configuration | Persisting settings records, registering setting providers, workspace/user scoping, migration locks. | Setting names, defaults, schemas, environment-variable overlays, credential references, user/workspace policy. |
| Toolchain | Persisting selected toolchain metadata, registering discovered tools, workspace scoping, cache location routing. | Tool discovery, download, version selection, encoder/decoder, shell runtime, process composition. |
| Extension | Registering extension manifests and state, persisting extension-local state, workspace scoping. | Activation rules, contribution semantics, extension permissions, extension host behavior. |
| Service | Persisting service snapshots, registering service providers, workspace/document scoping. | Language truth, remote-service protocol, semantic facts, completion/hover/diagnostic content. |
| Interaction | Persisting editor/session state through its DataStore Owner, workspace scoping, update locks. | Editor behavior, document model, text buffer, commands, focus, selection, workspace edit application. |
| Appearance | Persisting layout/theme state through its DataStore Owner, rendering state subscriptions. | Rendering, visual theme mapping, widgets, panels, editor surface. |

The practical rule:

```text
Foundation provides the mechanism.
The owning layer provides the meaning.
```

If a module needs a setting, tool, extension contribution, language fact, editor behavior, or visual presentation, that module belongs above Foundation even when it stores data through Foundation.

Detailed service acceptance rules are recorded in [foundation-service-boundary/README.md](./foundation-service-boundary/README.md).

## 3.2 Foundation Module Admission Rule

Before a new module is added under `foundation/`, classify it by the operation it performs.

| Operation | Foundation? | Correct owner if not Foundation |
|---|---|---|
| Store a typed record supplied by an owner. | Yes. | N/A |
| Register a provider descriptor without executing it. | Yes. | N/A |
| Scope services to a workspace root. | Yes. | N/A |
| Route a storage namespace to an app/cache/state/temp location. | Yes. | N/A |
| Define a user setting key or default value. | No. | Configuration |
| Decide how environment variables are merged. | No. | Configuration |
| Select or install a Styio compiler. | No. | Toolchain |
| Provide encoder/decoder contracts for tool output. | No. | Toolchain |
| Launch shell, terminal, process, or PTY runtime. | No. | Toolchain or Environment, depending on direct OS interaction. |
| Parse Styio, resolve symbols, or produce language facts. | No. | Service / Styio Language Service |
| Apply editor commands or render UI. | No. | Interaction / Appearance |

This keeps Foundation small enough to be reused by all upper layers without becoming the hidden owner of their policies.

## 3.3 Foundation Dependency Direction

Foundation may call only downward platform primitives and sideways Foundation primitives.

```text
Upper Layers
  -> Foundation
    -> Environment / Platform Manager
      -> Platform Adapter
        -> Platform Context
          -> Platform Detector
```

Foundation must not call upward into Configuration, Toolchain, Extension, Service, Interaction, or Appearance.

Allowed examples:

| Foundation module | Allowed downward dependency |
|---|---|
| DataStore | File System Manager for record IO and atomic writes. |
| Resource Coordinator | Resource Manager for app/cache/state/temp/runtime roots. |
| Lock Service | File System Manager only when a persisted lock is required. |
| Diagnostics Sink | DataStore only if infrastructure diagnostics need persistence. |

Disallowed examples:

| Disallowed dependency | Reason |
|---|---|
| DataStore -> Configuration Store | Would make persistence depend on one consumer's settings model. |
| Registry -> Extension activation | Would turn a generic registry into extension runtime semantics. |
| Resource Coordinator -> Toolchain download | Would make resource routing own tool behavior. |
| Event Bus -> UI command router | Would couple foundation state notifications to interaction behavior. |

## 4. DataStore

`foundation/datastore` owns ordinary data storage mechanics.

It may provide:

| Capability | Meaning |
|---|---|
| Namespace | Data ownership boundary. |
| Schema state | Data shape state. |
| Codec | JSON/binary encoding and decoding. |
| Migration runner | Upgrade data across schema states. |
| Atomic record write | Safe write mechanics through FileSystem Manager. |
| Lock integration | Prevent conflicting writes. |

It must not provide:

| Not Allowed | Correct Owner |
|---|---|
| Shell configuration values | Configuration |
| Styio compiler configuration | Toolchain / Configuration |
| Theme settings | Configuration / Appearance |
| User profile settings | Configuration |
| Tokens / passwords / private keys | Configuration / Credential DataStore |

Dependency direction:

```text
Foundation / DataStore
  -> Foundation / Resource Coordinator
  -> Environment / FileSystem Manager
  -> Environment / Platform Context
```

Secret rule:

```text
DataStore stores CredentialReference only.
Credential DataStore stores secret values.
```

## 5. DataStore Owner

`foundation/data-store-owner` documents the ownership contract for stateful layers that use DataStore.

The contract exists because DataStore only persists records. It does not decide what state exists, who may mutate it, when it is loaded, or whether it is synced.

Correct dependency:

```text
Layer Feature
  -> Layer DataStore Owner
    -> Foundation / DataStore API
      -> Environment / FileSystem Manager
```

Detailed design: [data-store-owner/README.md](./data-store-owner/README.md)

## 6. Registry

`foundation/registry` owns shared registration mechanics.

It may provide:

| Capability | Meaning |
|---|---|
| register | Add an item into a named registry. |
| unregister | Remove an item. |
| lookup | Find registered items. |
| manifest index | Store parsed manifest references and metadata. |
| lifecycle state | Track registered / active / disabled state. |

It must not provide:

| Not Allowed | Correct Owner |
|---|---|
| Extension activation rules | Extension |
| Toolchain command semantics | Toolchain |
| Configuration defaults | Configuration |
| Language provider semantics | Service / language service connector |

Registry is a mechanism. The domain that registers something owns the meaning of that thing.

## 7. Workspace

`foundation/workspace` owns workspace identity, scope, and lifecycle mechanics.

It may provide:

| Capability | Meaning |
|---|---|
| Workspace identity | Stable workspace id. |
| Workspace root | Root path or remote workspace target. |
| Workspace scope | User/workspace/session scoping. |
| Workspace lifecycle | open, close, reload, dispose. |
| Workspace service container | Scoped foundation service references. |

It must not provide:

| Not Allowed | Correct Owner |
|---|---|
| Editor document model | Interaction |
| Editor file binding behavior | Interaction |
| File rendering | Appearance |
| Project language semantics | Service / StyioService |
| Workspace setting values | Configuration |

Workspace is the shared scope boundary. It is not the editor and it is not the language service.

## 8. Resource Coordinator

`foundation/resource-coordinator` coordinates resource locations for upper modules. It consumes `Environment / Resource Manager`, but it does not probe resources and does not perform file operations.

The module should not be named `System Resources`, because system resource facts and OS-specific resource behavior belong to Environment. Foundation only coordinates upper-layer resource locations and budget hints.

It may provide:

| Capability | Meaning |
|---|---|
| Namespace-to-location mapping | Assign datastore/cache/log/index namespaces to resource locations. |
| Location request | Ask Resource Manager for app/cache/state/temp/runtime roots. |
| Budget routing | Pass Resource Manager budget hints to cache/datastore/log owners. |
| Cleanup candidate declaration | Mark resource locations that may be cleaned by the owning subsystem. |

It must not provide:

| Not Allowed | Correct Owner |
|---|---|
| CPU/memory/storage probing | Environment / Resource Prober |
| Actual directory creation | Environment / FileSystem Manager |
| File deletion | Environment / FileSystem Manager plus owning subsystem |
| Cleanup execution | Cache/DataStore/log owner using FileSystem Manager |
| Storage policy UI | Configuration / Interaction / Appearance |

Correct flow:

```text
DataStore
  -> Resource Coordinator
    -> Resource Manager
  -> FileSystem Manager
```

Incorrect flow:

```text
Resource Coordinator
  -> write files directly
```

## 9. Relationship With Configuration

Configuration owns user, workspace, runtime, and product setting values.

Foundation can store configuration records mechanically through DataStore, but it must not decide what settings mean.

Examples:

| Item | Owner |
|---|---|
| DataStore codec for a settings file | Foundation |
| Setting value `shell.defaultProfileId` | Configuration |
| CredentialReference field in settings | Configuration |
| Secret token value | Configuration / Credential DataStore |
| Settings UI | Interaction / Appearance |

## 10. Relationship With Toolchain

Toolchain owns external tools and runtime composition.

Foundation may provide task mechanics, locks, datastore, registry, and workspace scope. It must not own compiler, runner, shell, terminal, package manager, or command semantics.

Examples:

| Item | Owner |
|---|---|
| Background task scheduling primitive | Foundation |
| Compiler install command | Toolchain |
| Shell Runtime | Toolchain |
| Terminal Runtime | Toolchain |
| Styio compiler selection | Toolchain / Configuration |
| Process/Shell/PTY OS managers | Environment |

## 11. Relationship With Environment

Environment owns OS/platform compatibility.

Foundation consumes Environment managers instead of duplicating platform behavior.

Examples:

| Item | Owner |
|---|---|
| Read/write/list/watch files | Environment / FileSystem Manager |
| Resource facts and budgets | Environment / Resource Manager |
| Process execution | Environment / Process Manager |
| Shell command execution | Environment / Shell Manager |
| PTY session capability | Environment / PTY Manager |
| Platform Context | Environment |

## 12. Relationship With Extension

Extension owns plugin/extension semantics. Foundation can provide registry and manifest indexing mechanics only.

| Item | Owner |
|---|---|
| Generic registry API | Foundation |
| Extension activation condition | Extension |
| Extension manifest schema semantics | Extension |
| Manifest storage/index mechanics | Foundation |

## 13. Minimal Implementation Plan

Implement in this order:

| Order | Module | Reason |
|---|---|---|
| 1 | `resource-coordinator` | DataStore and cache need stable locations. |
| 2 | `datastore` | Configuration and Platform Context need ordinary persistence. |
| 3 | `workspace` | Most upper services need workspace scope. |
| 4 | `registry` | Providers, services, and extensions need a shared registration mechanism. |
| 5 | `data-store-owner` contract adoption | Stateful feature owners need explicit mutation and persistence authority. |

Do not add optional modules until there is a concrete multi-layer consumer.

## 14. Directory Rule

`foundation/` should not contain domain-specific configuration or toolchain behavior.

Accepted:

```text
foundation/datastore/schema.dart
foundation/data-store-owner/README.md
foundation/registry/registry.dart
foundation/workspace/workspace_scope.dart
foundation/resource-coordinator/resource_coordinator.dart
```

Rejected:

```text
foundation/shell_configuration.dart
foundation/styio_compiler_selector.dart
foundation/file_system_manager.dart
foundation/terminal_runtime.dart
foundation/theme_settings.dart
```

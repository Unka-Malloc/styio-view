# Foundation Service Boundary

**Purpose:** Document the `docs/design/foundation/foundation-service-boundary/` collection scope, ownership, and maintenance rules.
**Last updated:** 2026-05-17

`Foundation` is the shared application-mechanics layer for Vityo.

It exists because `DataStore`, `Registry`, `Workspace`, and shared resource coordination are needed by many upper layers before those layers can implement their own product behavior.

It must not become a second `Configuration`, `Toolchain`, `Environment`, `Service`, `Interaction`, or `Appearance` layer.

The key constraint:

```text
Foundation is shared infrastructure for upper layers.
Foundation is not a policy layer and not a tool runtime layer.
```

## 0. Settled Boundary

`Foundation` is the application base between upper Vityo layers and the
system-compatibility stack.

```text
Configuration / Toolchain / Extension / Service / Interaction / Appearance
  -> Foundation
    -> Platform Manager
      -> Platform Adapter
        -> Platform Context
          -> Platform Detector
            -> OS / host APIs
```

This order is part of the contract:

| Position | Responsibility |
|---|---|
| Upper layers | Own product meaning, user intent, tool behavior, language service behavior, editor behavior, and rendering. |
| Foundation | Own shared application mechanics used by multiple upper layers. |
| Platform Manager | Own system-specific manager interfaces and implementations exposed upward. |
| Platform Adapter | Adapts Vityo internal calls to platform-specific capabilities. |
| Platform Context | Stores composed platform facts such as file-system, shell, PTY, process, network, and resource facts. |
| Platform Detector | Defines and runs prober behavior that produces platform facts. |
| OS / host APIs | Native file system, process, shell, PTY, network, clipboard, notification, and resource APIs. |

Foundation can depend on Platform Manager surfaces, but it must not bypass them
to call Platform Adapter, Platform Context, Platform Detector, concrete probers,
or OS APIs directly.

## 0.1 Foundation Service Set

The initial Foundation services are:

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

| Service | Admitted because | Boundary |
|---|---|---|
| `datastore` | Cross-layer persistence, schema-state mechanics, migrations, atomic record updates, edit decisions, and scoped subscriptions. | It persists records; it does not know settings, toolchains, editor state, or service result meaning. |
| `data-store-owner` | Each state family needs an owning layer boundary before it can mutate shared persistence. | The owner contract is Foundation; concrete owners live in Configuration, Toolchain, Service, Interaction, Appearance, Extension, or User Service. |
| `registry` | Multiple layers need registration, lookup, lifecycle state, and manifest projection mechanics. | It never executes registered behavior and never exposes runtime values through manifests. |
| `workspace` | Multiple layers need the same workspace identity, scope, root, lifecycle, and scoped service container. | It is not an editor document model and not a project language graph. |
| `resource-coordinator` | Multiple layers need namespace-to-location routing and budget handoff. | Real resource facts, locations, cleanup, quota, and OS operations remain in Environment managers. |
| `lifecycle-coordinator` | Foundation services need deterministic startup, reload, shutdown, and disposal ordering. | Product onboarding, extension activation, and tool execution remain above Foundation. |
| `lock-service` | Shared writes need meaning-free serialization. | Permissions, security decisions, and user approval remain outside Foundation. |
| `event-bus` | Foundation services need local state notifications. | UI command routing, extension events, and language protocol messages remain outside Foundation. |
| `diagnostics-sink` | Foundation needs a common infrastructure health sink. | Language diagnostics, problem rendering, and telemetry UI remain outside Foundation. |

`System Resources` is not a Foundation module name. The Foundation-side module
is `resource-coordinator`; the system-side module remains Environment
`Resource Manager`.

## 0.2 Non-Overlap With Configuration And Toolchain

Foundation must not grow upward into `Configuration` or `Toolchain`.

| Concern | Foundation may own | Configuration / Toolchain must own |
|---|---|---|
| Settings | Record IO, schema-state mechanics, migration execution, locks, subscriptions. | Setting keys, defaults, validation, profiles, environment overlay rules, user/workspace policy. |
| Credentials | Generic storage mechanics through the credential owner. | Secret classification, credential backend policy, token lifecycle, redaction policy. |
| Environment variables | Generic record persistence when called by Configuration. | Overlay semantics, merge order, launch-time injection policy, system-env write policy. |
| Toolchain catalog | Persisted records, registry descriptors, workspace scope, cache namespace routing. | Discovery, install, version resolution, selection policy, executable resolution, runtime health meaning. |
| Tool IO | Nothing beyond generic storage or registration mechanics. | Encoder, decoder, protocol, shell runtime, terminal runtime, process composition. |

Review rule:

```text
If the code knows what a setting means, how a tool runs, which compiler is
selected, how a payload is encoded, or how a shell/runtime is composed,
the code is above Foundation.
```

## 0.3 Additional Admission Test

A new Foundation proposal must pass every test:

| Test | Required answer |
|---|---|
| Is the mechanism used by at least two upper layers? | Yes. |
| Can it work without knowing the domain meaning of stored or registered data? | Yes. |
| Can it be tested without Styio syntax, tool installation, UI rendering, or extension activation? | Yes. |
| Does it depend only on Foundation peers or Platform Manager surfaces? | Yes. |
| Can Configuration and Toolchain change their policies without changing this module? | Yes. |
| Would moving it to Configuration or Toolchain be more semantically precise? | No. |

If any answer fails, keep the capability in the owning upper layer.

## 1. Naming Decision

Use `Foundation` for the layer.

Use `Foundation service` for one concrete reusable mechanism inside that layer.

Use domain names for upper-layer owners, such as `Configuration Store`, `Toolchain Manager`, `Styio Language Service`, `Editor Controller`, and `Appearance Renderer`.

Do not name upper-layer behavior as Foundation just because it persists data or registers providers.

```text
Foundation = shared mechanics.
Upper layer = product meaning.
```

Do not introduce a broad `Foundation Manager` as the main runtime owner.

`Foundation` is a horizontal layer made from small services. Each service has a narrow contract and is reached through a layer-local owner, registrar, controller, or adapter. A broad manager name would hide too many boundaries and make it too easy to move Configuration or Toolchain policy into Foundation.

```text
Good:
  Configuration Store -> Configuration DataStore Owner -> Foundation DataStore
  Toolchain Manager -> Toolchain Registrar -> Foundation Registry
  Interaction Controller -> Workspace Scope -> Foundation Workspace

Bad:
  Configuration Store -> Foundation Manager
  Toolchain Manager -> Foundation Manager
  Editor Controller -> Foundation Manager
```

## 2. Inclusion Rule

A module belongs in Foundation only when all of these are true:

| Rule | Meaning |
|---|---|
| Cross-layer use | At least two upper layers need the same mechanism. |
| Meaning-free | The module does not decide domain meaning. |
| Product-neutral | The module does not own user interaction or UI behavior. |
| Tool-neutral | The module does not own external tool selection, protocol semantics, shell runtime, or process behavior. |
| OS-neutral | The module does not probe or adapt operating-system APIs directly. |
| Stable primitive | The module is a low-level primitive that upper layers can compose safely. |

If a module fails one of these rules, keep it in the owning upper layer.

## 2.1 Foundation Service Families

Foundation services are grouped by shared mechanism, not by product domain.

| Family | Foundation modules | Why this is Foundation | What it must not absorb |
|---|---|---|---|
| Persistence | `datastore`, `data-store-owner` contract. | Many layers need consistent record IO, schema states, migrations, atomic writes, and mutation ownership. | Setting meaning, credential policy, service truth, editor behavior. |
| Registration | `registry`, manifest index mechanics. | Many layers need register/unregister/lookup/list and durable manifest references. | Extension activation, tool command semantics, service protocol meaning. |
| Workspace scope | `workspace`. | Many layers need the same workspace identity, root, scope, lifecycle, and scoped service container. | Editor document mutation, file binding, project language semantics. |
| Resource coordination | `resource-coordinator`. | Many layers need namespace-to-location routing and budget handoff. | OS resource probing, directory creation, cleanup execution, cache eviction policy. |
| Coordination | `lifecycle-coordinator`, `lock-service`, `event-bus`. | Shared services need startup/shutdown ordering, write serialization, and in-process foundation notifications. | User workflow approval, UI command routing, extension event semantics. |
| Infrastructure status | `diagnostics-sink`. | Foundation needs a common place for health/status events from its own services. | Language diagnostics, problem panel rendering, telemetry product UI. |

This avoids making `Foundation` a home for all common-looking code.

```text
Common mechanism can be Foundation.
Common domain policy cannot be Foundation.
```

## 2.2 Relationship To Upper Foundation Consumers

The same Foundation service can be used by many upper layers, but the meaning of each record, registration, or scope remains with the caller.

| Consumer | Uses Foundation for | Still owns itself |
|---|---|---|
| Configuration | Persisting settings records, credential references, environment overlay records, provider registrations, locks, and workspace/user scopes. | Setting semantics, default values, validation, migration policy, env overlay merge order, credential classification. |
| Toolchain | Persisting selected toolchain metadata, registering discovered toolchains, routing cache/state namespaces, and sequencing toolchain status updates. | Discovery, install, provenance checks, version resolution, executable selection, Shell Runtime, codecs, process composition. |
| Extension | Manifest index entries, extension state records, lifecycle state, and workspace scopes. | Activation, contribution points, permissions, extension host behavior. |
| Service | Service provider registration, service status records, snapshot storage, and workspace/document scopes. | Styio syntax/semantic truth, remote-service protocol meaning, diagnostics, completion, hover, references. |
| Interaction | Editor/session state persistence, workspace scope, lock/event primitives. | Document model, text buffer, commands, selection, focus, workspace edit application. |
| Appearance | Layout/theme state persistence and state observation. | Rendering, theme mapping, widgets, panels, surfaces. |

The dependency shape must stay:

```text
Upper-layer owner
  -> Foundation service
    -> Environment / Platform Manager surface if OS access is required
```

Foundation must not call upward into these consumers.

## 2.3 Non-Overlap Enforcement

Foundation must stay below Configuration and Toolchain even when both layers
use the same Foundation primitives.

The safe implementation shape is:

```text
Upper-layer owner
  -> Foundation primitive
    -> Environment / Platform Manager only when OS access is required
```

The unsafe implementation shape is:

```text
Foundation primitive
  -> upper-layer owner
  -> domain policy
```

Use this decision table during reviews:

| Question | If yes, owner is not Foundation |
|---|---|
| Does the code decide what a setting means? | Configuration |
| Does the code decide whether a credential is secret or how it should be protected? | Configuration |
| Does the code decide which Styio compiler or runtime should be used? | Toolchain |
| Does the code download, verify, select, or launch an external tool? | Toolchain |
| Does the code define an encoder/decoder contract for an external protocol? | Toolchain |
| Does the code probe or call OS APIs directly? | Environment / System Compatibility |
| Does the code decide language truth such as parse, type, symbol, hover, completion, or diagnostics? | Service / StyioService |
| Does the code mutate editor documents or apply workspace edits? | Interaction |
| Does the code render surfaces, widgets, themes, or panels? | Appearance |

Foundation can still provide the shared mechanics for these owners:

| Foundation primitive | What it can provide | What stays above it |
|---|---|---|
| DataStore | record IO, schema state mechanics, atomic write mechanics, subscriptions | record meaning, validation, migration policy |
| Registry | register, unregister, lookup, list, lifecycle state, manifest projection | provider semantics, activation rules, execution behavior |
| Workspace | workspace identity, scope, root, scoped service container | editor behavior, project semantics, tool execution policy |
| Resource Coordinator | namespace routing and budget handoff | OS probing, cleanup execution, cache eviction policy |
| Lifecycle / Lock / Event | sequencing, serialization, foundation-local notifications | product workflow, extension activation, UI command routing |

## 2.4 Naming and Rejection Rules

Use these names when the module belongs to Foundation:

| Capability name | Foundation module name |
|---|---|
| Data storage mechanics | `datastore` |
| State ownership contract | `data-store-owner` |
| Registration mechanics | `registry` |
| Workspace identity and scope | `workspace` |
| Shared resource routing | `resource-coordinator` |
| Startup/shutdown ordering | `lifecycle-coordinator` |
| Write/update serialization | `lock-service` |
| Foundation-local notifications | `event-bus` |
| Foundation health/status capture | `diagnostics-sink` |

Reject these names from Foundation because they imply upper-layer or OS-specific ownership:

| Rejected Foundation name | Correct owner |
|---|---|
| `configuration-store` | Configuration |
| `credential-datastore` | Configuration |
| `toolchain-manager` | Toolchain |
| `encoder-decoder` | Toolchain |
| `shell-runtime` | Toolchain |
| `terminal-runtime` | Toolchain |
| `file-system-manager` | Environment / System Compatibility |
| `process-manager` | Environment / System Compatibility |
| `resource-manager` | Environment / System Compatibility |
| `system-resources` | Do not use as a Foundation module; use `resource-coordinator` in Foundation and `resource-manager` in Environment. |

## 3. Initial Foundation Services

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

| Foundation service | Reason to exist | Primary upper-layer users |
|---|---|---|
| `datastore` | Persist scoped IDE-owned records with schema states, migrations, and atomic writes. | Configuration, Toolchain, Extension, Service, Interaction, Appearance. |
| `data-store-owner` | Define how each layer owns state families above the generic DataStore. | Every stateful layer. |
| `registry` | Register, unregister, look up, and list providers or manifests without owning their domain meaning. This is the implementation module for the broader Registration capability. | Configuration, Toolchain, Extension, Service, Interaction. |
| `workspace` | Provide workspace identity, root, scope, lifecycle, and scoped service references. | Service, Interaction, Toolchain, Configuration, Extension. |
| `resource-coordinator` | Route namespaces to app/cache/state/temp/runtime locations through Environment resource managers. | DataStore, cache owners, log owners, index owners. |
| `lifecycle-coordinator` | Sequence startup, reload, shutdown, and disposal for Foundation-owned services. | Foundation service container and workspace scope. |
| `lock-service` | Serialize writes and updates around shared state. | DataStore, registry, workspace lifecycle. |
| `event-bus` | Publish foundation-level state changes in-process. | Layer-local DataStore owners and service containers. |
| `diagnostics-sink` | Collect Foundation infrastructure health and status events. | Diagnostics surfaces, logs, debug tooling. |

## 3.1 Anti-Overlap Contract

Foundation can be used by `Configuration` and `Toolchain`, but it cannot absorb their responsibilities.

| Upper layer | What Foundation provides | What must remain in the upper layer |
|---|---|---|
| Configuration | DataStore mechanics, owner scoping, registry entries, locks, workspace scope. | Setting schema, setting defaults, validation rules, migration policy, environment-variable overlay semantics, credential policy. |
| Toolchain | DataStore mechanics, registry entries, workspace scope, resource routing for tool caches/state. | Tool discovery, download, install, version resolution, executable selection, encoder/decoder contracts, shell runtime, terminal runtime, process composition. |
| Extension | Registry mechanics, manifest index persistence, workspace scope. | Activation, contribution semantics, permission model, extension host lifecycle. |
| Service | Registry mechanics, snapshot persistence, workspace/document scope. | Styio syntax, semantic truth, completion, hover, diagnostics, semantic tokens, fallback behavior. |
| Interaction | State persistence, workspace scope, lock/event primitives. | Editor controller behavior, text buffer mutation, command routing, workspace edit application. |
| Appearance | State persistence and state subscriptions. | Rendering, theme mapping, panels, widgets, surfaces. |

Use this rejection rule:

```text
If the Foundation proposal names a Styio version, a compiler path, a setting key,
a shell policy, an encoder/decoder format, an extension contribution point,
or a UI behavior, reject it from Foundation and put it in the owning layer.
```

The rejection is mandatory even when the upper layer needs DataStore, Registry, Workspace, or Resource Coordinator.

```text
DataStore is allowed to store a Toolchain record.
DataStore is not allowed to understand tool resolution.

Registry is allowed to index a Configuration provider.
Registry is not allowed to validate setting semantics.

Resource Coordinator is allowed to route a cache namespace.
Resource Coordinator is not allowed to choose a cache policy.
```

## 4. Non-Goals

Foundation must not own these capabilities:

| Capability | Correct owner | Reason |
|---|---|---|
| Setting keys, defaults, schemas, migrations, and policy values. | Configuration | Settings meaning is product policy, not persistence mechanics. |
| Environment-variable overlays. | Configuration | Vityo-owned env overlays are configuration values. |
| Credentials and secrets. | Configuration / Credential DataStore | Secrets require a dedicated policy and storage boundary. |
| Tool discovery, installation, version selection, encoders, decoders, shell runtime, and terminal runtime. | Toolchain | External tool behavior is runtime composition, not foundation. |
| File, process, shell, PTY, resource, and network OS API adaptation. | Environment / Platform Manager | System compatibility belongs below Foundation. |
| Extension activation and contribution semantics. | Extension | Registry can store entries; Extension decides what they mean. |
| Styio syntax, semantics, diagnostics, completion, hover, and semantic tokens. | Service / StyioService | Language truth belongs to StyioService and the service adapter. |
| Editor document model, text buffer, commands, selection, focus, and workspace edit behavior. | Interaction | Editor behavior is user interaction logic. |
| Rendering, theme mapping, panels, widgets, and visual surfaces. | Appearance | UI presentation belongs to Appearance. |

## 5. Dependency Direction

```text
Upper layers
  -> Foundation services
    -> Environment / Platform Manager
      -> Platform Adapter
        -> Platform Context
          -> Platform Detector
```

Foundation may depend downward on Environment platform managers when it needs file-system, resource, process, or OS-compatible primitives.

Foundation must not depend upward on Configuration, Toolchain, Extension, Service, Interaction, or Appearance.

Allowed dependencies:

| Foundation service | May depend on |
|---|---|
| `datastore` | `resource-coordinator`, `lock-service`, `File System Manager`. |
| `registry` | `lock-service`, optionally `datastore` for manifest index persistence. |
| `workspace` | `lifecycle-coordinator`, optionally `datastore` for workspace metadata. |
| `resource-coordinator` | `Resource Manager` for locations and budget facts. |
| `event-bus` | No upper layer; foundation-internal publication only. |
| `diagnostics-sink` | Optionally `datastore` for infrastructure diagnostics persistence. |

Foundation services must not depend on `Platform Detector`, concrete `Prober` modules, `Platform Context`, or `Platform Adapter`. Those belong below the Platform Manager boundary.

Disallowed dependencies:

| Disallowed dependency | Why it is wrong |
|---|---|
| `datastore -> Configuration Store` | DataStore would become dependent on one consumer's settings model. |
| `registry -> Extension activation` | Registry would become Extension runtime. |
| `resource-coordinator -> Toolchain download` | Resource routing would become tool behavior. |
| `workspace -> Editor Controller` | Workspace scope would become editor behavior. |
| `event-bus -> UI command router` | Foundation state notification would become interaction logic. |

## 6. DataStore Boundary

DataStore is a persistence primitive. It stores records; it does not own state meaning.

```text
Layer feature
  -> Layer DataStore Owner
    -> Foundation / DataStore
      -> Foundation / Resource Coordinator
      -> Environment / File System Manager
```

| Data family | Owner |
|---|---|
| Shell preferences | Configuration / Shell Configuration |
| Environment overlays | Configuration / Environment Variable Configuration |
| Toolchain selection | Toolchain plus Configuration binding |
| Service snapshots | Service DataStore Owner |
| Editor tabs, cursor, selection, and dirty state | Interaction DataStore Owner |
| Theme and layout state | Appearance DataStore Owner |
| Credentials and tokens | Configuration / Credential DataStore |

The rule is:

```text
DataStore owns IO mechanics.
DataStore Owner owns mutation authority.
Domain layer owns meaning.
```

## 7. Registry Boundary

Registry is a registration primitive. It stores and indexes entries; it does not execute registered behavior.

| Registered thing | Registry may store | Domain owner must decide |
|---|---|---|
| Setting provider | Provider id, manifest reference, lifecycle state. | Setting schema, default value, validation, migration. |
| Toolchain provider | Provider id, descriptor reference, availability state. | Discovery, install, version selection, process launch. |
| Extension manifest | Manifest id, source, index metadata. | Activation, contribution points, permissions, extension host lifecycle. |
| Service provider | Provider id, capability metadata. | Protocol interpretation, result meaning, fallback policy. |

Foundation registry also exposes a manifest view. The manifest contains ids, kinds, owners, lifecycle state, and metadata, but it does not expose the registered runtime value. Cross-layer registry contracts should use the manifest when they need introspection without taking ownership of another layer's behavior.

## 8. Resource Coordinator Boundary

Use `Resource Coordinator`, not `System Resources`, in Foundation.

System resource facts and OS-specific behavior belong to Environment. Foundation only coordinates locations and budget hints for upper-layer storage and caches.

```text
Upper-layer owner
  -> Resource Coordinator
    -> Environment / Resource Manager
  -> File System Manager for actual file operations
```

| Concern | Owner |
|---|---|
| App/cache/state/temp/runtime root facts | Environment / Resource Manager |
| Namespace-to-location routing | Foundation / Resource Coordinator |
| Actual directory creation | Environment / File System Manager |
| Cache eviction policy | Owning upper layer, often Configuration policy plus cache owner. |
| Cleanup execution | Owning subsystem through File System Manager. |

## 9. Foundation Service Acceptance Checklist

Before adding a new Foundation service, check:

| Question | Required answer |
|---|---|
| Is this used by multiple upper layers? | Yes. |
| Does it avoid owning domain meaning? | Yes. |
| Can it be tested without Styio syntax, toolchain installation, UI, or extension activation? | Yes. |
| Does it call only Foundation peers or Environment platform managers? | Yes. |
| Would putting it in Configuration or Toolchain be more precise? | No. |
| Can an upper layer replace its owner/policy without changing Foundation? | Yes. |

If any answer fails, the module is not Foundation.

## 10. Foundation Exit Rule

If a Foundation service starts accumulating upper-layer policy, split that policy upward immediately.

| Symptom | Required action |
|---|---|
| DataStore knows a concrete setting name. | Move the setting schema and validation to Configuration. |
| Registry executes an extension contribution. | Move execution to Extension and keep only manifest indexing in Registry. |
| Resource Coordinator chooses a Styio compiler cache policy. | Move cache policy to Toolchain; keep only location routing in Foundation. |
| Workspace owns editor document mutation. | Move document behavior to Interaction and keep only workspace identity/scope in Foundation. |
| Diagnostics Sink classifies Styio syntax errors. | Move language diagnostics to Service and keep only infrastructure status in Foundation. |

# Foundation Layer Contract

**Purpose:** Document the `docs/design/foundation/foundation-layer-contract/` collection scope, ownership, and maintenance rules.
**Last updated:** 2026-05-17

`Foundation` is Vityo's shared application-mechanics layer.

It exists because multiple upper layers need the same low-level mechanics before they can implement real product behavior:

```text
Upper horizontal layers
  -> Foundation
    -> Environment / Platform Manager
      -> Platform Adapter
        -> Platform Context
          -> Platform Detector
            -> OS / host / external system APIs
```

Foundation must not become a softer name for Configuration, Toolchain, Extension, Service, Interaction, Appearance, or Environment.

The contract is:

```text
Foundation provides shared mechanics.
Owning layers provide domain meaning.
Environment provides system compatibility.
```

## 0. Settled Non-Overlap Decision

`Foundation` is the shared base for application mechanics, not the shared home
for every "basic" feature.

The admitted Foundation shape is deliberately narrow:

| Foundation category | Allowed modules | Reason |
|---|---|---|
| Persistence mechanics | `datastore`, `data-store-owner` contract | Multiple layers need scoped record IO, schema-state mechanics, migrations, atomic writes, and mutation ownership. |
| Registration mechanics | `registry` | Multiple layers need register/unregister/lookup/list and manifest projection without executing registered behavior. |
| Scope mechanics | `workspace` | Multiple layers need the same workspace identity, root, scope, lifecycle, and scoped service container. |
| Resource routing mechanics | `resource-coordinator` | Multiple layers need namespace-to-location routing and budget handoff without owning OS resources. |
| Coordination mechanics | `lifecycle-coordinator`, `lock-service`, `event-bus`, `diagnostics-sink` | Foundation services need deterministic startup/shutdown, serialized writes, local notifications, and infrastructure health capture. |

The excluded shape is equally important:

| Excluded concern | Correct owner |
|---|---|
| IDE setting keys, defaults, validation, profiles, environment-variable overlays. | Configuration |
| Credential classification, secret backend policy, redaction policy, token lifecycle. | Configuration / Credential DataStore |
| Tool discovery, install, version resolution, executable selection, protocol codecs, Shell Runtime, Terminal Runtime. | Toolchain |
| File-system, process, shell, PTY, network, clipboard, notification, and resource OS calls. | Environment / Platform Manager |

The key rule is:

```text
Foundation can standardize shared mechanics.
Foundation cannot standardize upper-layer meaning.
```

If a proposed Foundation API needs to understand a setting, credential, tool,
runtime, protocol, extension, language fact, editor operation, visual surface, or
OS capability, it belongs above or below Foundation, not inside Foundation.

## 0.1 Upper-Layer Overlap Rejection Gate

`Foundation` must reject modules that are only "basic" because they are common
or frequently used. A module is Foundation only when it is both shared and
meaning-free.

| Proposed module behavior | Decision |
|---|---|
| Defines setting keys, default values, profiles, environment overlays, or user-visible policy. | Reject from Foundation. Configuration owns it. |
| Defines credential categories, secret backend choice, redaction, token refresh, or credential lifecycle. | Reject from Foundation. Configuration / Credential DataStore owns it. |
| Discovers, installs, selects, launches, health-checks, encodes, or decodes tools and runtimes. | Reject from Foundation. Toolchain owns it. |
| Defines shell runtime, terminal runtime, task execution semantics, or external command behavior. | Reject from Foundation. Toolchain owns it. |
| Calls platform-specific file, process, shell, PTY, network, clipboard, notification, or resource APIs. | Reject from Foundation. Environment / Platform Manager owns it. |
| Stores records, projects manifests, coordinates lifecycle, serializes writes, scopes a workspace, or routes resource namespaces without interpreting domain meaning. | Acceptable Foundation candidate. |

The accepted dependency direction is:

```text
Configuration / Toolchain / Extension / Service / Interaction / Appearance
  -> Foundation shared mechanics
    -> Environment / Platform Manager when system primitives are needed
```

The rejected dependency direction is:

```text
Foundation
  -> Configuration semantics
  -> Toolchain semantics
  -> concrete Platform Adapter / Detector / OS API
```

This prevents a broad "common services" directory from silently rebuilding
Configuration, Toolchain, or Platform Manager under a different name.

## 1. Layer Decision

Use `Foundation` for shared application primitives that are required by several upper layers and do not decide domain semantics.

Do not use `Foundation` for:

| Not Foundation | Correct owner |
|---|---|
| Setting schemas, defaults, environment overlays, profile policy. | Configuration |
| Credential classification and secret policy. | Configuration / Credential DataStore |
| Tool discovery, installation, version resolution, encoders, decoders. | Toolchain |
| Shell Runtime, Terminal Runtime, execution profile semantics. | Toolchain |
| File-system, process, shell, PTY, network, and resource OS APIs. | Environment / Platform Manager |
| Extension activation, contribution points, extension host lifecycle. | Extension |
| Styio syntax, semantic truth, diagnostics, completion, hover, tokens. | Service / Styio Language Service |
| Editor document model, text buffer, commands, selection, edit application. | Interaction |
| Rendering, theme mapping, widgets, surfaces, panels. | Appearance |

The practical rule:

```text
If the module answers "what does this feature mean?", it is not Foundation.

If the module only answers "how is this record stored, registered, scoped,
locked, routed, or sequenced?", it may be Foundation.
```

## 2. Foundation Service Set

Initial Foundation modules:

```text
frontend/vityo_app/lib/src/view_ide/foundation/
  datastore/
  registry/
  workspace/
  resource_coordinator/
  lifecycle_coordinator/
  lock_service/
  event_bus/
  diagnostics_sink/
```

Design names and responsibilities:

| Foundation service | Owns | Must not own |
|---|---|---|
| DataStore API | Record IO, schema-state storage, migration runner, atomic writes, persistence mechanics. | Setting meaning, credential policy, tool behavior, language semantics. |
| DataStore Owner contract | Layer-local mutation authority, namespace ownership, state-family ownership. | A global state model or feature behavior. |
| Registry | Register, unregister, lookup, list, lifecycle state, manifest projection mechanics. | Extension activation, tool execution, service protocol meaning. |
| Workspace | Workspace identity, root, scope, lifecycle, and scoped foundation service container. | Editor document mutation, project language semantics. |
| Resource Coordinator | Namespace-to-location routing and budget handoff to Environment Resource Manager. | OS probing, directory creation, cleanup execution, cache policy. |
| Lifecycle Coordinator | Foundation service startup, reload, shutdown, and disposal sequencing. | Product onboarding, extension activation, process execution. |
| Lock Service | Shared mutual exclusion and transaction locks for Foundation services. | Permission checks, security policy, user workflow approval. |
| Event Bus | Foundation-level in-process state notifications. | UI command routing, extension events, language protocol messages. |
| Diagnostics Sink | Foundation infrastructure health/status events. | Styio diagnostics, problem-panel rendering, telemetry UI. |

Only add another Foundation service when at least two upper layers need the same meaning-free primitive.

## 3. DataStore Boundary

DataStore is not Configuration and not Toolchain.

Correct path:

```text
Configuration Store / Toolchain Manager / Service / Interaction / Appearance
  -> Layer DataStore Owner
    -> Foundation / DataStore API
      -> Foundation / Resource Coordinator
      -> Environment / File System Manager
```

Incorrect paths:

```text
DataStore -> Configuration Store
DataStore -> Toolchain Manager
File System Manager -> DataStore
Resource Manager -> DataStore
```

Boundary table:

| Concern | Foundation may do | Upper layer must do |
|---|---|---|
| Settings | Persist schema-state records when called by Configuration owner. | Define keys, defaults, schemas, validation, migration policy, UI grouping. |
| Environment variables | Store records as generic DataStore payloads. | Define overlay semantics, merge order, shell/process injection policy. |
| Credentials | Provide generic storage mechanics only through a credential owner. | Classify secrets, choose secret backend, define lookup and lifecycle. |
| Toolchain state | Persist records and route cache/state paths. | Discover, install, resolve, select, execute, encode, decode. |
| Service state | Persist snapshots and status through service owner. | Interpret protocol results, diagnostics, hover, completion, references. |

DataStore owns IO mechanics.

DataStore Owner owns mutation authority.

Domain layer owns meaning.

DataStore record operations are lock-scoped Foundation mechanics:

| Rule | Meaning |
|---|---|
| Lock identity | `namespace + scope + workspace + key` is the record-level lock identity. |
| Locked operations | `read`, `write`, `delete`, and migration write-back must use the same record lock. |
| Migration write-back | A successful read-time migration must persist the migrated record while still holding the record lock. |
| Owner boundary | DataStore Owners define mutation authority, but do not directly manage record locks. |
| Domain boundary | Locking does not imply feature approval, permission checks, security policy, or workflow confirmation. |

This prevents concurrent writes or migration write-back from racing for one record while keeping lock ownership inside Foundation persistence mechanics.

## 4. Registration Boundary

`Registration` is the shared capability.

`registry` is the Foundation implementation for generic registration mechanics.

Layer-specific registries may exist above Foundation when they need domain meaning.

```text
Layer registrar
  -> Foundation / Registry
    -> Manifest projection
```

Foundation Registry may store:

| Registry field | Allowed |
|---|---|
| id | Yes |
| kind | Yes |
| owner | Yes |
| lifecycle state | Yes |
| manifest reference | Yes |
| metadata map | Yes, if it is discovery metadata. |
| runtime value | Internally only; not through manifest projection. |

Foundation Registry must not execute registered behavior or validate domain schemas.

Examples:

| Registered thing | Foundation Registry can do | Owning layer must do |
|---|---|---|
| Configuration provider | Store provider id, owner, lifecycle state, manifest reference. | Validate settings schema and default values. |
| Toolchain provider | Store provider id and availability metadata. | Discover executables, install versions, launch tools. |
| Extension manifest | Store manifest index entry. | Activate extension and apply contribution points. |
| Service provider | Store provider id and capability metadata. | Interpret protocol and route feature results. |

Current implementation contract:

| Capability | Foundation Registry behavior |
|---|---|
| Entry validation | Rejects empty `id`, `kind`, or `owner`. |
| Duplicate handling | Rejects duplicate `id` registration. |
| Runtime lookup | Allows direct lookup by `id` for the owning runtime code path. |
| Filtered listing | Lists entries by `kind`, `owner`, and lifecycle `state`. |
| Lifecycle state | Updates generic lifecycle state without executing registered behavior. |
| Metadata updates | Merges or replaces discovery metadata without interpreting it. |
| Manifest projection | Emits id, kind, owner, state, and metadata only. Runtime values are not projected. |
| Manifest safety | Uses immutable metadata projection so consumers cannot mutate registry state through the manifest. |
| Manifest persistence | `FoundationRegistryManifestStore` persists manifest projections through a `FoundationDataStoreOwner`; it does not persist runtime values. |
| Category registrar | `FoundationRegistryRegistrar` wraps owner and category boundaries for `schema`, `provider`, `command`, `capability`, `renderer`, and `policy` registrations. |

This keeps `registry` as Foundation mechanics. Toolchain, Configuration, Extension, Service, Interaction, and Appearance may register things, but they must still interpret and execute their own domain behavior.

## 5. Workspace Boundary

Workspace belongs in Foundation only as shared scope mechanics.

Foundation Workspace owns:

| Concern | Meaning |
|---|---|
| Workspace id | Stable identity for state, registry, and service scope. |
| Workspace root | Root reference used by file and resource boundaries. |
| Workspace lifecycle | Open, initialize, reload, close, dispose sequencing hooks. |
| Scoped container | Access to Foundation services for a workspace. |

Foundation Workspace must not own:

| Concern | Correct owner |
|---|---|
| Open document text model. | Interaction |
| Editor tabs, cursor, selection, undo/redo. | Interaction DataStore Owner |
| Project language graph. | Service / Styio Language Service |
| Workspace file reads/writes. | Environment / File System Manager |
| User-visible workspace onboarding. | Appearance / Interaction |

## 6. Resource Boundary

Do not create a Foundation module called `system-resources`.

Use:

```text
Foundation / Resource Coordinator
  -> Environment / Resource Manager
    -> Platform Adapter
      -> Platform Context
        -> Platform Detector
```

Resource responsibilities:

| Concern | Owner |
|---|---|
| CPU, memory, storage, temp, XDG, sandbox facts. | Environment / Resource Manager and lower platform layers. |
| App/cache/state/temp/runtime location selection. | Environment / Resource Manager. |
| Namespace-to-location routing for upper-layer owners. | Foundation / Resource Coordinator. |
| Actual directory creation, read, write, delete, watch. | Environment / File System Manager. |
| Cache eviction policy. | Owning upper layer, often guided by Configuration policy. |
| Toolchain cache policy. | Toolchain. |
| Data schema, migration, and transaction policy. | DataStore and DataStore Owner. |

Resource Coordinator can ask where a namespace should live.

Resource Coordinator cannot decide why a cache exists or when it should be evicted.

## 7. Anti-Overlap Matrix

Reject a Foundation proposal when it introduces any of these concepts:

| Concept in proposal | Reject from Foundation because |
|---|---|
| Setting key, setting schema, default value. | Configuration owns settings meaning. |
| Environment overlay precedence. | Configuration owns environment-variable policy. |
| Secret/token classification. | Credential DataStore owns secret policy. |
| Styio version, compiler path, executable resolution. | Toolchain owns tool behavior. |
| Encoder/decoder format. | Toolchain owns process/protocol IO conversion. |
| Shell profile, terminal session, PTY lifecycle. | Toolchain or Environment owns runtime/system behavior. |
| OS API probing or OS API adaptation. | Platform Detector/Context/Adapter/Manager owns system compatibility. |
| Extension contribution point. | Extension owns extension semantics. |
| Syntax tree, semantic facts, diagnostics, completion. | Service owns language-service results. |
| Text buffer mutation or editor commands. | Interaction owns editor behavior. |
| Theme mapping or renderer behavior. | Appearance owns visual behavior. |

## 8. Foundation Candidate Review Flow

Use this review flow before adding any new Foundation directory or public API.

```text
New shared capability proposal
  -> Is it needed by at least two upper layers?
    -> no: keep it in the owning upper layer
    -> yes:
      -> Does it understand settings, tools, services, editor behavior, UI, or OS APIs?
        -> yes: keep it in the semantic owner layer
        -> no:
          -> Does it provide storage, registration, scope, lifecycle, locking, event, diagnostic, or resource-routing mechanics?
            -> yes: it may be Foundation
            -> no: reject or redesign the boundary
```

The intended decision examples are:

| Proposal | Decision | Reason |
|---|---|---|
| Generic persisted records and migrations. | Foundation / DataStore | It is storage mechanics without feature meaning. |
| Layer-local state mutation owner. | Foundation / DataStore Owner contract | It standardizes ownership, while meaning stays in the upper layer. |
| Generic provider registration and manifest projection. | Foundation / Registry | It registers and projects metadata without executing provider behavior. |
| Workspace identity and scope. | Foundation / Workspace | Multiple layers need the same scope primitive. |
| Namespace routing to cache/state/temp/resource locations. | Foundation / Resource Coordinator | It routes requests but does not own OS resources or cache policy. |
| Settings schema and default values. | Configuration | It defines what a setting means. |
| Environment-variable overlay precedence. | Configuration | It defines launch configuration policy. |
| Credential classification and secret backend policy. | Configuration / Credential DataStore | It owns privacy and secret semantics. |
| Styio compiler discovery and selected version. | Toolchain | It owns tool behavior and version selection. |
| Encoder and decoder protocol contracts. | Toolchain | It owns external tool IO semantics. |
| Shell Runtime or Terminal Runtime. | Toolchain | It composes runtime behavior above platform managers. |
| File-system or process API adaptation. | Environment / Platform Manager | It talks to system-specific managers and platform capabilities. |

The final admission rule is:

```text
Foundation can standardize how upper layers store, register, scope, lock,
sequence, observe, and route shared application mechanics.

Foundation cannot standardize what upper-layer records, tools, services,
commands, or UI states mean.
```

## 8. Acceptance Checklist

A new Foundation module is allowed only if every answer is `Yes`:

| Question | Required answer |
|---|---|
| Is the same primitive required by at least two upper layers? | Yes |
| Is it meaning-free and product-neutral? | Yes |
| Can it be tested without Styio syntax, external tool installation, UI, or extension activation? | Yes |
| Does it depend only on Foundation peers or Environment Platform Manager surfaces? | Yes |
| Can Configuration and Toolchain replace their policies without changing it? | Yes |
| Does it avoid direct dependencies on Platform Detector, Platform Context, and Platform Adapter? | Yes |

If any answer is not `Yes`, keep the capability in the owning upper layer.

## 9. Implementation Rule

Foundation code should live under:

```text
frontend/vityo_app/lib/src/view_ide/foundation/
```

Upper-layer owners should live with their owning layer:

```text
frontend/vityo_app/lib/src/view_ide/environment/configuration/
frontend/vityo_app/lib/src/view_ide/environment/toolchain/
frontend/vityo_app/lib/src/view_ide/environment/extension/
frontend/vityo_app/lib/src/view_ide/service/
frontend/vityo_app/lib/src/view_ide/interaction/
frontend/vityo_app/lib/src/view_render/
```

Do not add runtime directories named:

```text
view_ide/foundation/configuration_store/
view_ide/foundation/toolchain_manager/
view_ide/foundation/system_resources/
view_ide/foundation/file_system_manager/
view_ide/foundation/process_manager/
view_ide/foundation/shell_runtime/
view_ide/foundation/terminal_runtime/
```

Those names indicate the capability belongs outside Foundation.

## 10. Test Contract

Foundation tests must prove mechanics without depending on upper-layer meaning.

| Foundation service | Required test style |
|---|---|
| DataStore | Record IO, schema state, migration, atomicity, namespace isolation. |
| DataStore Owner | Namespace access control and owner metadata. |
| Registry | Register, unregister, lookup, list, manifest projection without exposing runtime value. |
| Workspace | Scope identity, lifecycle sequencing, service container boundaries. |
| Resource Coordinator | Namespace routing and budget handoff using fake Resource Manager. |
| Lifecycle Coordinator | Ordering, idempotency, dispose behavior. |
| Lock Service | Serialization and conflict behavior. |
| Event Bus | Subscription, publication, disposal behavior. |
| Diagnostics Sink | Infrastructure status recording and filtering. |

Tests should not require Styio compiler execution, external tool installation, UI rendering, or OS-global mutation.

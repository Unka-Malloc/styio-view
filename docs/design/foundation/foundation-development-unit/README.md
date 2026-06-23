# Foundation Development Unit

**Purpose:** Document the `docs/design/foundation/foundation-development-unit/` collection scope, ownership, and maintenance rules.
**Last updated:** 2026-05-17

`Foundation` is the independent development unit for Vityo's shared
application mechanics.

It is not an upper product layer and not a system compatibility layer. It sits
between upper Vityo layers and the Environment platform-manager stack.

```text
Configuration / Toolchain / Extension / Service / Interaction / Appearance
  -> Foundation
    -> Environment / Platform Manager
      -> Platform Adapter
        -> Platform Context
          -> Platform Detector
            -> OS / host / external system APIs
```

The settled naming is:

```text
Foundation = shared application mechanics.
Configuration = IDE settings and policy values.
Toolchain = external tools and runtime composition.
Environment = OS/platform compatibility and system calls.
```

## 1. Development Purpose

Foundation should be developed as a small horizontal base that upper layers can
reuse without inheriting each other's meaning.

It exists because these capabilities are required by many Vityo layers:

| Shared need | Foundation answer |
|---|---|
| Persist IDE-owned state consistently. | `datastore` plus `data-store-owner` contract. |
| Register providers, capabilities, manifests, and lifecycle state. | `registry`. |
| Scope state and services to a workspace. | `workspace`. |
| Route cache/state/temp/runtime namespaces. | `resource-coordinator`. |
| Sequence shared startup, reload, shutdown, and disposal. | `lifecycle-coordinator`. |
| Serialize shared writes and migrations. | `lock-service`. |
| Notify foundation-local state changes. | `event-bus`. |
| Collect infrastructure health from Foundation services. | `diagnostics-sink`. |

The development target is not a broad `FoundationManager`.

```text
Good:
  Configuration Store -> Configuration DataStore Owner -> Foundation DataStore
  Toolchain Manager -> Toolchain Registrar -> Foundation Registry
  Service Runtime -> Service DataStore Owner -> Foundation DataStore

Bad:
  Configuration Store -> Foundation Manager
  Toolchain Manager -> Foundation Manager
  Editor Controller -> Foundation Manager
```

## 2. Allowed Service Set

The first Foundation implementation cut is intentionally narrow:

```text
frontend/vityo_app/lib/src/view_ide/foundation/
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

| Service | Owns | Must not own |
|---|---|---|
| `datastore` | Record IO, schema-state storage, migration execution, atomic writes, subscriptions. | Setting meaning, credential policy, tool behavior, language truth, editor behavior. |
| `data-store-owner` | Layer-local mutation authority, namespace ownership, state-family ownership. | A global state model or feature behavior. |
| `registry` | Register, unregister, lookup, list, lifecycle state, and manifest projection mechanics. | Provider execution, extension activation, setting validation, tool launch. |
| `workspace` | Workspace identity, root, scope, lifecycle, and scoped service container. | Editor document mutation, project language semantics, tool execution policy. |
| `resource-coordinator` | Namespace-to-location routing and budget handoff. | OS resource probing, directory creation, cleanup execution, cache eviction policy. |
| `lifecycle-coordinator` | Foundation service startup, reload, shutdown, disposal sequencing. | Product onboarding, extension activation, process execution. |
| `lock-service` | Shared write/update serialization. | Permission decisions, security policy, user workflow approval. |
| `event-bus` | Foundation-local state notifications. | UI command routing, extension events, language protocol messages. |
| `diagnostics-sink` | Foundation infrastructure health and status events. | Styio diagnostics, problem-panel rendering, telemetry UI. |

Only add another Foundation service when at least two upper layers need the same
meaning-free primitive.

## 3. Non-Overlap With Configuration

Configuration owns settings and policy values. Foundation only provides storage,
registration, locking, scope, lifecycle, and resource-routing mechanics.

| Configuration concern | Foundation may provide | Must stay in Configuration |
|---|---|---|
| Settings | Schema-state record IO and migration execution. | Setting keys, defaults, validation, profiles, migration policy, UI grouping. |
| Environment variables | Generic record persistence when called by a Configuration owner. | Overlay precedence, merge order, process/shell injection policy, system-env write policy. |
| Credentials | Generic persistence mechanics through a credential owner. | Secret classification, backend selection, redaction policy, token lifecycle. |
| Cache policy | Namespace routing and persistence mechanics. | Eviction policy, freshness policy, user-visible cleanup policy. |

Foundation must not import Configuration stores or know concrete setting keys.

## 4. Non-Overlap With Toolchain

Toolchain owns external tools and runtime composition. Foundation can persist and
register toolchain-owned records, but it must not interpret tool behavior.

| Toolchain concern | Foundation may provide | Must stay in Toolchain |
|---|---|---|
| Toolchain catalog | Record persistence, registry entries, workspace scope. | Discovery, install, version resolution, active selection, executable resolution. |
| Tool cache/state paths | Namespace routing through `resource-coordinator`. | Cache policy, artifact layout, provenance checks, cleanup decisions. |
| Runtime status | Generic record persistence and foundation diagnostics capture. | Health meaning, recovery actions, degraded-mode semantics, runtime launch behavior. |
| IO conversion | Nothing beyond generic persistence if requested. | Encoder, decoder, protocol, shell runtime, terminal runtime. |

Foundation must not download tools, verify tool artifacts, select compilers,
launch processes, encode protocol payloads, or decode tool output.

## 5. Non-Overlap With Environment

Environment owns system compatibility. Foundation may call Environment Platform
Manager surfaces, but it must not bypass them.

| Environment concern | Foundation may do | Must stay in Environment |
|---|---|---|
| File system access | Use File System Manager as a persistence backend for DataStore. | Path compatibility, file watching, read/write/delete/list/copy/move implementations. |
| Resource locations | Ask Resource Manager for app/cache/state/temp/runtime roots through Resource Coordinator. | OS facts, storage facts, cleanup execution, quota/resource management. |
| Process, shell, PTY, network, clipboard, notifications | No direct ownership. | Manager APIs, platform adapter use, platform context consumption, system calls. |
| Platform facts | No direct ownership. | Platform Detector, Platform Context, Platform Adapter, Platform Manager. |

The forbidden path is:

```text
Foundation -> Platform Adapter / Platform Context / Platform Detector / OS API
```

The allowed path is:

```text
Foundation -> Environment / Platform Manager
```

## 6. Foundation Admission Gate

Every new Foundation module must pass this gate.

| Question | Required answer |
|---|---|
| Is the mechanism needed by at least two upper layers? | Yes. |
| Can it work without knowing the meaning of stored, registered, or scoped data? | Yes. |
| Can it be tested without Styio syntax, external tool installation, UI rendering, or extension activation? | Yes. |
| Does it depend only on Foundation peers or Environment Platform Manager surfaces? | Yes. |
| Can Configuration and Toolchain change their policies without changing it? | Yes. |
| Would moving it to Configuration, Toolchain, Service, Interaction, Appearance, Extension, or Environment be more semantically precise? | No. |

If any answer fails, the module must stay in the owning layer.

## 7. Rejected Foundation Names

Do not add these directories under `foundation/`:

```text
configuration-store/
credential-datastore/
toolchain-manager/
encoder-decoder/
shell-runtime/
terminal-runtime/
file-system-manager/
process-manager/
shell-manager/
pty-manager/
network-manager/
resource-manager/
system-resources/
```

Correct ownership:

| Rejected name | Correct owner |
|---|---|
| `configuration-store` | Environment / Configuration |
| `credential-datastore` | Environment / Configuration / Credential DataStore |
| `toolchain-manager`, `encoder-decoder`, `shell-runtime`, `terminal-runtime` | Environment / Toolchain |
| `file-system-manager`, `process-manager`, `shell-manager`, `pty-manager`, `network-manager`, `resource-manager` | Environment / Platform Manager |
| `system-resources` | Do not use. Split into Foundation `resource-coordinator` and Environment `resource-manager`. |

## 8. Implementation Acceptance

A Foundation implementation is acceptable only when it proves mechanics without
upper-layer meaning.

| Foundation service | Required proof style |
|---|---|
| DataStore | Record IO, schema states, migrations, atomic updates, namespace isolation. |
| DataStore Owner | Owner metadata, namespace access control, state-family boundaries. |
| Registry | Registration, lookup, filtered listing, lifecycle state, manifest projection without runtime values. |
| Workspace | Workspace identity, lifecycle sequencing, scoped service container boundaries. |
| Resource Coordinator | Namespace routing and budget handoff through a fake or manager-backed Resource Manager. |
| Lifecycle Coordinator | Ordering, idempotency, reload, shutdown, disposal. |
| Lock Service | Same-record serialization and conflict behavior. |
| Event Bus | Subscription, publication, disposal. |
| Diagnostics Sink | Infrastructure health recording and filtering. |

Tests must not require a real Styio compiler, tool installation, product UI
rendering, extension activation, or OS-global mutation.

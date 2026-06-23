# Foundation / DataStore Owner

**Purpose:** Document the `docs/design/foundation/data-store-owner/` collection scope, ownership, and maintenance rules.
**Last updated:** 2026-05-17

`DataStore Owner` is the layer-local owner of one IDE state family.

It decides what state exists, who may mutate it, how it is scoped, and whether it is volatile, cached, persisted, or synced.

It does not directly read or write files.

This contract belongs under Foundation because it defines how upper layers use the Foundation DataStore API. The concrete owner still lives with the horizontal layer that owns the state.

## 1. Dependency Direction

```text
Layer Feature
  -> Layer DataStore Owner
    -> Foundation / DataStore API
      -> Environment / File System Manager
        -> System Specific File System Manager
          -> OS / File System
```

`DataStore` may depend on `File System Manager`.

`File System Manager` must not depend on `DataStore`.

## 2. Owners

| Layer | DataStore Owner | State family |
|---|---|---|
| Service Layer / User Service | User Service DataStore Owner | Local profile, recent projects, onboarding, preferences, sync metadata, and optional account/session state. |
| Appearance Layer | Appearance DataStore Owner | Theme selection, layout, visual mode, panel visibility, visual state. |
| Interaction Layer | Interaction DataStore Owner | Open documents, tabs, cursor, selection, dirty state, undo/redo metadata, focus state. |
| Service Layer | Service DataStore Owner | Service results, diagnostics, semantic tokens, hover payloads, completion snapshots, resolved references, remote-service payloads, and degraded service status. |
| Environment Layer / Toolchain and System Compatibility | Runtime DataStore Owner | Toolchain status, process status, shell sessions, task status, platform context, manager-local capability status, resource status, network availability. |
| Environment Layer / Extension | Extension DataStore Owner | Plugin enablement, provider state, capability registration, lifecycle state, permission grants. |
| Environment Layer / Configuration | Configuration DataStore Owner | Settings values, environment-variable overlays, workspace overrides, profile overrides, migrations, cache policy, endpoint policy. |
| Environment Layer / Fallback | Fallback DataStore Owner | Fallback status, fallback reasons, degraded-mode state, last-known-good availability. |

## 3. Owner Responsibilities

| Responsibility | Meaning |
|---|---|
| Schema ownership | Defines the state shape and schema state. |
| Mutation authority | Defines which commands, controllers, adapters, or managers may update the state. |
| Scope ownership | Defines whether the state is user, workspace, session, document, process, extension, or feature scoped. |
| Persistence policy | Defines whether the state is volatile, cached, persisted, or synced. |
| Migration policy | Defines how stored state moves across schema states. |
| Privacy policy | Classifies public, local-only, sensitive, secret, and telemetry-safe fields. |
| Subscription policy | Defines who may observe state changes. |
| Transaction policy | Defines whether updates must be atomic with related state keys. |
| Lifecycle policy | Defines load, initialize, update, clear, dispose, and migrate behavior. |

## 4. File-System Boundary

DataStore Owners must not call OS file APIs directly.

DataStore Owners also should not call `File System Manager` directly for IDE-owned state persistence.

Correct path:

```text
DataStore Owner -> Foundation / DataStore API -> Environment / File System Manager
```

Allowed direct `File System Manager` calls from feature layers are for user or project files, not IDE state persistence.

| Scenario | Correct dependency |
|---|---|
| Persist IDE settings, editor state, cache metadata, extension state, or fallback state. | DataStore API |
| Read or write a project source file. | File System Manager |
| Watch workspace files. | File System Manager |
| Read an env file referenced by configuration. | Configuration flow through File System Manager |
| Persist DataStore records to disk. | DataStore internals through File System Manager |

## 5. Non-Owners

Not every component needs a DataStore Owner.

Components should skip DataStore ownership when they are:

| Component type | Reason |
|---|---|
| Pure renderer | It renders state owned elsewhere. |
| Stateless adapter | It converts payloads without owning persisted state. |
| One-shot command | It performs an action and returns a result without owning state. |
| Temporary popup | It is ephemeral UI state unless it needs persistence or cross-component observation. |
| Derived view model | It can be recomputed from owner state. |

## 6. Rule Summary

```text
DataStore Owner owns state mutation rules.
Foundation DataStore owns persistence mechanics.
Environment File System Manager owns file-system access.
System Specific File System Manager owns platform implementation.
Foundation Lock Service owns same-record serialization.
```

## 7. Lock and Transaction Boundary

`DataStore Owner` is not the transaction primitive.

The owner may define that a mutation is allowed, required, or grouped by domain policy. The owner must not reimplement file locks or coordinate record-level IO directly.

Record-level serialization belongs to `FoundationDataStore`:

| Concern | Owner |
|---|---|
| Whether a feature may mutate a state family. | DataStore Owner |
| Which namespace, scope, workspace, and key are used. | DataStore Owner and caller contract |
| Serializing read/write/delete for the same record. | FoundationDataStore through FoundationLockService |
| Persisting migrated schema records after read-time migration. | FoundationDataStore while holding the same record lock |
| Cross-record domain transactions. | Owning layer policy, built on top of DataStore operations |
| User approval, security decision, permission prompts. | Owning feature layer, Configuration, or Environment as appropriate |

The practical rule:

```text
Owners decide who may change state.
DataStore decides how one persisted record is safely changed.
```

## 8. Current Implementation

The generic implementation is `FoundationDataStoreOwner`.

```text
FoundationDataStoreOwnerDescriptor
  -> ownerId
  -> layer
  -> stateFamily
  -> allowedNamespaces
  -> allowedNamespacePrefixes

FoundationDataStoreOwner
  -> FoundationDataStore
```

The owner wrapper does not understand setting schemas, language semantics, editor state, or toolchain behavior. It only records owner identity and enforces namespace access before delegating persistence to `FoundationDataStore`.

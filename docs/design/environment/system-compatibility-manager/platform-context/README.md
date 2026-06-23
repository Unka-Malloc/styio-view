# Platform Context

**Purpose:** Document the `docs/design/environment/system-compatibility-manager/platform-context/` collection scope, ownership, and maintenance rules.
**Last updated:** 2026-05-17

`Platform Context` is the singleton configuration object for platform knowledge inside Vityo. It is mapped from real configuration files and composes the platform fact documents used by system-facing modules.

`File System Facts`, `Shell Facts`, `Process Facts`, `Resource Facts`, `Network Facts`, `Clipboard Facts`, `Notification Facts`, `Local Service Facts`, and `PTY Facts` are not separate global stores. They are composable sections inside `Platform Context`.

Current implementation anchors:

```text
frontend/vityo_app/lib/src/view_ide/environment/system_compatibility/platform_context/platform_context_model.dart
frontend/vityo_app/lib/src/view_ide/environment/system_compatibility/platform_context/platform_context_controller.dart
frontend/vityo_app/lib/src/view_ide/environment/system_compatibility/platform_detector/platform_detector.dart
frontend/vityo_app/lib/src/view_ide/environment/system_compatibility/platform_context/platform_context_store.dart
```

`PlatformContextSnapshot` is the immutable fact snapshot. `PlatformContextController` owns loading, saving, applying fact-section updates, and accepting refreshes from `PlatformDetector`.

## 1. Position

```text
Platform Manager
  <- Platform Adapter
    <- Platform Context
      <- Platform Detector / Probers
```

The configuration materialization direction is:

```text
Configuration files / persisted context files
  -> Platform Context Loader
    -> Platform Context singleton
      -> Platform Adapter
        -> Platform Manager
```

The probing refresh direction is:

```text
OS / Runtime / Host APIs
  -> Platform Detector / Probers
    -> File System Facts / Shell Facts / other fact sections
      -> PlatformDetector.detect()
        -> Platform Context Snapshot
          -> Platform Context Controller / Store
```

## 2. Responsibility

`Platform Context` owns platform fact storage and composition. It does not probe the platform by itself and it does not execute platform operations.

| Responsibility | Meaning |
|---|---|
| Singleton access | Provide one logical platform context for the current Vityo runtime scope. |
| Configuration mapping | Materialize platform facts from real configuration files or persisted context files. |
| Fact composition | Combine all system facts into one immutable snapshot object. |
| Snapshot access | Expose immutable snapshots to adapters and upper modules. |
| Source tracking | Preserve fact source, certainty, scope, freshness, and target id. |
| Refresh acceptance | Accept fact updates produced by `Platform Detector` probers. |

Current responsibility split:

| Artifact | Owns | Must not own |
|---|---|---|
| `PlatformDetector` | Probe orchestration and snapshot composition. | Storage, overrides, manager creation, operation execution. |
| `PlatformContextSnapshot` | Immutable normalized facts. | Probing, persistence, policy decisions. |
| `PlatformContextController` | Load/save lifecycle, refresh acceptance, fact-section replacement, overrides. | Raw OS probing and system operations. |
| `PlatformContextStore` | Persistence boundary for snapshots. | Fact interpretation or manager behavior. |

## 3. Non-Responsibilities

| Not Owned By Platform Context | Owner |
|---|---|
| Raw OS probing | `Platform Detector` and concrete `Prober` modules. |
| File read/write/watch operations | `Platform Manager / File System Manager`. |
| Shell command execution | `Platform Manager / Shell Manager` and `Toolchain / Shell Runtime`. |
| Path normalization policy | `Platform Adapter` or the specific manager using adapted facts. |
| Shell profile selection | `Shell Configuration` plus `Shell Runtime`. |
| UI fallback and recovery flow | Interaction or Appearance modules. |
| Product settings ownership | `Configuration`, unless the setting is specifically platform context data. |

## 4. Logical Singleton Model

`Platform Context` should be treated as a logical singleton, not as an uncontrolled global mutable bag.

```text
PlatformContextSingleton
  currentSnapshot
  load(configSource)
  applyFactSection(section)
  applyOverride(override)
  snapshot() -> PlatformContextSnapshot
```

The singleton is scoped to the running Vityo application instance, workspace host, or automation session. Tests may create isolated instances, but production code should consume it through the agreed access point instead of constructing unrelated platform context objects.

## 5. Composable Shape

```text
PlatformContext
  metadata
  host
  fileSystem
  shell
  process
  resource
  network
  clipboard
  notification
  localService
  pty
  overrides
```

| Section | Contains |
|---|---|
| `metadata` | context version, schema state, loaded source files, generated time, freshness policy. |
| `host` | OS, architecture, runtime mode, app host, CI/test hints. |
| `fileSystem` | `File System Facts`, including path style, case sensitivity, watcher support, provider kind, permission hints. |
| `shell` | `Shell Facts`, including available shells, shell family hints, PTY support, login-shell support. |
| `process` | process spawning, signal, process group, and environment inheritance facts. |
| `resource` | memory, storage, temporary directory, and runtime limit facts. |
| `network` | proxy, offline/online, loopback, and service reachability facts. |
| `clipboard` | text clipboard availability, system clipboard availability, and memory fallback support. |
| `notification` | desktop notification availability and in-app fallback support. |
| `localService` | loopback HTTP service and ephemeral port support. |
| `pty` | pseudo-terminal backend, script utility support, raw mode, signal, and resize facts. |
| `overrides` | explicit user, workspace, or automation overrides that adjust fact interpretation. |

## 6. Fact Entry Shape

Each fact section should use the same entry shape so adapters can consume it uniformly.

```text
PlatformContextFact
  key
  value
  source
  scope
  certainty
  targetId
  detectedAt
  expiresAt
```

| Field | Meaning |
|---|---|
| `key` | Stable fact key, for example `filesystem.watchSupport` or `shell.availableShells`. |
| `value` | JSON-serializable fact value. |
| `source` | `config`, `prober`, `cache`, `override`, or `inferred`. |
| `scope` | `host`, `workspace`, `toolchain`, `shell`, `filesystem`, `process`, `network`, or `resource`. |
| `certainty` | `confirmed`, `inferred`, `unknown`, `unsupported`, or `stale`. |
| `targetId` | Optional host/workspace/toolchain target id. |
| `detectedAt` | When the fact was created or refreshed. |
| `expiresAt` | Optional freshness boundary. |

## 7. Configuration File Mapping

`Platform Context` should be reconstructable from persisted configuration data. The exact file location is a Configuration/DataStore policy, but the mapping should be explicit and machine-readable.

```text
platform-context.json
  -> PlatformContextLoader
    -> PlatformContextSnapshot
```

A persisted context file should not pretend that dynamic host facts are permanently true. Runtime-sensitive values should carry source and freshness metadata so a prober can refresh them when needed.

## 8. Composition Rules

| Rule | Meaning |
|---|---|
| Config baseline first | Load persisted platform context data before applying probe refreshes. |
| Probe refresh second | Let probers update fact sections without taking over singleton lifecycle. |
| Explicit override last | User/workspace/automation overrides should win when they are valid. |
| Keep sections separable | `File System Facts` and `Shell Facts` remain separate sections inside the same context. |
| Snapshot for consumers | Upper modules should read immutable snapshots rather than mutating the singleton directly. |
| No hidden policy | If a fact requires policy interpretation, that belongs in an adapter or manager. |

## 9. Relationship With Platform Detector

`Platform Detector` defines the global `Prober` behavior contract. Concrete probers emit fact sections. `Platform Context` stores and composes those sections.

```text
File System Prober   -> File System Facts
Shell Prober         -> Shell Facts
Process Prober       -> Process Facts
Resource Prober      -> Resource Facts
Network Prober       -> Network Facts
Clipboard Prober     -> Clipboard Facts
Notification Prober  -> Notification Facts
Local Service Prober -> Local Service Facts
PTY Prober           -> PTY Facts
                       -> PlatformDetector
                         -> PlatformContextSnapshot
                           -> PlatformContextController
```

## 10. Relationship With Platform Adapter

`Platform Adapter` consumes `Platform Context` snapshots and converts them into manager-ready compatibility inputs.

```text
Platform Context Snapshot
  -> Platform Adapter / PlatformAdapter
    -> File System Compatibility Inputs
    -> Shell Compatibility Inputs
    -> Process Compatibility Inputs
    -> Resource / Network / Clipboard / Notification / Local Service / PTY Compatibility Inputs
```

The adapter may interpret facts, but it should not mutate the singleton context as part of ordinary operation.

## 11. Design Rule

Use `Platform Context` when a module needs to know what the current platform looks like. Use `Platform Manager` when a module needs to do something on the platform.

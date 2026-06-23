# Resource Manager

**Purpose:** Document the `docs/design/environment/system-compatibility-manager/resource-manager/` collection scope, ownership, and maintenance rules.
**Last updated:** 2026-05-17

`Resource Manager` is the Platform Manager component for resource facts, resource locations, and resource budgets. It does not manage stored data and it does not perform general file-system operations.

The short rule is:

```text
FileSystem Manager = how to operate the file system
Resource Manager   = where resources should live and how much can be used
DataStore          = how application data is structured, schema-state tracked, and persisted
```

## 1. Position

```text
DataStore / Cache / Logs / Indexes / Toolchain
  -> Platform Manager / Resource Manager
    <- Platform Adapter / Resource Adapter
      <- Platform Context / Resource Facts
        <- Platform Detector / Resource Prober
```

When a caller needs to write files, the direction is:

```text
DataStore
  -> Resource Manager       # asks for location / budget
  -> FileSystem Manager     # performs read/write/create/delete
```

Not this:

```text
Resource Manager
  -> DataStore
```

## 2. Core Boundary

| Question | Owner |
|---|---|
| Where should app data live? | Resource Manager |
| Where should cache live? | Resource Manager |
| Where should temp/runtime/log files live? | Resource Manager |
| How much memory/storage/cpu should this subsystem use? | Resource Manager |
| How do we read/write/delete/list files? | FileSystem Manager |
| How do we encode schema, migrate records, and persist app data? | DataStore |
| Where are tokens and secrets stored? | Credential DataStore |

## 3. Direct System Interaction

Resource-related direct OS interaction should mostly happen in `Resource Prober`, not in upper consumers.

| System Interaction | Example | Purpose |
|---|---|---|
| CPU information | `Platform.numberOfProcessors`, `nproc` | Concurrency budget hints. |
| Temp root | `Directory.systemTemp.path`, `TMPDIR` | Temp location suggestion. |
| Home root | `HOME`, `USERPROFILE` | User-root location fact. |
| XDG data/cache/state/runtime | `XDG_DATA_HOME`, `XDG_CACHE_HOME`, `XDG_STATE_HOME`, `XDG_RUNTIME_DIR` | Linux app data/cache/state/runtime locations. |
| Memory information | `/proc/meminfo`, platform APIs | Memory budget hints. |
| Storage capacity | `statvfs`, `df`, platform APIs | Storage budget hints. |
| Sandbox/quota hints | Flatpak, Snap, hosted/web facts | Storage and runtime constraints. |

Resource Manager should expose these as normalized resource facts, locations, and budget hints. It should not mutate user data as part of resource probing.

## 4. Responsibilities

| Responsibility | Meaning |
|---|---|
| Resource facts | CPU count, temp root, home root, XDG roots, memory/storage hints. |
| Resource locations | App data, cache, state, log, temp, runtime, workspace cache locations. |
| Resource budgets | Memory, storage, cache, log, index, and task concurrency budget hints. |
| Cleanup candidates | Identify which locations are safe candidates for cleanup. |
| Quota hints | Indicate sandbox or hosted limits when known. |
| Compatibility normalization | Hide OS differences in resource path conventions. |

## 5. Non-Responsibilities

| Not Owned By Resource Manager | Correct Owner |
|---|---|
| Read file | FileSystem Manager |
| Write file | FileSystem Manager |
| Create directory | FileSystem Manager |
| Delete file/cache/log directory | FileSystem Manager plus the owning subsystem |
| List directory contents | FileSystem Manager |
| Compute real directory size by traversal | FileSystem Manager or the owning cache/data subsystem |
| Store schema or migrate data | DataStore |
| Persist user configuration | Configuration Store / DataStore |
| Persist tokens/secrets | Credential DataStore |
| Notify user about cleanup | Notification Manager / UI |

## 6. Four-Layer Foundation

```text
Platform Manager / Resource Manager
  <- Platform Adapter / Resource Adapter
    <- Platform Context / Resource Facts
      <- Platform Detector / Resource Prober
```

| Layer | Module | Responsibility |
|---|---|---|
| Platform Detector | `Resource Prober` | Reads raw system resource signals. |
| Platform Context | `Resource Facts` | Stores normalized resource facts. |
| Platform Adapter | `Resource Adapter` | Converts facts into resource locations and budgets. |
| Platform Manager | `Resource Manager` | Exposes resource location and budget queries. |

## 7. Resource Facts

Suggested shape:

```text
ResourceFacts
  targetId
  operatingSystem
  distributionId
  architecture
  processorCount
  homePath
  tempRoot
  xdgDataHome
  xdgCacheHome
  xdgStateHome
  xdgRuntimeDir
  memoryTotalBytes
  memoryAvailableBytes
  storageAvailableBytes
  sandboxKind
  quotaKind
  detectedAt
```

Facts describe the current host or target. They should not imply that a directory has already been created.

## 8. Resource Locations

Suggested location model:

```text
ResourceLocation
  kind
  path
  scope
  createPolicy
  cleanupPolicy
  quotaHint
```

Example kinds:

| Kind | Example Linux Location |
|---|---|
| `appData` | `$XDG_DATA_HOME/vityo` or `~/.local/share/vityo` |
| `cache` | `$XDG_CACHE_HOME/vityo` or `~/.cache/vityo` |
| `state` | `$XDG_STATE_HOME/vityo` or `~/.local/state/vityo` |
| `log` | `$XDG_STATE_HOME/vityo/logs` |
| `temp` | `/tmp/vityo-*` or `$TMPDIR/vityo-*` |
| `runtime` | `$XDG_RUNTIME_DIR/vityo` |
| `workspaceCache` | workspace-local or user-cache scoped location |

Resource Manager returns these locations. It does not create them. Creation is a FileSystem Manager operation.

## 9. Resource Budgets

Suggested budget model:

```text
ResourceBudget
  kind
  softLimitBytes
  hardLimitBytes
  source
  scope
```

Example budgets:

| Budget | Consumer |
|---|---|
| `indexMemory` | Language service / semantic index. |
| `cacheStorage` | DataStore / cache owners. |
| `logStorage` | Logging subsystem. |
| `toolchainStorage` | Toolchain manager. |
| `taskConcurrency` | Process/task runner. |

Budgets are hints unless a platform explicitly provides hard quota facts.

## 10. Relationship With FileSystem Manager

Resource Manager does not perform file operations. It only returns locations and budgets.

Correct flow:

```text
location = resourceManager.appDataLocation(namespace)
fileSystemManager.createDirectory(location.path)
fileSystemManager.writeText(filePath, content)
```

Incorrect flow:

```text
resourceManager.writeText(filePath, content)
resourceManager.deleteCache(namespace)
```

Current implementation note: if a Resource Manager API creates a temp directory directly, that API is temporary and should be replaced by a location allocation API plus FileSystem Manager creation.

Current failure handling exposes `ResourceOperationFailure` through manager-local `classifyFailure(...)`. This classifies unsupported resource APIs, permission-denied resource access, resource-limit failures such as no available storage, unavailable resource locations, and unknown failures without adding a global resource policy layer.

## 11. Relationship With DataStore

DataStore consumes Resource Manager. Resource Manager must not know DataStore schema, records, migrations, or codecs.

```text
DataStore
  -> Resource Manager   # asks where data should live
  -> FileSystem Manager # persists encoded records
```

DataStore owns:

| DataStore Concern | Reason |
|---|---|
| Namespace | Data ownership boundary. |
| Schema | Data shape and version. |
| Migration | Version upgrade. |
| Codec | JSON/binary encoding. |
| Transaction/atomicity | Data write behavior. |

Resource Manager owns none of these.

## 12. Relationship With Credential DataStore

Credential DataStore is separate from ordinary DataStore and Resource Manager.

```text
Credential DataStore
  -> owns secret values
  -> may ask Resource Manager for safe backend location only if using a local backend
  -> must not expose secret values through Resource Manager
```

Ordinary configuration should store credential references only. Secret values stay in Credential DataStore or a future OS keychain backend.

## 13. First Compatibility Target

For Linux Debian ARM:

| Resource | Expected Source |
|---|---|
| CPU count | `Platform.numberOfProcessors` or `nproc`. |
| temp root | `Directory.systemTemp.path` / `TMPDIR`. |
| home root | `HOME`. |
| app data root | `XDG_DATA_HOME` or `~/.local/share/vityo`. |
| cache root | `XDG_CACHE_HOME` or `~/.cache/vityo`. |
| state root | `XDG_STATE_HOME` or `~/.local/state/vityo`. |
| runtime root | `XDG_RUNTIME_DIR` when available. |
| memory facts | `/proc/meminfo` or system API. |
| storage facts | `statvfs`, `df`, or system API. |

## 14. Design Rule

If the operation changes files, it belongs to `FileSystem Manager` or the owning subsystem. If the operation decides where something should live or how much resource it may consume, it belongs to `Resource Manager`.

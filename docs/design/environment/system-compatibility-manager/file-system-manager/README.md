# File System Manager Vertical Flow View

**Purpose:** Record the conceptual vertical flow from OS/file-system primitives to Vityo upper-layer file operations while keeping implementation modules in horizontal layers.

**Last updated:** 2026-05-17

**Status:** Draft for review

## 1. Reduced Vertical Flow

The File System Manager line is ordered from bottom to top:

```text
OS / File System
  -> Platform Detector / File System Prober
  -> Platform Context / File System Facts
  -> Platform Adapter
  -> File System Manager interface
  -> System Specific File System Manager implementation
  -> Other Functionalities
```

This line intentionally avoids extra global gates between facts and the manager.

## 2. Core Rule

```text
Facts describe the environment.
Platform Manager is the top call surface. Platform Adapter converts facts into manager context below it.
File System Manager is the platform manager interface.
System Specific File System Manager implements the interface.
Upper features consume File System Manager only.
```

Permission checks, security-policy effects, resource pressure, provider constraints, and optional preflight are internal File System Manager concerns for file operations. They are not separate mandatory layers that callers must understand.

## 3. Layer Responsibilities

| Stage | Responsibility |
|-------|----------------|
| OS / File System | Native file-system behavior, path rules, permissions, mounts, symlinks, watchers, provider-specific behavior, and native failure modes. |
| Platform Detector / File System Prober | Platform Detector defines Prober behavior; File System Prober implements it for host and target file-system signals. |
| File System Prober | Probe file-system-specific facts such as case sensitivity, path style, symlink behavior, watcher support, newline defaults, provider capabilities, and root boundaries. |
| Platform Context | Store normalized host facts and target facts without executing file operations. |
| File System Facts | Store file-system facts such as URI scheme, path style, case sensitivity, watcher capability, symlink capability, encoding hints, and root boundaries. |
| Platform Adapter | Convert Platform Context and File System Facts into context required by the File System Manager interface. |
| File System Manager interface | Define the stable file-system API used by Vityo upper layers. It is the platform manager interface, not a concrete OS implementation. |
| System Specific File System Manager implementation | Implement the File System Manager interface for local, remote, browser-backed, virtual, or future hosted file systems. It owns provider routing, path/URI handling, operation execution, file content codec, optional local preflight, permission/error classification, policy-related error classification, and resource-aware failure reporting. |
| Other Functionalities | Editor, language, toolchain, extension, configuration, user surfaces, artifacts, package workflows, workspace features, and DataStore consume File System Manager. |

## 4. Interface And Implementation Split

`File System Manager` is the platform manager interface.

Concrete implementations are system specific:

| Implementation | Target |
|----------------|--------|
| LocalFileSystemManager | Local desktop filesystem. |
| RemoteFileSystemManager | Remote workspace filesystem. |
| BrowserFileSystemManager | Browser-backed or File System Access API-backed filesystem. |
| VirtualFileSystemManager | In-memory, generated, plugin-provided, or read-only virtual filesystem. |
| HostedFileSystemManager | Future hosted workspace filesystem. |

Rule:

```text
FileSystemManager = interface
LocalFileSystemManager / RemoteFileSystemManager / BrowserFileSystemManager / VirtualFileSystemManager = implementations
```

## 5. What Is Absorbed Into File System Manager

These concepts are no longer explicit runtime layers for file operations:

| Former concept | New placement |
|----------------|---------------|
| File System Compatibility | Internal compatibility strategy inside File System Manager. |
| File System Permission | Internal permission check and error classification inside File System Manager. |
| File System Security Policy | Internal policy-related error classification or local preflight inside File System Manager. |
| Operation Feasibility | Optional manager-local `canX` or preflight, only where useful. |
| Platform Adapter for file operations | Kept as the facts-to-manager-context adapter before the File System Manager interface. It does not implement file operations. |

## 6. File System Manager API Surface

Upper layers should use File System Manager for:

| API area | Examples |
|----------|----------|
| Path and URI | normalize, resolve, join, relative, URI conversion, scheme handling. |
| Containment | is within workspace root, safe output path, cache path containment. |
| Metadata | stat, exists, file type, mtime, size, readonly state, executable bit. |
| Content | read text, write text, read bytes, write bytes. |
| Directory | list, create, delete, rename, move, copy. |
| Watch | watch file, watch directory, recursive watch, polling fallback. |
| File content codec | text vs bytes, BOM handling, newline handling, file encoding hints, text normalization, and file content decode errors. |
| Provider | local provider, remote provider, virtual provider, browser-backed provider. |
| Local preflight | optional `canRead`, `canWrite`, `canDelete`, `canWatch`, and `canMove` for UI gating or high-risk operations. |
| Error classification | permission denied, read-only target, unsupported provider, invalid path, outside workspace, resource limit, stale target, and unknown failure. |

## 7. Internal Components

Each system-specific File System Manager implementation should be internally split by responsibility:

| Internal component | Responsibility |
|--------------------|----------------|
| Provider Router | Select local, remote, virtual, or browser-backed provider by URI scheme and target identity. |
| Path Resolver | Normalize, resolve, join, relativize, and convert between path and URI forms. |
| Workspace Boundary Guard | Enforce workspace-root containment, safe output paths, and cache path containment. |
| File Metadata API | Provide stat, exists, file type, mtime, size, readonly state, and executable bit. |
| File Content API | Provide read/write bytes and read/write text operations. |
| File Content Codec | Handle persisted file content concerns: text vs bytes, BOM, newline normalization, file encoding hints, and file content decode errors. |
| Directory API | Provide list, create, delete, rename, move, and copy operations. |
| Watch Service | Provide file watches, directory watches, recursive watches, provider watches, and polling fallback. |
| Local Preflight | Provide optional `canRead`, `canWrite`, `canDelete`, `canWatch`, and `canMove` only where UI gating or high-risk operations benefit. |
| Error Classifier | Convert provider and OS failures into structured file-system failures. |

## 8. Codec Boundary

File content codec is not the same as Toolchain IO encoding.

| Concern | Owner | Examples |
|---------|-------|----------|
| Persisted file content | File Content Codec | read text, write text, BOM handling, newline normalization, file encoding hints, decode errors. |
| External tool input | Toolchain Encoder | command arguments, environment overlays, stdin payloads, protocol request payloads. |
| External tool output | Toolchain Decoder | stdout, stderr, JSON, JSONL, diagnostics, artifact reports, terminal output, exit statuses. |

Rule:

```text
Toolchain encoding = process/protocol IO.
File content codec = persisted file content.
```

## 9. Default Execution Rule

Most file operations should execute directly and return structured results.

```text
caller -> File System Manager operation -> ok or structured error
```

Local preflight should be used only when it provides clear product value:

| Use preflight when | Example |
|--------------------|---------|
| UI must disable or hide an action before execution | Disable delete for read-only provider. |
| Operation is expensive or destructive | Preflight workspace delete, move, or bulk write. |
| User confirmation depends on feasibility | Show accurate warning before applying workspace edits. |
| Provider exposes cheap capability metadata | Use provider readonly/capability flags. |

Do not require every caller to ask permission or feasibility before calling the manager.

## 10. Upper-Layer Consumers

| Consumer | Uses File System Manager for |
|----------|------------------------------|
| Editor State Controller | Open, save, dirty-state reconciliation, and file-backed document state. |
| Workspace Edit Applier | Apply edits safely to open buffers and disk-backed files. |
| Service Layer | Bind documents to workspace identity and read language fixtures or snapshots. |
| Styio Result Adapter | Associate language results with document URI, revision, and snapshot identity. |
| Toolchain Manager | Discover binaries, read manifests, inspect lockfiles, write artifacts, apply executable bit for staged tools, and clean outputs. |
| Package Manager | Read package files, write lockfiles, install outputs, and inspect dependency state. |
| Extension Manager | Load plugin manifests and enforce file-access boundaries through manager results. |
| Configuration Store | Read workspace settings, profile settings, env files, and cache policy paths. |
| DataStore | Persist scoped IDE data where persistence policy allows. |
| Appearance / App Shell Surface | Display file errors, recovery guidance, blocked paths, and workspace status. |

## 11. Non-Bypass Rule

Upper layers must not bypass File System Manager for file-system behavior.

| Bypass | Problem |
|--------|---------|
| Calling OS file APIs directly | Skips provider routing, path normalization, containment checks, structured error classification, and resource handling. |
| Reading Platform Context directly for file decisions | Treats facts as behavior and bypasses manager strategy. |
| Calling Manager-local permission handling directly for file reads/writes | Checks authorization but does not perform provider-aware file operations. |
| Calling policy or preflight helpers directly for file reads/writes | Analyzes one concern but does not perform file operations. |
| Toolchain writing files directly | Skips workspace containment, artifact policy, cache policy, and provider differences. |

## 12. Error Classification

File System Manager should preserve distinct failure classes:

| Failure class | Meaning |
|---------------|---------|
| unsupportedProvider | The URI scheme or provider is unsupported. |
| invalidPath | The path or URI is malformed for the target. |
| outsideWorkspace | The operation violates workspace-root containment. |
| permissionDenied | The current actor is not authorized for the operation. |
| readOnlyTarget | The provider, mount, workspace, or target is read-only. |
| policyBlocked | The operation is blocked by sandbox, browser, enterprise, mount, quarantine, or runtime policy. |
| resourceLimitReached | Disk, watcher, fd, memory, quota, or cache pressure prevents the operation. |
| notFound | The target file or directory does not exist. |
| conflict | The operation conflicts with current file state. |
| staleTarget | Facts, provider state, or target identity are stale. |
| unknownFailure | The failure could not be classified safely. |

Current implementation exposes `FileSystemOperationFailure` and a manager-local `classifyFailure(...)` method. This keeps the first implementation compatible with existing throwing file APIs while giving upper layers a stable structured failure envelope:

```text
File operation throws provider/OS error
  -> FileSystemManager.classifyFailure(error, operation, target)
    -> FileSystemOperationFailure(kind, operation, target, sourceManager, message, recoveryHint)
```

This is not a global permission layer. The classification belongs to the concrete File System Manager that owns the operation.

The local implementation currently supports file and directory `copy` / `move` / `rename` with explicit overwrite behavior. `rename` is the upper-layer intent name for move-style file identity changes. A conflict is reported as the native operation failure first and can be classified through `classifyFailure(...)`.

The compatibility and manager surfaces also expose file URI conversion and containment helpers:

| API | Meaning |
|-----|---------|
| `toFileUri(path)` | Convert a normalized path to a `file:` URI when the provider supports file URIs. |
| `pathFromFileUri(uri)` | Convert a `file:` URI back to a normalized manager path. |
| `isWithin(childPath, parentPath)` | Check normalized path containment using the target path style and case-sensitivity rules. |

`FileSystemBoundaryGuard` is the current manager-local workspace/root containment helper. It uses `FileSystemManager.isWithin(...)` and produces `FileSystemOperationFailure(kind: outsideWorkspace)` when a target escapes the allowed root.

`FileSystemTextCodec` is the current persisted file-content codec. It handles UTF-8 BOM detection/removal, UTF-8 encode/decode, and newline normalization for file content. It must not be used for Toolchain stdout/stderr/protocol payloads.

`FileSystemProviderRouter` is the current provider-routing seed. It supports local bare paths and `file:` URIs, and returns `FileSystemOperationFailure(kind: unsupportedProvider)` for unsupported schemes. Remote, browser, virtual, and hosted providers still need concrete implementations before they become supported routes.

## 13. Open Questions

1. Should `File System Prober` be documented as a submodule under Platform Detector or under File System Manager?
2. Should remote and virtual file providers be first-class from the beginning or introduced after local desktop support?
3. Which `canX` APIs are worth exposing in the first implementation instead of relying on execute-and-classify behavior?

## Relationship With File System Prober

`File System Prober` is not part of `File System Manager`. It belongs to the global `Platform Detector` contract and only emits file-system facts.

`File System Manager` consumes adapted file-system facts and owns actual file-system operations, including read/write/list/watch/open/save-facing behavior exposed to upper layers.

## Relationship With Platform Context

`File System Manager` should not own global platform storage. It receives file-system compatibility inputs derived from `Platform Context`, especially the `fileSystem` fact section.

The lower-level chain is:

```text
File System Prober
  -> File System Facts
    -> Platform Context
      -> Platform Adapter
        -> File System Manager
```

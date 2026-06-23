# System Compatibility Manager

**Purpose:** Document the `docs/design/environment/system-compatibility-manager/` collection scope, ownership, and maintenance rules.
**Last updated:** 2026-05-17

## Platform Detector Contract

`Platform Detector` is the global interface preset for the detector layer. It does not mean one concrete detector implementation; it defines the behavior all concrete `Prober` modules must follow.

Concrete probers include:

| Prober | Responsibility | Output |
|---|---|---|
| `File System Prober` | Probe file-system capability and host file-system traits. | File system facts. |
| `Shell Prober` | Probe available shells and shell execution traits. | Shell facts. |
| `Process Prober` | Probe process spawning and signal traits. | Process facts. |
| `Network Prober` | Probe host/network reachability traits. | Network facts. |
| `Resource Prober` | Probe memory, storage, and temporary resource traits. | Resource facts. |
| `Clipboard Prober` | Probe text clipboard and fallback traits. | Clipboard facts. |
| `Notification Prober` | Probe desktop notification and in-app fallback traits. | Notification facts. |
| `Local Service Prober` | Probe loopback service and ephemeral port traits. | Local service facts. |
| `PTY Prober` | Probe pseudo-terminal backend traits. | PTY facts. |

All probers emit facts only. They must not choose product policy, execute workflows, mutate user state, select shell profiles, normalize file paths, or own manager behavior. See `platform-detector/README.md` for the full prober contract.


System Compatibility Manager is the Environment home for the system integration side.

Read the stack from bottom to top:

```text
Platform Manager        # top call surface for feature owners
  <- Platform Adapter
  <- Platform Context
  <- Platform Detector  # lowest raw probing layer
```

Equivalent facts-preparation direction:

```text
Platform Detector / Probers -> Platform Context -> Platform Adapter -> Platform Manager
```

Application callers call Platform Manager from above. Detector/Facts/Adapter prepare the manager context from below.

It does not contain a unified permission layer. Permission handling is local to the concrete manager that performs the operation.

## 1. Directory Rule

```text
system-compatibility-manager/
  README.md
  platform-detector/
    README.md
  platform-context/
    README.md
  file-system-manager/
    README.md
```

Future system-specific managers may be added here when they directly own system compatibility behavior, for example process, shell, network, resource, or browser-host compatibility.

## 2. Ordered System Integration Chain

| Step | Responsibility | Shell example |
|---|---|---|
| Platform Detector | Global interface preset for all Probers. | Defines Prober behavior, fact emission shape, certainty/source/scope rules, and forbidden behavior. Shell Prober and File System Prober implement this preset. |
| Platform Context | Carry normalized facts only. | Publish Shell Facts such as shell family hint, login-shell support, PTY support, quoting family, and script extension hints. |
| Platform Adapter | Convert facts into manager context. | Convert Shell Facts into Shell Manager invocation context. |
| Platform Manager | Top call surface. Expose stable manager interfaces and delegate to system-specific implementations. | Shell Manager quotes arguments, prepares shell invocation, handles cwd/env/stdin/stdout, and returns structured failures. |


## 2.1 Platform Detector And Probers

`Platform Detector` is the global interface preset for all Probers.

```text
Platform Detector
  File System Prober
  Shell Prober
  Process Prober
  Network Prober
  Resource Prober
  Clipboard Prober
  Notification Prober
  Local Service Prober
  PTY Prober
```

Each Prober probes one system domain and emits raw or partially normalized facts. `Shell Prober` detects system shell availability and raw shell capabilities. `File System Prober` detects raw file-system capabilities. Probers must not select active profiles, quote commands, execute commands, apply configuration, perform feature file operations, or render recovery UI.

Detailed detector contract: [platform-detector/README.md](./platform-detector/README.md)

## 3. Platform Manager Scope

`Platform Manager` is the top system-compatibility call surface and an interface category.

`PlatformManagerBundle` may aggregate concrete managers created from one `Platform Context`, but it must remain a thin bundle. It must not reimplement file-system, shell, process, resource, network, clipboard, notification, local-service, or PTY behavior.

`createDetectedPlatformManagerBundle` is the default top-of-stack construction path. It runs a `Platform Detector`, receives a `Platform Context`, adapts compatibility through `Platform Adapter`, and then creates the concrete managers from that context.

`PlatformManagerBundle.snapshot()` exposes a top-level status projection for upper layers and tests. It includes target id, context source, schema state, aggregate Linux/Debian/ARM compatibility, and the manager keys present in the bundle. It does not expose or reimplement manager behavior.

| Manager interface | Owns |
|---|---|
| File System Manager | File provider routing, URI/path handling, read/write/watch, file content codec, and structured file errors. |
| Shell Manager | Shell profile selection, quoting, command invocation shape, cwd/env/stdin/stdout handoff, PTY capability, and structured shell errors. |
| Process Manager | Process spawn, signal, exit-code, env process details, and process-level structured failures. |
| Network Manager | Proxy, TLS, offline, localhost, remote endpoint checks, and structured network errors. |
| Resource Manager | Memory, storage, watcher, fd, process-limit, cache-quota, and cleanup-pressure checks. |
| Clipboard Manager | Text clipboard reads/writes and memory fallback behavior. |
| Notification Manager | Desktop notification routing and in-app fallback records. |
| Local Service Manager | Loopback service startup and local endpoint lifecycle. |
| PTY Manager | Pseudo-terminal allocation, IO stream, resize, and interactive session lifecycle. |

## 4. Permission Rule

```text
No global permission-manager/ directory.
No shared Permission Manager runtime layer.
```

Permission checks belong inside the manager that executes or prepares the operation:

| Permission concern | Owning module |
|---|---|
| File read/write/create/delete/watch permission | File System Manager |
| Process spawn and executable permission | Process or Execution Manager |
| Shell command permission | Shell Manager or Execution Manager |
| Network endpoint permission | Network-capable manager or service connector owner |
| Extension activation permission | Extension Manager |
| Data persistence, sync, and privacy permission | DataStore owner or User Service privacy boundary |

## 5. Required Output Shape

Even without a global permission layer, managers must still report permission-related failures explicitly.

| Field | Meaning |
|---|---|
| `kind` | `permissionDenied`, `unsupported`, `notFound`, `conflict`, `resourceLimit`, `shellUnavailable`, `ptyUnsupported`, or another structured failure kind. |
| `operation` | The operation being attempted, such as file read, file write, shell quote, process spawn, or extension activation. |
| `target` | The path, command, shell profile, endpoint, provider, or resource being accessed. |
| `recoveryHint` | User-visible recovery guidance when available. |
| `sourceManager` | The manager that produced the failure. |

Current Process Manager implementation exposes `ProcessOperationFailure` through manager-local `failureFor(...)`. This classifies blocked, timed out, non-zero exit, and spawn-failed process results without turning process execution into a global permission layer.

Current Network Manager implementation exposes `NetworkOperationFailure` through manager-local `failureForText(...)` and `failureForBytes(...)`. This classifies unsupported network access, timeouts, HTTP status failures, TLS/certificate failures, host reachability failures, invalid URI failures, and unknown network failures.

Current Resource Manager implementation exposes `ResourceOperationFailure` through manager-local `classifyFailure(...)`. This classifies unsupported resource APIs, permission-denied resource access, resource-limit failures, unavailable locations, and unknown resource failures.

Current Shell Manager implementation exposes `ShellOperationFailure` through manager-local `failureFor(...)`. This classifies unsupported shell execution, timeouts, non-zero exits, spawn failures, and unknown shell failures.

Current PTY Manager implementation exposes `PtyOperationFailure` through manager-local `failureForSession(...)` and `failureForResize(...)`. This classifies unsupported sessions, start failures, resize unsupported, resize failures, and failed sessions.

Current Clipboard Manager implementation exposes `ClipboardOperationFailure` through manager-local `failureFor(...)`. This classifies blocked clipboard access and unknown clipboard failures.

Current Notification Manager implementation exposes `NotificationOperationFailure` through manager-local `failureFor(...)`. This classifies blocked notification delivery and unknown notification failures.

Current Local Service Manager implementation exposes `LocalServiceOperationFailure` through manager-local `classifyFailure(...)`. This classifies unsupported local-service APIs, permission-denied binds, unavailable ports, bind failures, and unknown local-service failures.

## 6. Rationale

A centralized permission layer or universal system facade adds latency and coupling without owning real operations. Concrete managers already know the target, facts, provider constraints, fallback path, and recovery options, so system compatibility behavior should remain local to operation-owning managers.

## Platform Context Rule

`Platform Context` replaces the old `Platform Facts` module name. The term `Facts` is still valid for component-level data such as `File System Facts` and `Shell Facts`, but the global storage/composition object is `Platform Context`.

`Platform Context` is a singleton configuration object mapped from real configuration files. It composes every system fact section and exposes snapshots to `Platform Adapter` and `Platform Manager`.

All component fact sections inside one `Platform Context` must use the same
`targetId` as the containing context snapshot. Detector output, loaded JSON, and
copied snapshots are normalized at the context boundary before adapters or
managers consume them.

```text
Platform Detector / Probers
  -> Platform Context target normalization
    -> Platform Adapter compatibility
      -> Platform Manager facts + compatibility consumption
```

This keeps manager behavior tied to one explicit platform target instead of
letting individual fact sections retain stale or probe-local target identities.

## PTY Manager Boundary

`PTY Manager` is the Platform Manager component for OS pseudo-terminal capability. It is separate from `Shell Manager`: shell modules own command semantics and quoting, while PTY modules own terminal device allocation, resize, raw input, and interactive session lifecycle.

Design document: [pty-manager/README.md](./pty-manager/README.md)

## Resource Manager Boundary

`Resource Manager` owns resource facts, resource locations, and resource budgets. It does not own `DataStore` and it does not perform general file-system operations. `DataStore` consumes Resource Manager for location/budget decisions and consumes `FileSystem Manager` for persistence operations.

Design document: [resource-manager/README.md](./resource-manager/README.md)

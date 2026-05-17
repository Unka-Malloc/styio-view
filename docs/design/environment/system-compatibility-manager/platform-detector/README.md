# Platform Detector

**Purpose:** Document the `docs/design/environment/system-compatibility-manager/platform-detector/` collection scope, ownership, and maintenance rules.
**Last updated:** 2026-05-17

`Platform Detector` is the global interface preset for the whole detector layer. It defines how every concrete `Prober` behaves before any platform fact is published upward.

It is not a feature manager and it is not a compatibility implementation. Its only job is to standardize bottom-level probing so `File System Prober`, `Shell Prober`, and future probers produce comparable facts.

Current implementation anchor:

```text
frontend/vityo_app/lib/src/view_ide/environment/system_compatibility/platform_detector/platform_detector.dart
```

`PlatformDetector.detect()` composes all concrete prober outputs into a `PlatformContextSnapshot`. It does not store the snapshot and it does not create any manager.

## 1. Position

```text
Platform Manager
  <- Platform Adapter
    <- Platform Context
      <- Platform Detector
         -> File System Prober
         -> Shell Prober
         -> Process Prober
         -> Network Prober
         -> Resource Prober
```

The direction above means upper layers consume prepared platform knowledge. The raw discovery direction is:

```text
OS / Runtime / Host APIs
  -> Platform Detector / Probers
    -> Platform Context
      -> Platform Adapter
        -> Platform Manager
```

## 2. Global Prober Contract

Every `Prober` under `Platform Detector` must follow the same contract.

| Contract Area | Requirement |
|---|---|
| Ownership | A prober owns one system capability domain only. |
| Output | A prober emits platform context, not product behavior. |
| Shape | Every fact should carry a stable key, value, source, scope, certainty, target id when relevant, and detection time. |
| Failure mode | A prober should prefer `unknown`, `unsupported`, `inferred`, or `stale` facts over throwing into upper layers, unless the probe itself cannot safely run. |
| Side effects | A prober must avoid persistent side effects. It can inspect; it should not configure, repair, execute user workflows, or mutate user state. |
| Policy | A prober must not choose product policy, fallback policy, UI behavior, active shell, path strategy, or toolchain version. |
| Consumption | `Platform Context` records prober output; `Platform Adapter` interprets facts for a manager; `Platform Manager` exposes the usable system-facing API. |

## 3. Prober Matrix

| Prober | Domain | Emits Facts About | Must Not Do |
|---|---|---|---|
| File System Prober | File system capability | path style hints, case sensitivity, watcher support, file system provider hints, cheap permission signals | read/write product files, normalize project paths, choose watcher strategy, own editor file binding |
| Shell Prober | Shell capability | available shells, executable paths, shell family/version hints, PTY support, login-shell capability | select active shell, quote commands, execute user commands, apply shell configuration |
| Process Prober | Process capability | spawn support, signal support, process group support, environment inheritance hints | start product tasks, supervise commands, enforce task policy |
| Network Prober | Network capability | proxy hints, online/offline hints, loopback support, TLS/backend reachability hints | download toolchains, authenticate services, retry product requests |
| Resource Prober | Resource capability | memory/storage/temporary-directory limits and availability hints | allocate long-lived storage, enforce quotas, clear user data |

## 4. File System Prober Boundary

`File System Prober` belongs to `Platform Detector`. It exists so the rest of Vityo can reason about file-system differences before a higher-level file operation is attempted.

It may detect:

| Fact Key Example | Meaning |
|---|---|
| `filesystem.pathStyle` | POSIX-like, Windows-like, virtual, or hosted path conventions. |
| `filesystem.caseSensitivityHint` | Whether paths are likely case-sensitive in the target scope. |
| `filesystem.watchSupport` | Whether recursive watch, polling, or no watch is available. |
| `filesystem.providerKind` | Local, remote, browser sandbox, virtual, or hosted provider hint. |
| `filesystem.permissionPreflight` | Cheap, non-invasive permission signal when available. |

It must not own file reads, writes, document binding, path normalization strategy, watch lifecycle, or recovery UI. Those belong above the detector chain.

## 5. Shell Prober Boundary

`Shell Prober` belongs to `Platform Detector`. It detects what shell capabilities exist in the current host or execution target.

It may detect:

| Fact Key Example | Meaning |
|---|---|
| `shell.availableShells` | Shell executables that appear available. |
| `shell.defaultShellHint` | Host-provided default shell hint, if cheaply available. |
| `shell.familyHint` | bash, zsh, fish, powershell, cmd, sh, or unknown. |
| `shell.versionHint` | Best-effort version string. |
| `shell.ptySupported` | Whether PTY-backed interaction appears available. |
| `shell.loginShellSupported` | Whether login-shell mode appears possible. |

It must not choose the active shell profile, quote commands, execute commands, mutate shell rc files, or persist Shell Runtime configuration. Those belong to `Shell Configuration`, `Shell Runtime`, and `Shell Manager`.

## 6. Interface Shape

The concrete implementation language can vary, but the architectural interface should remain stable:

```text
PlatformDetector
  detect(targetId) -> PlatformContextSnapshot

PlatformProber
  id
  domain
  supportedScopes
  probe(context) -> PlatformFact[]
```

`probe(context)` should receive only the minimum context needed to inspect the target safely, for example host mode, workspace target, execution target, and configured probe budget.

A platform fact should follow the repository-wide fact shape:

```text
PlatformFact
  key
  value
  source
  scope
  certainty
  targetId
  detectedAt
  expiresAt
```

Current Dart mapping:

| Design contract | Current Dart artifact |
|---|---|
| Platform Detector | `PlatformDetector` |
| Prober-backed detector | `ProbingPlatformDetector` |
| Test/static detector | `StaticPlatformDetector` |
| File System Prober | `FileSystemProber` |
| Shell Prober | `ShellProber` |
| Process Prober | `ProcessProber` |
| Resource Prober | `ResourceProber` |
| Network Prober | `NetworkProber` |
| Clipboard Prober | `ClipboardProber` |
| Notification Prober | `NotificationProber` |
| Local Service Prober | `LocalServiceProber` |
| PTY Prober | `PtyProber` |
| Emitted context | `PlatformContextSnapshot` |
| Context persistence owner | `PlatformContextController`, not `PlatformDetector` |

## 7. Design Rule

If a module needs to know whether a system capability exists, create or extend a `Prober`. If a module needs to perform the system operation, implement it in the relevant `Platform Manager` or a system-specific manager behind it.

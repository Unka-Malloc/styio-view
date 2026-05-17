# Platform Adapter

**Purpose:** Document the `docs/design/environment/system-compatibility-manager/platform-adapter/` collection scope, ownership, and maintenance rules.
**Last updated:** 2026-05-17

`Platform Adapter` converts immutable `Platform Context` facts into manager-ready compatibility inputs.

It is not a feature layer and it does not execute platform operations. Its job is to keep fact interpretation out of `Platform Context` and to keep manager factories from each inventing their own context conversion path.

Current implementation anchor:

```text
frontend/vityo_app/lib/src/view_ide/environment/system_compatibility/platform_adapter/platform_adapter.dart
```

## 1. Position

```text
Platform Manager
  <- Platform Adapter
    <- Platform Context
      <- Platform Detector
```

Operational direction:

```text
PlatformContextSnapshot
  -> PlatformAdapter
    -> PlatformCompatibilitySnapshot
      -> File System Manager
      -> Shell Manager
      -> Process Manager
      -> Resource Manager
      -> Network Manager
      -> Clipboard Manager
      -> Notification Manager
      -> Local Service Manager
      -> PTY Manager
```

## 2. Responsibilities

| Responsibility | Meaning |
|---|---|
| Fact conversion | Convert `FileSystemFacts`, `ShellFacts`, `ProcessFacts`, `ResourceFacts`, `NetworkFacts`, `ClipboardFacts`, `NotificationFacts`, `LocalServiceFacts`, and `PtyFacts` into compatibility inputs. |
| Compatibility grouping | Provide one `PlatformCompatibilitySnapshot` for manager factories. |
| Domain adapter access | Expose domain adapters such as `FileSystemAdapter`, `ShellAdapter`, and `ProcessAdapter`. |
| Manager input stability | Keep manager constructors and factories tied to compatibility inputs instead of raw context interpretation. |

## 3. Non-Responsibilities

| Not Owned By Platform Adapter | Owner |
|---|---|
| Raw OS probing | Platform Detector / Probers |
| Fact persistence and overrides | Platform Context Controller / Store |
| File reads, writes, watches | File System Manager |
| Shell command execution | Shell Manager and Toolchain / Shell Runtime |
| Process execution | Process Manager |
| Toolchain selection and runtime composition | Toolchain |
| Product fallback, UI recovery, and user approval | Interaction / Appearance / feature owner |

## 4. Current Dart Mapping

| Design contract | Current artifact |
|---|---|
| Platform Adapter | `PlatformAdapter` |
| Grouped compatibility output | `PlatformCompatibilitySnapshot` |
| File-system compatibility input | `FileSystemCompatibility` |
| Shell compatibility input | `ShellCompatibility` |
| Process compatibility input | `ProcessCompatibility` |
| Resource compatibility input | `ResourceCompatibility` |
| Network compatibility input | `NetworkCompatibility` |
| Clipboard compatibility input | `ClipboardCompatibility` |
| Notification compatibility input | `NotificationCompatibility` |
| Local service compatibility input | `LocalServiceCompatibility` |
| PTY compatibility input | `PtyCompatibility` |

## 5. Design Rule

Use `Platform Adapter` when a module needs manager-ready compatibility inputs from platform facts.

Use `Platform Manager` when a module needs to perform a system operation.

Use `Platform Context` when a module needs an immutable fact snapshot without manager behavior.

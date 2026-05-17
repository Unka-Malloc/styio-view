# Environment

**Purpose:** Document the `docs/design/environment/` collection scope, ownership, and maintenance rules.
**Last updated:** 2026-05-17

Environment owns system and runtime environment capabilities. It has seven conceptual parts.

System integration side, from bottom to top:

```text
Platform Manager        # top call surface for upper Environment/Application users
  <- Platform Adapter   # facts-to-manager-context adapter
  <- Platform Context     # normalized facts contract
  <- Platform Detector  # lowest raw probing layer
```

Equivalent facts-preparation direction:

```text
Platform Detector / Probers -> Platform Context -> Platform Adapter -> Platform Manager
```

Application callers such as Toolchain / Shell Runtime call the manager from above; Detector/Facts/Adapter prepare manager context from below.

Application-side environment modules:

```text
Configuration
Toolchain
Extension
```

The application-side environment modules have no strict global order. Configuration, Toolchain, and Extension may reference each other through explicit contracts, but none of them should become a universal parent layer.

Shared application mechanics such as DataStore API, DataStore Owner, Registry, Workspace scope, Resource Coordinator, Lifecycle Coordinator, Lock Service, Event Bus, and Diagnostics Sink belong to [Foundation](../foundation/README.md), not Environment.

Configuration and Credential persistence must enter Foundation through `FoundationDataStoreOwner`. Configuration owns setting semantics and credential policy; Foundation only provides the DataStore mechanics.

Only boundary or complex environment modules get their own README. Ordinary intended managers are recorded here until their design becomes concrete enough to justify a separate document.

## Seven Environment Parts

| Part | Responsibility | Directory owner |
|---|---|---|
| Platform Detector | Global interface preset and concrete detector facade for all Probers. Defines Prober behavior, runs raw probing, and composes a `PlatformContextSnapshot`; it does not store facts or create managers. | `system-compatibility-manager/platform-detector/` |
| Platform Context | Normalized facts contract for File System, Shell, Process, Resource, Network, Clipboard, Notification, Local Service, and PTY facts. Facts do not execute behavior. The controller loads, saves, updates, and refreshes snapshots through `PlatformDetector`. | `system-compatibility-manager/platform-context/` |
| Platform Adapter | Converts facts into manager context. It adapts facts, not feature behavior. | `system-compatibility-manager/` |
| Platform Manager | Top system-compatibility call surface. Stable manager interfaces such as File System Manager, Shell Manager, Process Manager, Network Manager, and Resource Manager. | `system-compatibility-manager/` plus concrete manager docs |
| Configuration | IDE-owned settings, Shell Configuration, environment overlays, user/workspace preferences, defaults, and migrations. | `configuration-store/` |
| Toolchain | Tool discovery, installation, selection, version binding, process context, encoder/decoder support, and Shell Runtime. | `toolchain-manager/` and `shell-runtime/` |
| Extension | Extension lifecycle, manifests, activation, contribution, and extension-local permission decisions. | `extension-manager` |

## Module Inventory

| Module | Responsibility | Separate doc |
|---|---|---|
| `configuration-store/environment-variable-configuration/` | IDE-owned environment overlays and configuration persistence rules. | Yes |
| `configuration-store/shell-configuration/` | Shell Runtime configuration: default shell profile, workspace policy, env overlay references, and fallback preferences. | Yes |
| `system-compatibility-manager/` | Platform Detector/Facts/Adapter/Manager contracts, system-specific managers, and manager-local permission handling. | Yes |
| `system-compatibility-manager/platform-detector/` | Global Platform Detector interface preset for File System Prober, Shell Prober, and future Probers. | Yes |
| `system-compatibility-manager/platform-context/` | Facts-only platform context, including all system compatibility fact sections. | Yes |
| `system-compatibility-manager/platform-adapter/` | Global Platform Adapter facade that converts `PlatformContextSnapshot` into manager-ready compatibility inputs. | Yes |
| `system-compatibility-manager/file-system-manager/` | File-system provider routing, URI/path handling, read/write/watch, file content codec, and structured errors. | Yes |
| `toolchain-manager/styio-toolchain-management/` | Styio toolchain discovery, installation, selection, version binding, process context, and capability handshake support. | Yes |
| `shell-runtime/` | Toolchain-bound shell execution profile coordination through Shell Facts, Shell Adapter, and Shell Manager. | Yes |
| `extension-manager` | Extension lifecycle, manifests, activation, contribution, and extension-local permission decisions. | No |
| `fallback-registry` | Global fallback registration only; behavior remains local to feature owners. | No |
| `execution-manager` | Build/run/test/task execution semantics, process lifecycle coordination, launch-time env resolution, and redacted execution status metadata. | No |

## Boundary

Environment must not own Appearance rendering, Interaction behavior, or Service-level language truth.

## Platform Detector Rule

`Platform Detector` is the global interface preset for all low-level system probers. `File System Prober`, `Shell Prober`, and later process/network/resource probers must follow this contract and emit facts only.

`PlatformDetector.detect()` may orchestrate all probers and compose a `PlatformContextSnapshot`. It must not persist the snapshot, interpret product policy, or expose platform operations.

Operational behavior stays above the detector chain: facts are stored by `Platform Context`, interpreted by `Platform Adapter`, and exposed through `Platform Manager` or a system-specific manager.

## Platform Context Rule

`Platform Context` is the environment-side singleton configuration object for platform knowledge. It is mapped from real configuration files and composes component fact sections such as `File System Facts`, `Shell Facts`, `Process Facts`, `Resource Facts`, `Network Facts`, `Clipboard Facts`, `Notification Facts`, `Local Service Facts`, and `PTY Facts`.

The environment system-integration chain is therefore:

```text
Platform Manager
  <- Platform Adapter
    <- Platform Context
      <- Platform Detector / Probers
```

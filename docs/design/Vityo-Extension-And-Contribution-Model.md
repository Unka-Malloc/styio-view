# Vityo Extension and Contribution Model

**Purpose:** Define Vityo's Styio-native extension and contribution model — how modules declare capabilities, how contributions are routed, and how the extension host isolates and activates extensions. This is NOT a VS Code extension API clone.

**Owner:** Extension/module architecture owner (`CODEOWNERS` → module_host domain)
**Last updated:** 2026-06-24

---

## 1. Design Principles

1. **Styio-first, not VS Code-compatible.** Vityo extensions use a Styio-native manifest schema and typed contribution model. No attempt is made to load or run VS Code extensions.
2. **Capability-gated activation.** Extensions declare their required capabilities; the host activates them only when the capability matrix permits.
3. **Isolated execution.** Extensions run in an isolated context; they cannot directly access the file system, network, or UI tree without declared permissions.
4. **Typed contributions, not string-based.** Contribution points are typed Dart classes, not JSON string identifiers.
5. **Staged updates.** Extensions support staged update cycles: verify → stage → activate → rollback on failure.

## 2. Extension Manifest

### 2.1 Manifest Schema

Extensions declare their identity, capabilities, contributions, and requirements in a manifest:

```dart
class ExtensionManifest {
  final int schemaVersion;         // Manifest schema version
  final String id;                 // Unique extension ID (e.g., "styio.cpp-tools")
  final String name;               // Human-readable name
  final String version;            // SemVer
  final List<String> activationEvents;  // e.g., ["onLanguage:cpp", "onWorkspaceOpen"]
  final List<ExtensionContribution> contributions;  // Typed contributions
  final List<String> requiredCapabilities;  // e.g., ["language.cpp", "toolchain.clang"]
  final ExtensionIsolation isolation;  // process | same-process | hosted
}
```

Reference: `frontend/vityo_app/lib/src/view_ide/module_host/extension_manifest_contract.dart`

### 2.2 Manifest Validation

- Schema version must be parseable and <= current host version.
- ID must be unique within the installed extension set.
- Required capabilities must be satisfiable by the current capability matrix.
- Contributions must be valid for their declared contribution point type.

## 3. Contribution Model

### 3.1 Contribution Points

Vityo defines typed contribution points, each owned by a domain:

| Contribution Point | Domain Owner | Dart Type | Example |
|-------------------|-------------|-----------|---------|
| `commands` | `commands/` | `ExtensionCommandContribution` | Register a command in palette |
| `languages` | `language/` | `ExtensionLanguageContribution` | Register a language service |
| `agent_providers` | `agent/` | `ExtensionAgentProviderContribution` | Register an AI provider |
| `agent_tools` | `agent/` | `ExtensionAgentToolContribution` | Register an agent tool |
| `debug_adapters` | `debugger/` | `ExtensionDebugContribution` | Register a debug adapter |
| `toolchains` | `toolchain/` | `ExtensionToolchainContribution` | Register a toolchain |
| `themes` | `theme/` | `ExtensionThemeContribution` | Register a theme |
| `views` | `view_render/extensions/` | `ExtensionViewContribution` | Register a UI view |
| `runtime_tasks` | `runtime/` | `ExtensionRuntimeTaskContribution` | Register a runtime task |

### 3.2 Contribution Router

The `ExtensionContributionRouter` (at `frontend/vityo_app/lib/src/view_ide/module_host/extension_contribution_router.dart`) routes contributions to their domain owners. Each domain owner validates and registers the contribution.

### 3.3 Contribution Lifecycle

1. **Declare**: Extension manifest declares contributions.
2. **Validate**: Domain owner validates contribution against capability matrix.
3. **Register**: Valid contribution is registered in domain registry.
4. **Activate**: Contribution becomes active when activation conditions are met.
5. **Deactivate**: Contribution is deactivated on extension unload or capability loss.
6. **Remove**: Contribution is fully removed on extension uninstall.

## 4. Extension Host Isolation

### 4.1 Isolation Levels

| Level | Description | Use Case |
|-------|------------|----------|
| `same-process` | Extension runs in the Vityo process (Dart isolate) | Simple themes, keybindings |
| `process` | Extension runs as a separate OS process | Language servers, toolchains |
| `hosted` | Extension runs on a remote host | Cloud-backed services |

### 4.2 Isolation Rules

- `same-process` extensions must not access `dart:io` directly.
- `process` extensions communicate via stdin/stdout or socket with typed codecs.
- `hosted` extensions require network permission and health monitoring.

Reference: `frontend/vityo_app/lib/src/view_ide/module_host/extension_host_isolation.dart`

## 5. Extension Lifecycle

### 5.1 Lifecycle States

```
[installed] → [validated] → [staged] → [active]
                                  ↓
                            [rollback] → [staged-previous]
                                  ↓
                            [removed]
```

### 5.2 Lifecycle Hooks

Extensions may implement lifecycle hooks (defined in `extension_lifecycle_hooks.dart`):

- `onInstall()` — one-time setup
- `onActivate()` — called when activation conditions are met
- `onDeactivate()` — called when deactivation is requested
- `onUpdate(fromVersion, toVersion)` — staged update hook
- `onUninstall()` — cleanup

### 5.3 Activation Events

Activation events (modeled after Theia/VS Code concepts but Styio-native):

- `onLanguage:{languageId}` — activate when a file of this language is opened
- `onWorkspaceOpen` — activate when any workspace is opened
- `onCommand:{commandId}` — activate when a specific command is invoked
- `onDebug` — activate when a debug session starts
- `onStartup` — activate at application startup
- `*` — activate immediately on install

## 6. Extension Marketplace

The `ExtensionMarketplace` (at `frontend/vityo_app/lib/src/view_ide/module_host/extension_marketplace.dart`) provides:

- Discovery of available extensions
- Installation with dependency resolution
- Version management and staged updates
- Extension health monitoring
- Uninstall with cleanup

## 7. Capability Matrix Integration

Extensions declare `requiredCapabilities` in their manifest. The `ModuleCapabilityMatrix` (at `frontend/vityo_app/lib/src/view_ide/module_host/module_capability_matrix.dart`) gates activation:

- If a required capability is unavailable, the extension is blocked.
- If a required capability is degraded, the extension activates with limited functionality.
- Capability changes trigger re-evaluation of active extensions.

## 8. Extension Governance

### 8.1 Extension Manifest Schema Test

Every new contribution point must have:
- A manifest schema test in `extension_manifest_contract_test.dart`
- A contribution validation test in the domain owner's test suite
- An activation/deactivation lifecycle test

### 8.2 Extension Security

- Extensions must declare all permissions in their manifest.
- `same-process` extensions are subject to Dart isolate restrictions.
- `process` extensions run with the user's OS permissions; host validates before launch.
- `hosted` extensions require explicit network permission and TLS.

### 8.3 Extension Hygiene

- Extension manifests are validated at install, activation, and periodically.
- Stale extensions (no update in N days, where N is configurable) generate warnings.
- Extensions with known vulnerabilities are blocked from activation.

## 9. Cross-Reference

- [Vityo Mainstream Architecture Alignment](./Vityo-Mainstream-Architecture-Alignment.md)
- [Vityo Protocol And Capability Negotiation](./Vityo-Protocol-And-Capability-Negotiation.md)
- [ADR-0009 Module Runtime and Staged Updates](../adr/ADR-0009-module-runtime-and-staged-updates.md)
- [Module Platform Runbook](../teams/MODULE-PLATFORM-RUNBOOK.md)
- [Extension Module Runbook](../teams/EXTENSION-MODULE-RUNBOOK.md)

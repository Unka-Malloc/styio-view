# Settings Profile Theme Personalization Contract

**Purpose:** Define ownership, product boundaries, invariants, data flow, capability gaps, downstream consumers, and validation targets for Vityo settings, profile, theme, personalization, and agent-context redaction.

**Owner:** Better Plan -- Settings Profile Theme Personalization  
**File:** `docs/contracts/SettingsProfileThemePersonalization.md`  
**Status:** Current  
**Last updated:** 2026-06-29

This contract is the canonical reference for the Settings Profile Theme Personalization plan in `docs/plan/better-plan/settings-profile-theme-personalization/`.

---

## Owned Artifacts

### 1. Configuration Stores

| Artifact | File | Description |
|----------|------|-------------|
| `ConfigurationStore` | `frontend/vityo_app/lib/src/view_ide/environment/configuration/configuration_store.dart` | Generic key-value configuration backed by `FoundationDataStore`. All settings flow through this store. |
| `ConfigurationSettingKey` | same file | Composite key: `namespace`, `name`, optional `workspaceId`. Stable key joins `namespace:workspaceId:name`. |
| `ConfigurationSettingRecord` | same file | Value wrapper: `Map<String, Object?>value` plus `List<CredentialReference>`. |
| `ConfigurationSettingChange` | same file | Event emitted on write/update/delete/migrate. |
| `ShellConfigurationStore` | `.../configuration/shell_configuration_store.dart` | Writes `ShellConfiguration` through `ConfigurationStore`. |
| `LanguageServiceConfigurationStore` | `.../configuration/language_service_configuration_store.dart` | Language service config through `ConfigurationStore`. |
| `EnvironmentVariableConfiguration` | `.../configuration/environment_variable_configuration.dart` | Overlay scopes: user, workspace, profile, task, debug, toolchain, extension. Supports `CredentialReference` injection. |

### 2. Credential and Secret Storage

| Artifact | File | Description |
|----------|------|-------------|
| `CredentialDataStoreKey` | `frontend/vityo_app/lib/.../credential_data_store.dart` | Composite key: `namespace`, `name`, `scope` (user|workspace|toolchain|service), optional `targetId`. |
| `CredentialReference` | same file | Lightweight pointer to a stored credential. |
| `CredentialSecretRecord` | same file | Full secret record with `secretValue`, expiry, metadata. |
| `FoundationCredentialDataStore` | same file | Persists credentials under namespace `configuration.credentials`. |
| `SecretStore` (abstract) | `.../configuration/secret_store.dart` | Abstract interface: read/write/delete/list. |
| `InMemorySecretStore` | same file | Volatile in-memory implementation for tests and previews. |
| `SecretStoreWritePolicy` | same file | Blocks long-lived web-fallback secrets without user confirmation. |
| `SecretStoreHealth` | same file | Reports `backendKind`, `persistent`, `safeForLongLivedSecrets`. |

### 3. Theme Models and Store

| Artifact | File | Description |
|----------|------|-------------|
| `VityoThemePreset` | `frontend/vityo_app/lib/.../vityo_theme_override.dart` | Enum: `parchment`, `graphite`. |
| `VityoThemeOverride` | same file | Per-field color overrides: `canvas`, `panel`, `ink`, `accent`, `muted`. |
| `VityoThemeOverrideStore` | `.../configuration/theme_override_store.dart` | DataStore owner `vityo.theme-override`, namespace `theme.override`. |
| `VityoTheme` | `frontend/vityo_app/lib/.../vityo_theme.dart` | Light theme builder. Accepts preset + overrides. |
| `VityoThemeOverrideColorX` | same file | Extension converting `int?` color fields to `Color?`. |

### 4. Command Palette Preferences and Keybinding Profiles

| Artifact | File | Description |
|----------|------|-------------|
| `CommandPaletteDisplayPreferences` | `frontend/vityo_app/lib/.../command_palette_recent_store.dart` | Workspace-level display options. |
| `CommandPaletteRecentCommandHistory` | same file | Ordered recent command list (max 20). |
| `CommandPaletteDisplayPreferencesStore` | same file | DataStore owner `interaction.command-palette.preferences`. |
| `CommandPaletteRecentCommandStore` | same file | DataStore owner `interaction.command-palette.recent`. |
| `CommandKeybindingProfile` | `.../commands/command_keybinding_profile.dart` | Per-workspace keybinding overrides. |
| `CommandKeybindingProfileStore` | same file | DataStore owner `interaction.command-palette.keybindings`. |

### 5. Agent Profile and Provider Endpoint

| Artifact | File | Description |
|----------|------|-------------|
| `AgentPromptProfile` | `frontend/vityo_app/lib/.../agent/agent_profile.dart` | Profile with `AgentProviderEndpoint`. |
| `AgentProviderEndpoint` | same file | Route, base URL, model, credential policy. |
| `AgentProviderCredentialPolicy` | same file | `explicitUserCredential`, `hostedSessionCredential`, `noClientCredential`. |
| `AgentPromptProfileStore` | `.../agent_prompt_profile_store.dart` | DataStore owner `agent.prompt-profile`. |

### 6. Settings UI Surface

| Artifact | File | Description |
|----------|------|-------------|
| `SettingsSurface` | `frontend/vityo_app/.../settings_surface.dart` | Product settings entry with toolchain, command palette, and theme cards. |
| `ViewportProfile` | `.../platform/viewport_profile.dart` | Desktop/mobile dimensions, drives compact layout. |

### 7. Log Redaction and Agent Context

| Artifact | File | Description |
|----------|------|-------------|
| `LogRedactor` | `frontend/vityo_app/.../log_redactor.dart` | Regex-based redactor with 11 default rules. |
| `ConfigurationStore._assertNoSecretLikeValues` | `configuration_store.dart` | Validate-before-write guard rejecting raw secrets. |

### 8. Import / Export Paths

| Artifact | File | Description |
|----------|------|-------------|
| `TestRunConfigurationStore` | `frontend/vityo_app/.../test_run_configuration_store.dart` | DataStore owner `interaction.testing.run-configurations`. |
| `TestRunHistoryStore` | `.../testing/test_run_history_store.dart` | Persisted test run history. |
| `ShellConfiguration` | `.../configuration/shell_configuration.dart` | Shell profile list, default profile, environment overlay. |

### 9. DataStore Owners Summary

| Owner ID | Layer | Namespace(s) |
|----------|-------|-------------|
| `environment.configuration` | `environment` | `configuration.*` (prefix) |
| `environment.configuration.credentials` | `environment` | `configuration.credentials` |
| `vityo.theme-override` | `configuration` | `theme.override` |
| `interaction.command-palette.preferences` | `interaction` | `interaction.command-palette.preferences` |
| `interaction.command-palette.recent` | `interaction` | `interaction.command-palette.recent` |
| `interaction.command-palette.keybindings` | `interaction` | `interaction.command-palette.keybindings` |
| `interaction.testing.run-configurations` | `interaction` | `interaction.testing.run-configurations` |
| `interaction.testing.run-history` | `interaction` | `interaction.testing.run-history` |
| `agent.prompt-profile` | `service` | `agent.profile` |

---

## Product Boundaries

### What This Contract Owns

- User-configurable settings: toolchain selection, shell profile, command palette display, keybinding overrides, theme colors.
- Theme presets and per-workspace color overrides.
- Agent provider profiles and endpoints.
- Credential and secret storage (via `FoundationCredentialDataStore` and `SecretStore`).
- Log redaction of secrets, tokens, and PII.
- Viewport-driven adaptive layout of settings surfaces.
- Persistence through `FoundationDataStore`.
- Import/export of test run configurations and histories.

### What Adjacent Contracts Own

- **LanguageServiceAdapter.md**: Language service configuration.
- **ToolchainManagementAdapter.md**: Toolchain install/update lifecycle.
- **RuntimeEventAdapter.md**: Runtime and debug console settings.
- **ProblemsTestingSourceControlSurfaces.md**: Test run execution and coverage.
- **WorkbenchShellSurfaces.md**: Shell rendering and shell integration.

### What This Contract Explicitly Does NOT Own

- Cloud sync of settings/profile/theme (no sync service exists yet).
- OS-native secure credential storage (TODO for Keychain/libsecret migration).
- User authentication or identity management.
- Debug console or runtime terminal settings.
- Source control credentials.
- Compiler/language toolchain internals.

---

## Invariants

### I1: Raw Secrets Must Never Be Stored in Configuration Values

`ConfigurationStore.write()` calls `_assertNoSecretLikeValues()` before
persisting.  Any value containing token-like key names or matching regex
patterns for bearer tokens, API keys, GitHub tokens, etc. is rejected.
Credentials must be stored as `CredentialReference` in the
`credentialReferences` list.

### I2: Credential Secret Values Are Only Visible Through Explicit Read

`CredentialSecretRecord.secretValue` is the only live access path.
`toMetadata()` always produces a redacted value.

### I3: Theme Override Is Per-Workspace

`VityoThemeOverrideStore` saves under `FoundationResourceScope.workspace`.
No global/user-scoped theme override exists.

### I4: Command Palette Preferences Are Per-Workspace

All command palette stores use `FoundationResourceScope.workspace`.

### I5: Agent Profiles Are Per-Workspace With a Manifest

`AgentPromptProfileStore` stores profiles under workspace scope with a
`__manifest__` key for discovery.

### I6: Settings UI Is a Consumer, Not a Store

`SettingsSurface` receives all state through constructor parameters and
delegates save operations via callbacks.  No widget holds persistent state.

### I7: Log Redaction Is Stateless and Regex-Only

`LogRedactor` has no mutable state.  Rules cover: Authorization headers,
bearer tokens, API keys, GitHub tokens, email addresses, home paths, Windows
user paths, session IDs.

### I8: Single Implementation Path

No fallback, legacy, v1/v2, compat, or experimental paths exist.  Only
`InMemorySecretStore` is a non-persistent alternative tagged for
tests/previews.

---

## Data Flow

```
User Input / SettingsSurface
    |
    v
Callback (onSaveThemeOverride, onSaveCommandPalettePreferences, ...)
    |
    v
Store (VityoThemeOverrideStore, CommandPaletteDisplayPreferencesStore, ...)
    |
    v
FoundationDataStoreOwner (constrained namespace, workspace scope)
    |
    v
FoundationDataStore (lock-protected JSON persistence)
    |
    v
Stream (FoundationDataStoreChange) -> live watchers update surfaces

Secrets path:
User-provided credential
    |
    v
FoundationCredentialDataStore.write(CredentialSecretRecord)
    |  secretValue stored, metadata redacted
    v
ConfigurationSettingRecord.credentialReferences (pointer only)
    |  _assertNoSecretLikeValues rejects raw secrets at write time
    v
LogRedactor (redacts secret-like patterns in all output paths)
```

---

## Downstream Consumers

| Consumer | What It Consumes | Path |
|----------|-----------------|------|
| `SettingsSurface` | All settings, preferences, theme overrides | `view_render/settings/settings_surface.dart` |
| `VityoTheme` | `VityoThemePreset` + `VityoThemeOverride` | `view_render/theme/vityo_theme.dart` |
| Agent surface | `AgentPromptProfile`, `CredentialReference` | `view_ide/agent/` |
| `CommandPaletteOverlayState` | Display preferences, recent history | `view_ide/commands/command_palette_model.dart` |
| IDE capability framework | Capability snapshot | `view_ide/foundation/ide_capability_framework.dart` |
| Shell integration | `ShellConfiguration`, environment overlays | `view_ide/environment/configuration/` |
| Test runner | `TestRunConfigurationSet` | `view_ide/testing/` |
| Log output / diagnostics | `LogRedactor` | `view_ide/environment/configuration/` |
| `ConfigurationStore` consumers | `write()` enforcement | `view_ide/environment/configuration/` |

---

## Capability Gaps (Structured Blocked States)

| Gap | Owner | Reason | Recovery |
|-----|-------|--------|----------|
| OS-native secure credential storage | `environment.configuration.credentials` | Stored in DataStore JSON, not OS-backed | Migrate to Keychain/Credential Manager/libsecret |
| Cloud sync of settings/theme | No owner | No sync service exists | Add sync adapter contract |
| Theme live preview in settings | `vityo.theme-override` | Applies on save only | Add `onPreviewThemeOverride` callback |
| Dark theme support | `VityoTheme` | Only `light()` exists | Add `VityoTheme.dark()` |
| Global (user-scoped) settings | `environment.configuration` | All settings workspace-scoped | Add `FoundationResourceScope.user` variant |
| Keybinding conflict UI | `interaction.command-palette.keybindings` | No live conflict overlay | Wire resolver into settings surface |

---

## Verification Evidence

### Unit Tests

- `ConfigurationStore._assertNoSecretLikeValues` rejection of raw secrets.
- `ConfigurationStore._isSecretLikeConfigurationKey` pattern coverage.
- `CredentialSecretRecord` round-trip, expiry, `toMetadata()` redaction.
- `SecretStoreWritePolicy.evaluate` allowed/blocked/warning decisions.
- `LogRedactor.redact` per-rule test input/output pairs.
- `LogRedactor._shouldRedactScalarField` field name coverage.
- `VityoThemeOverride` JSON round-trip, hex/int parsing.
- `VityoTheme` construction with overrides and preset selection.
- `CommandPaletteDisplayPreferences` copyWith, toQueryState, JSON round-trip.
- `CommandKeybindingProfile` overrides and conflict detection.
- `AgentPromptProfile` JSON round-trip and credential policy resolution.
- `ShellConfiguration` fromFacts and JSON round-trip.

### Integration Tests

- `VityoThemeOverrideStore` save/read round-trip.
- `CommandPaletteDisplayPreferencesStore` save/read round-trip.
- `CommandKeybindingProfileStore` save/read round-trip.
- `FoundationCredentialDataStore` write/read round-trip.
- `ConfigurationStore` rejects raw secrets, accepts `CredentialReference`.
- `SettingsSurface` render with sample configurations.

### Release Gates

- No raw-secret-containing configuration record in any DataStore namespace.
- All settings-surface API callbacks accept only validated inputs.
- `SecretStoreHealth.message` contains the known migration TODO.

---

## Single Implementation Paths

| Area | Current | Legacy | Closure |
|------|---------|--------|---------|
| Theme persistence | `VityoThemeOverrideStore` | None | Single store |
| Credential storage | `FoundationCredentialDataStore` | `InMemorySecretStore` (test only) | Production path only |
| Command palette prefs | `CommandPaletteDisplayPreferencesStore` | None | Single store |
| Keybinding profiles | `CommandKeybindingProfileStore` | None | Single store |
| Agent profiles | `AgentPromptProfileStore` | None | Single store |
| Theme rendering | `VityoTheme.light()` | None | Single builder |
| Log redaction | `LogRedactor` | None | Single redactor |
| Settings surface | `SettingsSurface` | None | Single surface |

# Environment Variable Configuration

**Purpose:** Document the `docs/design/environment/configuration-store/environment-variable-configuration/` collection scope, ownership, and maintenance rules.
**Last updated:** 2026-05-17

Environment Variable Configuration stores Vityo-managed environment overlays. It does not write IDE-internal environment state back to the operating system's global environment.

This follows the same product boundary used by mature IDEs: environment values configured in the IDE are persisted as IDE or workspace configuration, then merged into process environments when terminals, tasks, debuggers, language services, shell runtimes, or toolchain commands are launched.

## 1. Boundary

| Area | Owner | Persisted where | Writes OS-level environment? |
|---|---|---|---|
| Host environment facts | Platform Context | Not owned here; facts are detected snapshots. | No |
| User environment overrides | Environment Variable Configuration | User profile configuration. | No |
| Workspace environment overrides | Environment Variable Configuration | Workspace configuration. | No |
| Profile environment overrides | Environment Variable Configuration | Profile configuration. | No |
| Env file references | Environment Variable Configuration | Configuration references to workspace or profile env files. | No |
| Secret references | Environment Variable Configuration | Redacted references to secret providers. | No |
| Process launch environment | Execution Environment Builder / Toolchain Environment Builder | Not persisted as a new source of truth. | No |
| Explicit system environment mutation | System setup workflow, if one is added later. | OS-specific shell/profile/system settings. | Only by explicit user action |

## 2. Core Rule

Vityo must not silently persist IDE-managed environment variables into system-level environment storage.

Examples of forbidden default behavior:

| Behavior | Reason |
|---|---|
| Editing `~/.bashrc`, `~/.zshrc`, PowerShell profiles, Windows system environment, or macOS launch environment from normal IDE settings. | This mutates host state outside the IDE configuration boundary. |
| Converting workspace env overrides into global OS variables. | Workspace state must not leak into the host globally. |
| Persisting toolchain runtime env mutations as user settings without an explicit user action. | Runtime process state is not configuration truth. |

Allowed behavior:

| Behavior | Reason |
|---|---|
| Store env overlays in user, workspace, or profile configuration. | This is IDE-owned configuration. |
| Apply env overlays when launching terminal, task, debugger, language service, shell runtime, or external tool processes. | This affects only the launched process tree. |
| Read host environment as Platform Context. | Facts describe the current host; they do not mutate it. |
| Run an explicit setup command that modifies OS shell/profile files after user confirmation. | This is a separate system setup workflow, not normal environment configuration. |

## 3. Data Model

| Field | Meaning |
|---|---|
| `scope` | `user`, `workspace`, `profile`, `task`, `debug`, `toolchain`, or `extension`. |
| `target` | The execution target the overlay applies to, such as terminal, Styio service, shell runtime, build command, test command, or extension host. |
| `variables` | Key-value overrides. Values may be literal strings, removals, or references. |
| `pathPrepend` | Ordered PATH entries to place before inherited PATH. |
| `pathAppend` | Ordered PATH entries to place after inherited PATH. |
| `envFiles` | Env files to parse and merge before explicit variables. |
| `secretRefs` | References to secret storage. Raw secrets must not be written into ordinary configuration files. |
| `mergePolicy` | Merge strategy for inherited environment, env files, profile overrides, workspace overrides, and target-specific overrides. |
| `redactionPolicy` | Rules for logs, diagnostics, telemetry, and UI display. |
| `platformSelector` | Optional selector for Linux, macOS, Windows, browser, remote, hosted, or automation targets. |

## 4. Merge Order

The effective process environment should be built at launch time.

Default merge order:

```text
1. Platform Context: detected host or target process environment snapshot
2. Configuration defaults: product defaults and schema defaults
3. User configuration: user-level env overlays
4. Profile configuration: active IDE profile env overlays
5. Workspace configuration: workspace env overlays and env files
6. Target configuration: terminal/task/debug/toolchain/language-service-specific overlays
7. Runtime request: one-off launch overrides from the caller
8. Redaction and validation: remove forbidden values from logs and reject invalid entries
```

Later entries override earlier entries unless `mergePolicy` says otherwise.

Current implementation path:

```text
EnvironmentVariableOverlay
  -> EnvironmentVariableConfigurationStore
    -> Configuration Store
      -> Foundation DataStore
        -> File System Manager

EnvironmentVariableFileLoader
  -> File System Manager
  -> EnvironmentVariableFileParser

EnvironmentVariableResolver
  -> inherited process environment
  -> parsed env-file variables
  -> stored overlays
  -> runtime overrides
  -> effective launch environment
```

`EnvironmentVariableConfigurationStore` persists IDE-owned overlay records and keeps `CredentialReference` values separate from ordinary configuration values. `EnvironmentVariableFileLoader` reads referenced env files through File System Manager and passes the text to `EnvironmentVariableFileParser`. The parser validates variable names without reading files directly. `EnvironmentVariableResolver` builds the effective process environment at launch time and supports env-file variables, variable override, variable removal, PATH prepend/append, and final runtime overrides. `EnvironmentVariableRedactionPolicy` provides display-safe maps and JSON projections for logs, status surfaces, and diagnostics.

This implementation intentionally does not mutate OS global environment variables.

Current remaining work is not the basic Configuration boundary. Toolchain
launch paths already consume overlays through `ToolchainEnvironmentBuilder`,
Terminal Runtime consumes the same resolver before opening PTY sessions, and
Execution Manager consumes it before generic process execution. The remaining
work is product adoption: every consumer boundary must use the redacted status
projection instead of logging raw environment values.

## 5. Consumers

| Consumer | How it uses environment configuration |
|---|---|
| Execution Manager | Launches shell runtime, terminal sessions, tasks, debug sessions, and command workflows with the effective environment. |
| Toolchain Environment Builder | Builds the environment for `styio`, `styio_lspd`, `spio`, package commands, build, run, and test commands. |
| Styio Service Connector | Receives language-service process env through the toolchain/execution path, not by reading configuration directly. |
| Extension Manager | May contribute env overlays through declared configuration schema and permission rules. |
| DataStore | Persists configuration records and may cache resolved env-file metadata, but not the effective environment as truth. |
| Platform Context | Supplies detected host/target environment facts; it does not consume configuration overlays. |

## 6. File-System Interaction

Environment Variable Configuration may reference files, but should not parse or read them directly through OS APIs.

| Need | Dependency |
|---|---|
| Read `.env` files | File System Manager |
| Resolve workspace-relative paths | File System Manager |
| Check whether an env file is inside the workspace boundary | File System Manager |
| Store user/profile/workspace configuration | DataStore through Configuration Store |
| Redact secrets in logs | Redaction policy owned by Configuration Store and consumers |

## 7. Explicit OS Mutation

A future OS System Environment Writer may exist only as an explicit setup tool. It must not be part of the default settings path.

If added, it needs separate confirmation, preview, rollback notes, and system-specific implementations.

Examples:

| Platform | Possible explicit mutation target |
|---|---|
| Linux shell | `~/.bashrc`, `~/.profile`, shell-specific startup files. |
| macOS shell | Shell startup files or explicit `launchctl` workflows. |
| Windows | User or machine environment variable APIs, PowerShell profile, or installer-managed settings. |

Normal Vityo environment configuration must stop before this boundary.

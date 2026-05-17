# Styio Toolchain Management

**Purpose:** Define how Vityo manages Styio compiler, StyioService, and related language/execution endpoints without treating them as part of the OS layer.

**Last updated:** 2026-05-17

**Status:** Draft for review

## 1. Core Rule

`StyioService` is not an OS component.

It is a service process, CLI, daemon, or future embedded endpoint launched from a selected Styio toolchain.

```text
Vityo Toolchain Manager
  -> Selected Styio Toolchain
    -> Styio Compiler / styio_lspd / CLI / future embedded endpoint
      -> OS Process API / File System / Network
```

OS provides the execution foundation. Vityo owns toolchain discovery, selection, installation policy, process startup, capability handshake, and degraded-state UI.

## 2. IDEA-Style Model

Vityo should follow the same product model used by mature IDEs for SDK/toolchain handling:

| Concern | Vityo rule |
|---|---|
| Existing local toolchain | Detect an already installed `styio` binary and allow the user to select it. |
| Managed toolchain | Allow Vityo to download, install, pin, and use a managed Styio version when supported. |
| Project binding | Let a workspace or project select a specific Styio toolchain. |
| Override | Allow profile, workspace, or future module override where needed. |
| IDE runtime separation | Vityo's own runtime is separate from the Styio toolchain used to analyze, build, or run user projects. |
| Missing toolchain | Show install/select/retry/degraded-mode recovery, not a raw OS error. |

## 3. Layer Placement

```text
Appearance    | [ Toolchain Selection UI ]  [ Install / Select / Recovery UI ]
            |   v
Interaction   | [ Toolchain Command Flow ]  [ Retry / Switch / Pin Flow ]
            |   v
Service       | [ Styio Service Connector ]  [ Capability Detector ]
            |   v
Environment   | [ Toolchain Manager ]
            |   |  [ Styio Toolchain Discovery ]  [ Install Policy ]  [ Install Executor ]  [ Version Selector ]
            |   v
Environment   | [ Selected Styio Toolchain ]
            |   |  [ styio ]  [ styio_lspd ]  [ syntax CLI ]  [ future embedded endpoint ]
            |   v
Environment   | [ Shell Runtime ]  [ Shell Manager ]  [ Toolchain Environment Builder ]  [ Toolchain Encoder / Decoder ]
            |   v
OS            | [ OS Process API ]  [ OS File System ]
External(Web) | [ Download Endpoint ]
```

## 4. Ownership Split

| Area | Owner | Notes |
|---|---|---|
| OS process spawning | System Compatibility / Process Manager | Provides spawn, signal, exit-code, env, and platform process facts. |
| Styio toolchain detection | Toolchain Manager | Finds existing local Styio installations and validates versions. |
| Styio managed install | Toolchain Manager | Plans install modes, executes external installer commands, stages managed download artifacts, and keeps verification/registration explicit. |
| Styio version selection | Configuration Store + Toolchain Manager | User/workspace config chooses the toolchain; Toolchain Manager resolves it. |
| Shell Runtime | Toolchain Manager + Shell Manager | Builds toolchain-bound shell execution profiles using Shell Facts and Shell Adapter context. |
| StyioService startup | Toolchain Manager + Styio Service Connector | Starts CLI/LSP/daemon/embedded endpoint from selected toolchain, optionally through Shell Runtime when shell invocation is required. |
| Language facts | StyioService | Parser, analyzer, semantic facts, references, hover, completion, and language truth. |
| Editor display | Vityo Editor / Appearance / Interaction   | Renders and applies language results. |

## 5. Recovery Surface

When the selected Styio toolchain is missing or incompatible, Vityo should offer product-level recovery choices:

| Failure | Recovery choices |
|---|---|
| No Styio toolchain selected | Select existing toolchain, install managed toolchain, use degraded mode. |
| Selected toolchain missing | Locate again, install replacement, clear selection, use degraded mode. |
| Version incompatible | Switch version, upgrade/downgrade managed version, show required contract. |
| StyioService failed to start | Retry, show logs, switch transport, use CLI fallback, use degraded mode. |
| Capability missing | Disable unsupported feature, show capability gap, request upstream contract. |

## 5.1 Configuration Binding

Styio toolchain discovery is implemented in Toolchain, not Language Service.

Current implementation path:

```text
frontend/vityo_app/lib/src/view_ide/toolchain/styio_toolchain_discovery.dart
frontend/vityo_app/lib/src/view_ide/toolchain/styio_toolchain_discovery_io.dart
frontend/vityo_app/lib/src/view_ide/toolchain/styio_toolchain_discovery_stub.dart
```

Language Service may keep a compatibility re-export, but it must not own the platform discovery implementation. StyioService startup consumes a selected `ToolchainCatalog`.

Toolchain selection is persisted through Configuration, not through an ad-hoc file owned by the runtime.

```text
ToolchainCatalog
  -> ToolchainCatalogSnapshot
    -> ToolchainConfigurationStore
      -> Configuration Store
        -> Foundation DataStore
          -> File System Manager
```

The same path also exposes change observation:

```text
Foundation DataStore change
  -> ConfigurationSettingChange
    -> ToolchainCatalogConfigurationChange
      -> Toolchain status surfaces / future Language Service rebinding
```

`ConfigurationStore.watch` maps Foundation DataStore changes into
configuration-domain setting changes. `ToolchainConfigurationStore.watchCatalog`
maps the toolchain catalog setting into a catalog-level change event and keeps
delete events explicit with a null catalog.

Toolchain catalog mutation should use the same Foundation transaction path:

```text
ToolchainConfigurationStore.editCatalog
  -> ConfigurationStore.edit
    -> FoundationDataStoreOwner.editJson
      -> FoundationDataStore lock-serialized write / delete / keep
```

`ToolchainManager.registerToolchain`, `ToolchainManager.selectToolchain`, and
`ToolchainManager.clearActiveToolchain` use this edit path for catalog mutation.
Duplicate registration, missing selection, and empty clear-active operations
return `keep` so they do not write catalog state or emit false catalog-change
events.

The persisted catalog contains:

| Data | Meaning |
|---|---|
| `descriptors` | Toolchain id, kind, display name, executable path, version, channel, and non-secret metadata. |
| `activeToolchainIds` | Active descriptor id per `ToolchainKind`, such as `language-service` or `runner`. |

Ordinary toolchain configuration must not store secrets. Registry tokens, remote credentials, or install credentials must be stored as `CredentialReference` values and resolved through `Credential DataStore`.

`ToolchainManager` is the application-side Toolchain entry point. It loads the persisted `ToolchainCatalog` through `ToolchainConfigurationStore`, creates `ToolchainRuntime` from `PlatformManagerBundle`, and exposes run, health-check, install planning, and install execution paths without making callers assemble Configuration, Platform Manager, Runtime, Policy, Executor, and Health Checker manually.

`ToolchainManager.snapshot` exposes the current normalized toolchain catalog state for status surfaces. The snapshot includes target id, optional workspace id, registered descriptors, active state per kind, version, channel, executable path, and non-secret metadata. It does not claim install, download, pin, or recovery workflows are complete; those require separate result envelopes.

`ToolchainManager.selectToolchain` and `ToolchainManager.clearActiveToolchain` return `ToolchainSelectionResult` envelopes. These cover the implemented use/pin and clear-active paths with structured selected, cleared, and missing states. Missing-id results do not invent a toolchain kind. They do not cover managed download or installer execution.

`ToolchainManager.registerToolchain` covers the implemented local/manual toolchain registration path. It returns `ToolchainRegistrationResult` with registered, duplicate, or invalid states and persists successful registrations through `ToolchainConfigurationStore`. This supports user-selected local executables without pretending managed download is implemented.

## 5.2 Version Resolution

Toolchain resolution is owned by Toolchain.

Current implementation path:

```text
ToolchainRequirement
  -> ToolchainResolver
    -> ToolchainResolution
      -> ToolchainRuntime
```

`ToolchainRequirement` may request a kind, id, version, channel, and metadata constraints such as a StyioService protocol contract. `ToolchainResolver` must first respect an explicit id, then active toolchain selection, then registered alternatives of the same kind. If no descriptor satisfies the requirement, `ToolchainRuntime` must block before spawning a process.

This keeps version and contract matching out of Language Service. Language Service can request a StyioService contract, but Toolchain decides which executable satisfies that request.

## 5.3 Install Policy

Toolchain install policy is owned by Toolchain.

Current implementation path:

```text
ToolchainInstallRequest
  -> ToolchainInstallPolicy
    -> ToolchainInstallPlan
      -> ToolchainInstallExecutor
        -> Process Manager for external installer commands
          -> ToolchainInstallExecutionResult
```

The policy layer decides whether Vityo may offer manual selection, managed download, or external installer commands for a missing toolchain. It does not perform the download itself and it does not mutate the file system. Actual download/execution must be implemented by a Toolchain installer using Network Manager, File System Manager, Process Manager, credentials, and explicit user/workspace policy.

Managed downloads must use trusted HTTPS hosts. Untrusted download hosts produce a blocked plan.

Policy may require managed downloads to carry an expected SHA-256 before a plan is actionable. This makes checksum verification a planning-time gate instead of a best-effort executor detail.

Policy may also require signature or stronger provenance verification. Current Vityo does not yet wire a signature verifier, so `requireManagedDownloadSignature` blocks managed download plans even when a signature URI is supplied. This is intentional: Vityo must fail closed instead of treating checksum-only verification as strong provenance.

`ToolchainInstallRequest.provenanceSignatureUri` and `ToolchainInstallPlan.provenanceSignatureUri` carry the signature location for a future verifier. They are metadata only today. The policy does not treat the presence of this URI as verification.

`ToolchainInstallPlan.toJson` is the status envelope for install policy UI. It exposes planned or blocked state, mode, requirement, actionable flag, optional URI or external command, and recovery message. It remains a plan only; it does not execute downloads or installers.

`ToolchainInstallExecutor` is the execution boundary for approved plans.

| Plan mode | Current execution behavior |
|---|---|
| `manualSelection` | Returns `requiresUserAction`; UI must collect or confirm an executable path before registration. |
| `externalCommand` | Runs the command through Platform Manager's `Process Manager` using Toolchain environment-building rules. |
| `managedDownload` | Downloads binary artifacts through `Network Manager`, verifies optional SHA-256 and byte-size expectations, writes staged bytes through `File System Manager`, optionally extracts tar archives, optionally marks the staged or extracted executable, and returns `staged`; signature/provenance verification is not wired yet. |
| `disabled` or blocked plan | Returns `blocked` with the plan message. |

`ToolchainInstallExecutionResult.toJson` is the status envelope for command-flow UI, logs, and diagnostics. It includes the original plan, execution status, optional `ProcessCommandResult`, optional `NetworkTextResponse`, staged path, recovery message, and success boolean.

Install execution results may also include `platformFailure`. This is the structured failure envelope produced by the concrete Platform Manager used by the install mode, such as `ProcessOperationFailure` for external installer commands or `NetworkOperationFailure` for managed downloads. Toolchain records the envelope but does not reinterpret platform-specific failure kinds.

`ToolchainArtifactVerifier` is the isolated artifact-verification boundary used by managed downloads. It currently computes artifact SHA-256 and byte size, compares them with expected values from the install plan, and returns a structured `ToolchainArtifactVerification` result. This is not a signature system yet; it only keeps checksum and size verification out of the executor control flow so stronger provenance verification can be plugged in later.

`ToolchainRecoveryAction` is the product-facing recovery hint carried by failed, blocked, or user-action install execution results. It is still Toolchain-owned data, not UI behavior. Appearance and Interaction decide how to render, sort, confirm, or invoke the action.

Current product projection path:

```text
ProjectGraphSnapshot.toolchain
ToolchainManagerStatusReport
ToolchainCommandResult
  -> Interaction / ToolchainStatusSurface
    -> Appearance / toolchain-status-renderer
      -> Runtime Surface
      -> Settings Surface
```

`ToolchainStatusSurface` is intentionally a projection, not a second toolchain
manager. It may summarize the manager report, source, version, channel, last
command state, and recovery action ids for UI consumption. Shell may consume an
optional `ValueListenable<ToolchainManagerStatusReport>` and falls back to the
project-graph toolchain snapshot when no manager report is wired. It must not
discover executables, install tools, select versions, mutate Configuration, or
reinterpret raw Toolchain payloads.

Settings may render the same projection as a product configuration entry. The
Settings surface does not resolve catalogs, run installers, or choose versions;
it only displays manager-backed status and forwards recovery action ids to the
Shell interaction path.

`ToolchainSettingsSurface` is the richer settings projection over the same
manager report. It exposes catalog candidates, normalized capability states,
durable recovery state, and persisted install history for Settings UI without
making Settings resolve catalogs or mutate Configuration directly.

Selecting a registered candidate is a Shell interaction backed by
`ToolchainManager.selectToolchain`. Settings passes only the candidate id to
Shell; Toolchain Manager mutates the persisted catalog through
`ToolchainConfigurationStore`, which writes through Configuration and
Foundation DataStore. Settings must not write Configuration directly.

Clearing an active candidate follows the same rule. Settings passes the
`ToolchainKind` to Shell, Shell calls `ToolchainManager.clearActiveToolchain`,
and Toolchain Manager persists the active-state change through the same
Configuration-backed catalog path.

The managed-install recovery action starts with planning, not execution. Shell
calls `ToolchainManager.planInstallation`, stores the latest
`ToolchainInstallPlan`, and logs the policy decision. Download, external
installer execution, and registration still require an explicit installer UI or
confirmed command flow; Settings must not start those side effects directly.

Settings may render the latest install plan through a
`ToolchainInstallPlanSurface`. This is still a policy/status projection, not an
installer executor.

The only currently wired execution step is the safe `manualSelection` path.
Shell may execute the latest manual-selection plan through
`ToolchainManager.executeInstallPlan`; the executor returns
`requiresUserAction`, records install history, and does not download, run an
external command, or register a toolchain. Non-manual install modes still require
a separate explicit confirmation flow before execution.

`AppBootstrap.load` wires the live application path:

```text
Platform Detector / Context / Manager Bundle
  -> Foundation DataStore
    -> ConfigurationStore
      -> ToolchainConfigurationStore
        -> ToolchainManager
          -> ValueNotifier<ToolchainManagerStatusReport>
            -> ShellModel
              -> ToolchainStatusSurface
```

The bootstrap-owned report source publishes the initial language-service
toolchain report and refreshes it when the toolchain catalog setting changes.
This is the product path for manager-backed Toolchain status. Project graph
toolchain status remains a fallback for tests, hosted payloads, and routes where
the manager report has not been wired yet.

Recovery action invocation is still outside Toolchain Manager rendering:

```text
Runtime Surface
  -> ShellModel.handleToolchainRecoveryAction
    -> ShellRuntimeModel
      -> ToolchainManagementAdapter only for concrete retryable commands
```

Current wired actions:

| Recovery action | Current behavior |
|---|---|
| `retry-tool-use` | Re-runs `useManagedCompiler` when an active compiler is resolved. |
| `retry-tool-pin` | Re-runs `pinManagedCompiler` when an active compiler is resolved. |
| `show-toolchain-logs` | Routes the shell to the Debug bottom tab and records the log-view intent. |
| `select-existing-toolchain` | Records a selection route request for the future selector UI. |
| `install-managed-toolchain` | Records a managed-install route request for the future installer UI. |
| `use-degraded-mode` | Records a degraded-mode route request. |

Current action mapping:

| Plan mode | Recovery action ids |
|---|---|
| `manualSelection` | `select-existing-toolchain` |
| `managedDownload` | `configure-managed-download`, `select-existing-toolchain` |
| `externalCommand` | `retry-external-installer`, `select-existing-toolchain` |
| `disabled` | `enable-toolchain-installation` |

Successful install executions do not carry recovery actions.

`ToolchainManager.planInstallation` and `ToolchainManager.executeInstallPlan` are convenience entry points for upper layers. They do not bypass policy.

`ToolchainManager.installAndRegisterStagedToolchain` covers direct artifacts and simple tar archive artifacts. When a managed download produces a staged artifact that is already the executable to use, the manager can register that staged path as a `ToolchainDescriptor`, persist it through `ToolchainConfigurationStore`, and optionally activate it for the workspace. When a managed download produces a tar archive and the plan names `archiveExecutablePath`, the install executor extracts the tar archive and the manager registers the extracted executable path.

`ToolchainManager.installAndRegisterArchiveManifestToolchain` covers richer tar layouts. The plan names `archiveManifestPath`; after extraction, the manager reads that manifest JSON, resolves its relative `executablePath` inside the extraction directory, builds a `ToolchainDescriptor`, persists it through `ToolchainConfigurationStore`, and optionally activates it for the workspace.

The registration result is represented by `ToolchainInstallRegistrationResult`. It includes the install execution envelope, optional registration envelope, current snapshot, rollback status, rollback message, message, and success boolean.

If install or registration fails after a staged or extracted artifact was produced, `ToolchainManager` rolls back staging and extraction directories by default. Callers may disable this only when they need to preserve artifacts for diagnostics.

A staged managed download is not a usable toolchain by itself. It is a locally persisted artifact candidate. The current policy can require expected SHA-256, carry an optional provenance signature URI, and fail closed when strong provenance is required but no verifier is wired. The executor can verify artifact SHA-256 and byte size before byte-preserving staging, extract simple tar archives, reject archive path traversal, and request an executable bit on the staged or extracted executable. The manager can register a staged file, a named extracted executable, or a manifest-described archive layout as the toolchain entry point, and it rolls back staging/extraction directories on install or registration failure. A later installer/verifier must still prove signature or stronger provenance and required StyioService contract before production-grade archive-based registration.

This keeps install decisions out of Language Service and UI widgets. UI may present a plan, but Toolchain owns whether that plan is allowed.

## 5.4 Health Check

Toolchain health checks are owned by Toolchain.

Current implementation path:

```text
ToolchainRequirement
  -> ToolchainHealthChecker
    -> ToolchainResolver
    -> optional Process Manager probe
      -> ToolchainHealthReport
```

`ToolchainHealthChecker` first resolves a `ToolchainRequirement`. If the caller supplies probe arguments, it runs a small probe command through Process Manager using the same environment-building rules as `ToolchainRuntime`. `ToolchainRuntime.checkHealth` exposes the same preflight through the runtime object. This lets Language Service distinguish an unresolved toolchain from a resolved but failing executable before attempting full StyioService analysis.

`ToolchainRuntimeResult`, `ToolchainHealthReport`, `ToolchainResolution`, and lower `ProcessCommandResult` expose `toJson` status envelopes for UI, logs, and diagnostics. These envelopes include status, resolved descriptor, process result, messages, and success booleans without changing execution semantics.

`ToolchainManager.statusReport` is the manager-backed status aggregation
envelope. It loads the persisted catalog, projects a `ToolchainStateSnapshot`,
resolves a `ToolchainRequirement`, projects normalized capability states,
projects durable recovery state, includes persisted install history, and
optionally includes a health probe. This gives product surfaces a stable source
for ready, unresolved, or unhealthy toolchain state without reading the latest
Shell command log.

```text
ToolchainConfigurationStore
  -> ToolchainManager.statusReport
    -> ToolchainStateSnapshot
    -> ToolchainResolution
    -> ToolchainCapabilityStatus[]
    -> ToolchainRecoveryState
    -> ToolchainInstallHistorySnapshot
    -> optional ToolchainHealthReport
```

The report is still Toolchain-owned data. Runtime or settings surfaces may
render it, but they must not reimplement catalog resolution or executable health
probing.

Capability status is normalized per `ToolchainKind`:

| State | Meaning |
|---|---|
| `active` | A descriptor of that kind is active and satisfies the requested requirement. |
| `available` | A descriptor of that kind exists and can satisfy the requested requirement, but it is not the active descriptor. |
| `unresolved` | No matching descriptor can be resolved for that kind. |
| `unhealthy` | A descriptor resolves, but the optional health probe failed. |

Recovery state is derived from durable manager facts rather than Shell logs:

| State | Meaning |
|---|---|
| `none` | The requested toolchain resolved and has no failed health/install recovery need. |
| `needsSelection` | The requested toolchain kind cannot be resolved, so selection, install, or degraded mode can be offered. |
| `needsInstall` | Reserved for installer-specific missing managed artifact cases. |
| `retryAvailable` | A health probe or latest persisted install execution failed and retry actions can be offered. |

`ToolchainConfigurationStore` also owns persisted install history:

```text
ToolchainInstallExecutionResult
  -> ToolchainInstallHistoryEntry
    -> ToolchainConfigurationStore.appendInstallHistory
      -> ConfigurationStore
        -> Foundation DataStore
```

`ToolchainManager.executeInstallPlan` records each install execution with mode,
kind, status, success flag, message, and timestamp. This history is intentionally
execution-level history. It does not replace catalog state, does not store
secrets, and does not claim that a staged artifact is active unless registration
also writes the catalog.

## 5.5 Encoder / Decoder

Toolchain owns reusable payload encoding and decoding for tool-backed protocols.

Current implementation path:

```text
ToolchainPayloadCodec
  -> encode/decode UTF-8 text
  -> encode/decode JSON maps
  -> encode/decode JSONL map streams
```

This belongs to Toolchain because it is used at external tool and service boundaries, such as Styio CLI JSONL output, future daemon/LSP payloads, package-manager responses, and task runner protocol output.

It must not own language semantics. Decoding a Styio diagnostic JSONL record into a generic map is Toolchain behavior; interpreting that map as Vityo diagnostics, semantic tokens, hover content, or code actions belongs to the Styio Language Service adapter.

It must not own configuration truth. Codec metadata may carry contract/version labels, but selected toolchain versions and persistent settings are stored through Toolchain Configuration Store and Configuration Store.

## 5.6 Toolchain Environment Builder

Toolchain owns the launch-time environment builder for external tool processes.

Current implementation path:

```text
EnvironmentVariableOverlay
  -> EnvironmentVariableResolver
    -> ToolchainEnvironmentBuilder
      -> ToolchainRuntime
        -> Process Manager
```

`ToolchainEnvironmentBuilder` combines inherited environment, Configuration-owned environment overlays, and runtime overrides before `ToolchainRuntime` launches a selected toolchain.

`ToolchainRuntime.fromPlatformManagers` is the preferred bridge when a caller already has a `PlatformManagerBundle`. It consumes the bundle's `Process Manager` and keeps tool execution above the Platform Manager boundary instead of reaching for system-specific process implementations directly.

This keeps ownership split:

| Concern | Owner |
|---|---|
| Persist env overlays | Configuration |
| Detect host environment facts | Platform Context |
| Merge process launch environment | Toolchain Environment Builder |
| Spawn process | Process Manager |
| Interpret tool output | Owning service or command flow |

Toolchain Environment Builder must not write OS-level environment variables. It only prepares the environment map for the launched process tree.

## 6. Shell Runtime Placement

Shell Runtime belongs to the application-side environment modules through Toolchain. It consumes the system integration side for shell behavior:

```text
Platform Detector
  -> Platform Context / Shell Facts
  -> Platform Adapter / Shell Adapter
  -> Platform Manager / Shell Manager
  -> Toolchain / Shell Runtime
```

Shell Runtime is the toolchain-bound runtime profile for shell execution. It does not replace Shell Manager; it calls Shell Manager with selected toolchain, Shell Configuration, cwd, env, stdin/stdout, and execution intent.

Detailed design: [../shell-runtime/README.md](../shell-runtime/README.md)

## 7. Non-Goals

1. This module does not make StyioService part of the OS layer.
2. This module does not require users to install Styio globally before Vityo can work.
3. This module does not let Vityo invent Styio language truth.
4. This module does not make Toolchain Manager responsible for editor UI rendering.
5. This module does not mutate OS global environment variables as part of normal toolchain selection.

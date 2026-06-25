# Vityo Implementation Gaps

**Purpose:** Track unfinished Vityo implementation and integration gaps after retiring `docs/plans/` as an active documentation area.

**Last updated:** 2026-06-25

**Latest audit run:** 2026-06-25 02:00–02:30 UTC

**Status:** Active gap register

**Latest gate run (2026-06-25):** See section 10 — Verified Gate Results.

## 1. Scope

This document replaces local implementation-plan tracking.

Completed or accepted design baselines live in [Vityo-Delivered-Design-Baseline.md](./Vityo-Delivered-Design-Baseline.md). This document only records missing implementation, missing integration, unresolved upstream contracts, missing validation, or unsettled design decisions.

Status values:

| Status | Meaning |
|---|---|
| Open | Work is not complete. |
| Upstream blocked | Vityo needs a Styio or Spio machine contract before final closure. |
| Implementation needed | Design exists, but repo-local implementation is missing or incomplete. |
| Partially implemented | Repo-local anchors exist, but the full product or integration path is not complete. |
| Validation needed | Code or design anchors exist, but product-level gates are not proven. |
| Decision needed | The design boundary is not settled enough to implement. |

## 2. Language And StyioService Gaps

| Gap | Status | Owner | Required closure |
|---|---|---|---|
| ResolvedElement / ResolvedReference | Partially implemented | StyioService first, Vityo adapter second | Vityo has local and StyioService-backed `ResolvedElement` / `ResolvedReference` binding through `SemanticSnapshot`. Remaining closure: StyioService exposes stable compiler-owned resolution facts for all language constructs and Vityo removes local semantic heuristics where compiler facts exist. |
| SemanticSnapshot | Partially implemented | StyioService first, Vityo adapter second | Vityo can build `SemanticSnapshot` from local facts, merged `StyioDocumentAnalysis`, and StyioService-backed symbols/references. `StyioServiceResponse` exposes payload counts and a raw-output-safe status envelope for caches/status panels. Language result cache can bind to Toolchain catalog change streams, invalidate stale toolchain entries, keep the persisted metadata-only manifest aligned with cache invalidation, persist a manifest from `StyioServiceAnalysisDriver`, and expose manifest change observation. Remaining closure: stable upstream semantic payload including type facts, scope graph, semantic token classifications, stale-snapshot identity, and cross-document/project facts. |
| ProviderRegistry | Partially implemented | StyioService and Vityo | Vityo has capability-aware `LanguageProviderRegistry`, metadata-only `LanguageProviderRegistryManifest` projection with JSON roundtrip, Service-owned manifest persistence through `LanguageProviderRegistryManifestStore`, derived capability states, snapshot-driven provider descriptor/registration helpers, `StyioServiceCapabilityRegistrar`, `StyioServiceCapabilityNegotiator.analyzeAndRefresh`, `StyioServiceCapabilitySession` refresh/dispose lifecycle, and `StyioServiceRuntimeSession` as the local lifecycle anchor that keeps provider manifest metadata aligned with runtime registration and emits metadata-only lifecycle events. Remaining closure: upstream provider capability contract and wiring to real long-lived StyioService server/session events. |
| Rename | Upstream blocked | StyioService + Vityo | Rename safety and workspace edit plan from StyioService; dialog, preview, and apply in Vityo. |
| Code actions | Upstream blocked | StyioService + Vityo | Fix intent and raw edits from StyioService; lightbulb, menu, preview, and apply in Vityo. |
| Formatting | Upstream blocked | StyioService + Vityo | TextEdit-style edits and range rules from StyioService; command UI, save hook, and preview in Vityo. |
| Inlay hints | Upstream blocked | StyioService + Vityo | Semantic payload from StyioService; rendering and settings in Vityo. |
| Embedded parser API | Upstream blocked | styio-nightly | Stable embedded parser facade or published syntax-check API consumable by Vityo. |
| Mandatory `.true.styio` / `.false.styio` gate | Validation needed | Vityo | `LanguageFixtureFileCollector` scans fixture roots through File System Manager, `LanguageFixtureFileSystemTextLoader` reads fixture text through File System Manager, `LanguageFixtureConfidenceMatrixBuilder` classifies `.true.styio`, `.false.styio`, and unlabeled fixtures against supplied parser pass/fail results, `StyioServiceFixtureValidator` adapts `StyioServiceConnector` diagnostics into those results without implementing a parser, `LanguageFixtureGateRunner` composes collection, validation, and classification into one gate result, `StyioServiceFixtureGate` wires File System Manager plus `StyioServiceConnector` into a reusable connector-backed gate, `StyioServiceFixtureGate.fromToolchainRuntime` supports one-shot local command execution, `StyioServiceFixtureGate.fromToolchainManager` supports Configuration-backed product runtime execution, `tool/language_fixture_gate.dart` exposes a local command backed by `ToolchainStyioServiceConnector`, `scripts/language-fixture-gate.sh` resolves the Styio executable, `checkpoint-health.sh` / `local-ci-gate.yml` wire the gate into repository health, and command output includes machine-readable JSON plus compact human summary. Remaining closure: confirm the GitHub-hosted CI run after sibling `styio-nightly` builds on the remote runner. |
| Fixture corpus cleanliness | Validation needed | Vityo + StyioService | Re-run syntax validation against real Styio parser before claiming parser-clean fixtures. |

## 3. Editor Gaps

| Gap | Status | Owner | Required closure |
|---|---|---|---|
| Editor File Binding implementation | Implementation needed | Vityo | Implement load, save, watch, conflict detection, deleted-file state, readonly state, provider unavailable state, and structured error mapping. |
| Editor File Binding tests | Partially implemented | Vityo | Existing tests cover open/save, conflict, deleted-file save failure, readonly save failure, provider-unavailable save failure, resource watch state updates, shell save command persistence, shell-level external-change acceptance, direct resource-watch-to-shell reload of clean external changes, editor conflict recovery banner rendering, readonly/provider-unavailable banner rendering, and readonly-to-writable shell recovery state. Remaining closure: provider reconnect UI and broader product flow coverage. |
| Document revision to language snapshot binding | Partially implemented | Vityo | `CachedStyioLanguageService` reads cache entries by `documentId`, `revision`, `protocolVersion`, and optional `toolchainId`; `StyioServiceResultAdapter` rejects stale responses before merging analysis. Unit coverage now proves stale cached revisions do not feed diagnostics, hover, completion, semantic spans, references, or rename. Shell-level file binding coverage now proves manual acceptance and resource-watch delivery both reload a new document revision and drop old cached diagnostics. `FileSystemWorkspaceDocumentStore.watchDocument` now proves save/watch/reload delivery of text plus revision through the concrete local File System Manager route. Remaining closure: prove the same behavior across remote/browser/virtual providers when those providers exist. |
| Project-file vs IDE-state persistence split | Partially implemented | Vityo | User/project files use File System Manager; `EditorSessionDataStore` now persists tabs, active document, cursor offsets, selection anchors, and dirty document ids through an Interaction-owned Foundation DataStore Owner scoped by workspace. `EditorSessionController.toSessionSnapshot` provides the controller-to-store bridge, and `ShellRuntimeModel.persistEditorSession` / `restoreEditorSession` can explicitly save and restore the live shell editor session when the active document matches. Remaining closure: automatic save/restore policy, cross-document reopen behavior, and broader recovery handling. |
| Cache Contract | Partially implemented | Vityo | Cache contract documented in `docs/contracts/CacheContract.md`. Language cache submodule (`view_ide/language/cache/`) implements `LanguageCache` with Two-Level LRU + dependency invalidation. Cache keys include documentId, revision, workspaceGraphHash, toolchainId, providerId, protocolVersion, semanticPayloadVersion. All cache families identified: language result, semantic snapshot, project graph, file gist, runtime event derived, AI context. Remaining closure: publish the `CacheStore<K,V>` interface that the contract mandates; implement the contract's `observe()` method on LanguageCache; implement DataStore-backed Level 2 persistence; build the Project Graph, File Gist, Runtime Event Derived, and AI Context cache families that the contract lists. |

## 4. DataStore And Registry Gaps

| Gap | Status | Owner | Required closure |
|---|---|---|---|
| DataStore API | Partially implemented | Vityo | Foundation DataStore now has scoped namespaces, schema states, migration-on-read persistence, owner boundaries, file-backed records through File System Manager, lock-serialized writes, transactional JSON update/delete semantics, explicit write/delete/keep edit decisions, and scoped change subscriptions. Remaining closure: broader persistence policy and product-level adoption. |
| DataStore Owner implementations | Partially implemented | Vityo | Configuration uses a Foundation DataStore Owner with namespace-prefix enforcement and exposes setting change observation plus transaction-backed updates. Credential DataStore persists through its own Configuration-owned Foundation DataStore Owner and uses transaction-backed writes/deletes with no-op support. Language result cache manifest storage and language provider registry manifest storage use Service-owned Foundation DataStore Owners. Registry manifest storage also uses a DataStore Owner. Editor session state now uses an Interaction-owned Foundation DataStore Owner. Remaining closure: User, Appearance, Runtime, Extension, and Fallback owners where stateful behavior exists. |
| File-backed DataStore persistence | Partially implemented | Vityo | Foundation DataStore persists local file-backed records through File System Manager without reversing the dependency, with unit coverage for the persisted path. Remaining closure: non-local provider validation and broader product-level DataStore owner adoption. |
| DataStore migrations | Partially implemented | Vityo | Foundation DataStore applies named read-time migrations from stored schema state to target schema state, writes migrated records back while holding the record lock, and has tests for persisted migration and missing migration failure. Remaining closure: layer-owned migration policy coverage for concrete persisted IDE state families. |
| Registry implementation | Partially implemented | Vityo | Foundation Registry now supports validated registration, lookup, filtered listing by kind/owner/state, lifecycle state, metadata updates, immutable manifest projection, runtime-value exclusion, and generic owner/category registrars for schema, provider, command, capability, renderer, and policy categories. Remaining closure: adopt these registrars in each concrete layer and remove ad-hoc registration paths. |
| Registry manifests | Partially implemented | Vityo | Foundation Registry manifest projection and DataStore-backed manifest persistence exist. Remaining closure: local layer manifest producers and external manifest index without driving internal flow steps through registry. |
| Registry/DataStore separation tests | Partially implemented | Vityo | Foundation tests cover runtime-value exclusion from registry manifest projection and DataStore-backed manifest persistence. Remaining closure: concrete layer registrars must adopt the same separation instead of keeping ad-hoc provider state. |

## 5. Environment And File System Gaps

| Gap | Status | Owner | Required closure |
|---|---|---|---|
| File System Manager implementation | Partially implemented | Vityo | Local File System Manager has stable path/stat/read/write/bytes/list/delete/watch/copy/move/rename anchors, file URI conversion, normalized containment checks, `FileSystemBoundaryGuard`, `FileSystemTextCodec`, local/file provider router seed, executable-bit handling, explicit overwrite behavior, manager-local `FileSystemOperationFailure` classification, and workspace document watch integration through `FileSystemWorkspaceDocumentStore.watchDocument`. Remaining closure: concrete remote/browser/virtual/hosted providers, non-file URI scheme implementations, product-specific boundary policy adoption, and wider operation-level structured result adoption. |
| LocalFileSystemManager | Partially implemented | Vityo | Concrete local desktop implementation exists for path, file IO, directory watch, copy/move/rename, executable bit handling, and failure classification. Remaining closure: platform-matrix verification outside the current local test host and product-specific boundary policy adoption. |
| Remote/browser/virtual providers | Partially implemented | Vityo | `MemoryFileSystemProvider` and `BrowserVirtualFileSystemProvider` are implemented in `frontend/vityo_app/lib/src/platform/`. `FileSystemOperationResult<T>` provides structured outcomes. URI schemes: file://, memory://, browser-vfs://. `HostedWorkspaceFileSystemProvider` and the `vityo-hosted://` URI scheme are documented in the abstract `FileSystemProvider` contract as planned capabilities but do not yet have concrete implementations. Remaining closure: implement `HostedWorkspaceFileSystemProvider` with the `vityo-hosted://` scheme; validate FileSystemManager routing for all URI schemes across non-local providers. |
| File System Prober placement | Decision needed | Vityo | Decide whether it is documented under Platform Detector or File System Manager internals. |
| `canX` preflight API set | Decision needed | Vityo | Decide which preflight checks are worth exposing before execute-and-classify behavior. |
| Platform Manager interface implementation | Partially implemented | Vityo | `PlatformManagerBundle` aggregates concrete system-specific managers from `PlatformContextSnapshot`, `PlatformAdapter`, and manager factories, and exposes a thin status snapshot. File System, Process, Network, Resource, Shell, PTY, Clipboard, Notification, and Local Service managers now expose manager-local structured failure envelopes. Remaining closure: product-level adoption and cross-platform provider decisions beyond the current Linux/Debian/ARM anchors. |
| Platform Context consumption | Partially implemented | Vityo | Platform Context now normalizes component fact `targetId` values at compose/load/copy time, `Platform Adapter` produces compatibility snapshots, and manager factories consume context facts plus adapter-derived compatibility. Remaining closure: broader product adoption and non-local provider validation. |
| Environment Variable Configuration implementation | Partially implemented | Vityo | `EnvironmentVariableConfigurationStore` persists IDE-owned env overlays through Configuration Store, `EnvironmentVariableFileLoader` reads env files through File System Manager, `EnvironmentVariableFileParser` parses env-file text with variable-name validation, `EnvironmentVariableResolver` builds launch-time process env without mutating OS global environment, `EnvironmentVariableRedactionPolicy` exposes display-safe env projections, Toolchain launch paths consume overlays through `ToolchainEnvironmentBuilder`, Terminal Runtime consumes the resolver before PTY launch, and Execution Manager consumes it before generic process execution. Remaining closure: product-wide adoption of redacted status projections at every consumer boundary. |
| OS system environment writer | Decision needed | Vityo | Only add as explicit setup tool if required; never as default settings behavior. |

## 6. Toolchain And Execution Gaps

| Gap | Status | Owner | Required closure |
|---|---|---|---|
| Real JIT compiler/backend contract | Upstream blocked | styio-nightly / backend service | Replace route intent and capability gap with published execution contract. |
| Toolchain route selection | Partially implemented | Vityo | `BackendExecutionRouteSelection` now normalizes workflow/JIT route decisions into `local-cli`, `ffi`, `hosted`, and `blocked` states with adapter kind, allowed/preview flags, detail, and blocked reason for build/run/test surfaces. Shell `run` command gating now consumes this normalized selection instead of raw summary text/preview flags. Native build/test command results now carry top-level `backendRouteSelection` metadata, the Agent provider/profile contract tells coding agents to inspect that metadata before proposing build, run, test, retry, or provider/toolchain reconfiguration, and native-tool result summaries render route state in runtime/agent UI. Runtime/Project Workflow surfaces render the normalized route kind. Remaining closure: extend route policy from metadata reporting into real build/test product workflow fixtures. |
| Managed Styio toolchain lifecycle | Partially implemented | Vityo | Local/manual registration, workspace catalog binding, runtime/health execution, external installer command execution, managed binary artifact staging, policy-required SHA-256 gate, explicit fail-closed `requireManagedDownloadSignature` policy gate with `provenanceSignatureUri` carried through request/plan, isolated artifact verifier, optional size verification, staged/extracted executable-bit application, direct staged-artifact registration with rollback, simple tar extraction, extracted executable registration, archive manifest layout registration, install-failure rollback, structured recovery actions, StyioService startup from selected toolchain, product-facing `ToolchainStatusSurface` rendering, and Shell recovery action routing have unit/widget anchors. Remaining closure: actual signature or stronger provenance verifier and full selector/installer UI flows for recovery actions. |
| Normalized toolchain state snapshots | Partially implemented | Vityo | Catalog snapshots cover registered descriptors, active state, version, channel, executable path, target id, and workspace id. Toolchain catalog configuration changes can be observed through Configuration Store, and manager registration/selection/clear-active flows use transaction-backed `editCatalog` with no-op support for duplicate, missing, and empty-clear cases. `ToolchainManager.statusReport` provides manager-backed catalog snapshot + resolution + normalized capability states + durable recovery state + persisted install history + optional health aggregation, `ToolchainStatusSurface` / Shell can consume that report while falling back to `ProjectGraphSnapshot.toolchain`, and `AppBootstrap.load` wires a live manager report notifier that refreshes on toolchain catalog changes. Runtime and Settings surfaces now render manager-backed status. Settings can render catalog candidates, capability states, recovery state, and install history through `ToolchainSettingsSurface`; registered candidate selection and active-candidate clearing now call `ToolchainManager` through Shell and refresh the status report. Managed-install recovery now creates a `ToolchainInstallPlan` through `ToolchainManager.planInstallation`, Settings can render that plan through `ToolchainInstallPlanSurface`, and manual-selection plan continuation can produce `ToolchainInstallExecutionResult.requiresUserAction` plus refreshed install history. Remaining closure: external-command/managed-download execution confirmation, real manual executable picker, managed download endpoint policy, and richer selector UX. |
| Install/use/pin result envelopes | Partially implemented | Vityo | Registration, selection, clear-active, runtime, health, install plan, external install execution, staged managed download, tar extraction, extracted executable registration, archive manifest registration, direct/archive install registration envelopes with rollback status, platform failure envelopes, recovery action hints, UI-facing command recovery projection, and retry/log route invocation exist. Remaining closure: partial install state plus selector/installer recovery action flows. |
| Toolchain backend handoff examples | Implementation needed | Vityo | Keep examples non-authoritative and aligned with contracts. |
| Build/run/test product gate | Partially implemented | Vityo | `backend_route_product_gate_test.dart` validates local-cli, hosted, and blocked backend route states against `BackendExecutionRouteSelection`, Runtime Surface rendering, and build/test native result summaries without invoking real compilers or cloud providers. Shell runtime tests assert that native build/test result metadata exposes normalized backend route facts for agent coding context. Live local/hosted product workflow gates now assert `selectBackendExecutionRoute` when `VITYO_PRODUCT_GATE=1` supplies the external fixtures. Remaining closure: keep adding concrete workflow fixtures as product lanes mature. |
| Package/workflow payload maturity | Upstream blocked | styio-spio | Published project graph, toolchain state, registry/package state, dependency, and workflow success payloads. |

## 7. AI, Theme, Module, And Mobile Gaps

| Gap | Status | Owner | Required closure |
|---|---|---|---|
| Real AI provider call | Partially implemented | Vityo | Configured provider profiles can route OpenAI-compatible requests through `NetworkAgentProviderTransport`, credential-backed provider factory wiring, and `AgentCodingSessionController`; stale responses after provider switch or user cancel are ignored, provider HTTP failures now surface as structured `AgentProviderTransportException` values for http status, timeout, cancel, and invalid response cases, the controller preserves the latest structured provider failure for recovery UI, retry strategy, and telemetry, Agent Surface renders failure kind/status/recovery hint plus retry and local-fallback actions, Provider Profile renders reconfiguration guidance for base URL/model/token fixes, provider reconfiguration can save/remount after failure, cancellable provider transports can propagate cancel to a `CancellableNetworkManager` token, and live local provider E2E is covered through a loopback OpenAI-compatible HTTP route. Remaining closure: optional live cloud-provider validation with real credentials outside default CI. |
| Agent IDE command closure | Partially implemented | Vityo | Agent Surface can render pending IDE commands, apply registered commands, block unregistered commands, block missing-input commands and recent retries with the registered `inputLabel`, or block not-ready commands, retry recent command results, and promotes `metadata.requiredCommand` from recent command results into an `Apply Required Command` action with `prerequisiteForCommandId` preserved. Agent Context exposes `settingsCommands` and `toolchainCommands` so agents can use registered settings/profile recovery and Clang/C++ version-selection actions instead of inventing unsupported UI routes, and Shell runtime now accepts `openSettings` agent suggestions with completion metadata while ShellModel switches the product UI to the Settings tab. Agent-origin settings recovery now records and renders a targeted `settingsSection` plus `recoveryForCommandId` for native/toolchain prerequisites, so follow-up requests and recent-command UI can distinguish generic settings recovery from completed prerequisite commands; `openSettings` is treated as a recovery route rather than a completed prerequisite, so Agent Surface does not immediately offer the original blocked command as retryable. A dedicated `cpp-clang-version-handoff` coding skill now activates for native workspaces, including Ninja-only build evidence, steering agents toward registered Clang/C++ candidates and IDE-provided CMake/Ninja handoff facts. A shared command-metadata helper resolves top-level and nested `buildResult`/`staticAnalysisResult`/`testResult` required commands plus `backendRouteSelection` and `toolchainSelectionStatus` facts for UI actions, Shell runtime completion tracking, provider request metadata summaries, and recent-command visible status text. Successful `selectClangCppVersion` command results now preserve the selected Clang/C++ manifest and preferred CMake/Ninja build-engine handoff so the next agent step can reuse IDE-owned build facts instead of inventing compiler paths or flags. Provider metadata now carries `lastPatchApplicationPendingPatchRetained` and the patch application message so agents can repair retained failed patches before proposing unrelated new edits. Agent Surface suppresses direct retry for route-blocked or failed toolchain-selection recent commands and offers the registered `openSettings` recovery action so users and agents do not repeat known blocked routes or missing Clang/C++ selections. It also offers `openSettings` for not-ready native tool suggestions that have no direct prerequisite command, such as missing build tools. The provider/default profile contract tells agents to inspect `commands.recentResults` required-command metadata before retrying blocked recent tool results, include required command inputs from `inputLabel`, propose `openSettings` when the latest backend route is not allowed or the latest toolchain selection status is not `selected`, use `openSettings` for not-ready native tool readiness entries that have no direct prerequisite command, use `preferredBuildEngineHandoff` after Clang/C++ selection, and use registered `selectClangCppVersion` toolchain commands instead of editing Clang/C++ configuration files directly. Remaining closure: broader recovery policy coverage for route/toolchain failures. |
| Secret injection | Partially implemented | Vityo | Configuration-owned `CredentialSecretInjector` resolves short-lived injected values from `CredentialReference`, returns redacted projections for logs/UI, fails closed for missing/expired/empty/kind-mismatched credentials, and Agent provider bearer-token resolution now consumes the generic injection path. Remaining closure: wire the same injection path into Toolchain execution, remote service connectors, and product credential setup UI. |
| Local bridge / cloud execution for AI | Partially implemented | Vityo | `AgentProviderRouteExecutor` now normalizes cloud, loopback local-bridge, and blocked execution plans from provider route + endpoint + platform local-service compatibility, and exposes execution resolution reports that include selected endpoint, fallback status, credential readiness, and optional endpoint probe results. `ConfiguredAgentProviderAdapterFactory` consumes the same resolution, marks loopback providers as `localBridge`, can route local bridge requests through a dedicated transport while AppBootstrap supplies `platformManagers.localService`, can fail over from a blocked primary endpoint to serialized profile fallback endpoints, skips endpoints whose configured credential reference cannot be injected, and can consume a pluggable endpoint probe without probing real cloud providers by default. `AgentProviderConfigurator` and persisted-profile AppBootstrap mounting now pass execution resolution into `AgentCodingSessionController`, and Agent Surface Provider Profile can render ready/fallback/blocked state plus endpoint readiness. The profile form now has a minimal fallback cloud endpoint editor for one fallback base URL + model, and can promote the selected fallback into the primary provider fields for recovery. Remaining closure: multi-fallback management, retry-probe controls, and richer failover history. |
| Theme editor UI | Implementation needed | Vityo | Visual theme editing panel and live preview. |
| Theme profile store | Implementation needed | Vityo | Persist user theme overrides and cross-session restore. |
| Module package staging | Implementation needed | Vityo | Real package download/staging/activation path. |
| Platform file deletion and resource reclaim | Implementation needed | Vityo | Platform-specific package/cache/data cleanup with user-visible recovery behavior. |
| Android local-first execution | Implementation needed | Vityo | Real local-first execution path and fallback behavior. |
| Mobile interaction matrix | Validation needed | Vityo | Android/iOS input, viewport, commands, editor, runtime, and recovery behavior. |
| Device/simulator platform gates | Validation needed | Vityo | Android device/emulator and iOS simulator/cloud-route gates. |

## 8. Product Hardening Gaps

| Gap | Status | Owner | Required closure |
|---|---|---|---|
| M5 platform matrix | Validation needed | Vityo | Cross-platform route behavior for desktop, Android, iOS cloud, and Web hosted workspace. |
| M6 IDE hardening | Validation needed | Vityo | Product-level full UI, contract, sample matrix, and workflow gates. |
| Runtime event product completeness | Partially implemented | Vityo | `StyioServiceRuntimeSession` emits lifecycle events and metadata-only `StyioServiceRuntimeStatusSnapshot` values that expose provider manifest state plus diagnostics/completion/hover/semantic-token capability states and counts without raw language payloads. Interaction now has `LanguageServiceStatusSurface` to project those snapshots into UI-consumable status models without rendering ownership. `AppBootstrap`, `ShellRuntimeModel`, and `EditorSurface` now carry and render that status in the real editor language pane, with a widget-test anchor for the status card surface. Remaining closure: validate the full app flow against a real asynchronous StyioService update on every supported platform. |
| Hosted workspace retention/export UX | Validation needed | Vityo | User-visible close/export/retention/delete path. |
| Documentation automation after plan retirement | Implementation needed | Vityo | Docs index/lifecycle/audit scripts and policies must no longer require `docs/plans/`. |

## 9. Retired Plan Replacement Rule

No new local `docs/plans/` document should be added for Vityo implementation tracking.

Use these destinations instead:

| Need | Destination |
|---|---|
| Stable product/system truth | `docs/design/` |
| Active implementation or integration gap | `docs/design/Vityo-Implementation-Gaps.md` |
| Upstream Styio handoff | `docs/external/for-styio/` |
| Upstream Spio handoff | `docs/external/for-spio/` |
| Frozen milestone batch | `docs/milestones/` |
| Open risk or conflict before decision | `docs/review/` |
| Final architecture decision | `docs/adr/` |

## 10. Verified Gate Results (2026-06-25 02:00–02:30 UTC Audit)

### Gates PASSED

| Gate | Result | Notes |
|---|---|---|
| `repo-hygiene-gate.py --mode tracked` | ✅ PASS | |
| `import-boundary-gate.py` (all 6 rules) | ✅ PASS | view_render→backend_toolchain, view_render→integration, view_render→toolchain impls, view_ide→upstream private, integration re-export only, backend_toolchain→Flutter widgets |
| `architecture_boundary_gate_test.py` (16 tests) | ✅ PASS | Fixed: `setUpClass` self→cls errors in TestAllowlistFileLoading and TestHelperFunctions; `relative_path()` ValueError for temp files outside REPO_ROOT |
| `dependency-policy-gate.py` | ✅ PASS | 7/7 dependencies registered, 0 unregistered |
| `docs-gate.sh` | ✅ PASS | team-docs-gate, docs-audit passed |
| `delivery-gate.sh --mode checkpoint` | ✅ PASS | repo-hygiene staged, docs-gate staged |
| `public-contract-schema-gate.py` | ✅ PASS | 0 blocking issues, 387 advisory (output-only types). Fixed: AgentProviderAccessRule and AgentProviderAccessControl now have `schemaVersion` + `extraFields` |
| `vityo-ide-product-gate.py` | ✅ PASS | Command registry, agent context/permission/patch, diagnostic/project graph/runtime surface test anchors, view_ide import hygiene |
| `prototype/ npm run selftest:editor` | ✅ PASS | 20 selftest steps passed |
| `flutter analyze` (non-test source) | ✅ PASS | 0 errors in lib/ source (69 errors remain in test/ files — pre-existing API migration residuals) |

### Repairs Applied This Audit

| # | File(s) | Issue | Fix |
|---|---|---|---|
| 1 | `scripts/architecture_boundary_gate_test.py` | `@classmethod setUpClass` used `self` instead of `cls` (4 test errors) | Moved assertion code to instance test methods; `setUpClass` now only sets `cls.gate` |
| 2 | `scripts/import-boundary-gate.py` | `relative_path()` crashed on temp files outside REPO_ROOT (2 test errors) | Added `try/except ValueError` fallback returning absolute `str(file_path)` |
| 3 | `lib/.../agent_provider_access_control.dart` | 8 BLOCKING schema issues: `AgentProviderAccessRule` and `AgentProviderAccessControl` missing `schemaVersion`, `extraFields` | Added `schemaVersion` (int, default 1), `extraFields` (Map<String, Object?>), updated `toJson()`/`fromJson()`/`copyWith()` |
| 4 | `lib/src/platform/file_system_provider.dart`, `browser_virtual_file_system_provider.dart`, `memory_file_system_provider.dart` | `FileSystemCompatibility` undefined; `supportsScheme` missing from implements classes | Added direct import of `file_system_adapter.dart`; implemented `supportsScheme()` in both providers |
| 5 | `lib/src/platform/file_system_operation_result.dart` | Object pattern + const constructor errors | Rewrote `valueOrThrow`/`valueOrNull`/`failureOrNull` using `is`/`as` type checks; added `const FileSystemOperationResult()` constructor |
| 6 | `lib/src/view_ide/agent/agent_execution_mode.dart` | `const` on non-const factory calls (4 sites) | Removed `const` prefix from `AgentExecutionModeCheckResult.allowed()` calls |
| 7 | `lib/src/view_ide/agent/agent_tool_sandbox_router.dart` | `AgentToolDecision` not a type; non-const default; const constructor with non-const field | Fixed type to `AgentToolPermissionDecision`; removed `const` from constructor; fixed `_toolRegistry` initialization |
| 8 | `lib/src/view_ide/backend_toolchain/graph_hash.dart` | Return type mismatches in hash methods | Fixed `compute()` split into `update`+`finish()`, `fromString()` returns digest, `fromBytes()` instance creation |
| 9 | `lib/src/view_ide/backend_toolchain/toolchain_provenance_guard.dart` | Static/instance `confirmed` name conflict | Renamed static to `preApproved`, updated call sites |
| 10 | `lib/src/view_ide/backend_toolchain/workspace_graph_adapter.dart` | `hashString` undefined | Added import of `graph_hash.dart` |
| 11 | `lib/src/view_render/shell/shell_layout_plan.dart` | Exhaustive switch missing `BottomSurfaceTab.locations` (3 sites) | Added `.locations` case + wildcard `_` fallback |
| 12 | `lib/src/view_render/shell/shell_model.dart` | Exhaustive switch missing `AppCommandId.runSelectedTarget`; broken brace | Added `runSelectedTarget` case + `default` fallback; fixed switch closing brace |
| 13 | `lib/src/view_render/shell/vityo_shell_scaffold.dart` | Exhaustive switch missing `BottomSurfaceTab.navigate`, `AppCommandId.reloadFile` | Added missing cases + `default` fallbacks |

### Remaining Upstream-Blocked Items (Unchanged)

All items marked **Upstream blocked** in sections 2–8 remain unchanged. Key items:
- Rename / Code actions / Formatting / Inlay hints — need StyioService machine contract
- Embedded parser API — needs styio-nightly stable facade
- Real JIT compiler/backend contract — needs styio-nightly/backend service
- Package/workflow payload maturity — needs styio-spio

### Remaining Repo-Local Items (Not Addressed This Audit)

Items marked **Implementation needed** or **Partially implemented** that were not addressed:
- `HostedWorkspaceFileSystemProvider` (vityo-hosted:// scheme) — still unimplemented
- `CacheStore<K,V>` generic interface — not yet published
- Cache Level 2 persistence (DataStore-backed) — not yet implemented
- Theme editor UI / Theme profile store — still needed
- Module package staging / Platform file deletion and resource reclaim — still needed
- Android local-first execution — still needed
- Mobile interaction matrix / Device/simulator platform gates — still needed
- Test file API migration residuals (69 errors in test/) — pre-existing from ongoing refactoring

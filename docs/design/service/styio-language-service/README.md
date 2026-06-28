# Styio Language Service

**Purpose:** Document the `docs/design/service/styio-language-service/` collection scope, ownership, and maintenance rules.
**Last updated:** 2026-05-17

Styio Language Service is the Service Layer directory that directly serves Styio language capabilities to upper Vityo layers.

It is the only Service Layer root for Styio language behavior. Internal connector, adapter, cache, and fixture-confidence modules live under this service instead of appearing as Service Layer roots.

The protocol contract consumed by this service is defined in `docs/design/service/styio-language-service/STYIO-SERVICE-PROTOCOL-CONTRACT.md`.

## 1. Direct Service Surface

| Capability | Upper-layer consumers |
|---|---|
| Syntax validation | Interaction diagnostics flow, app-shell recovery/status surfaces |
| Diagnostics | Editor controller, problems surface, diagnostics renderer |
| Completion | Editor controller and completion popup renderer |
| Hover | Editor controller and hover renderer |
| Semantic tokens | Editor renderer and theme mapper |
| Semantic block ranges | Editor folding, structural navigation, and block outline flows |
| Definition / references | Editor navigation commands and references UI |
| Formatting edits | Editor formatting command flow and workspace edit application |
| Inlay hints | Editor source renderer and hint toggle flow |
| Parameter info | Editor parameter-info popup and signature-help command flow |
| Rename facts | Rename command flow and preview UI |
| Refactoring plans | Safe delete, inline variable, introduce variable, extract function, and change signature command flows |
| Code action facts | Code-action menu and workspace edit applier |
| Language snapshot | Editor document binding, stale-result rejection, diagnostics/completion/semantic/formatting/hint flows |

## 2. Internal Modules

| Internal module | Responsibility |
|---|---|
| `styio-service-connector` | Connects to StyioService through CLI, LSP, daemon, or future embedded API. No separate README until the connector design becomes complex. |
| `styio-cli-jsonl-protocol` | Contract-aware protocol parser for `styio --parser-engine nightly --error-format jsonl --file <file>` style output. It uses Toolchain payload decoding for JSON/JSONL bytes and only interprets Styio language records inside this service. Plain AST text is not requested by default. It accepts both individual JSONL records and a published `record: facts` envelope carrying diagnostics, completions, hovers, semantic spans, document symbols, references, explicit capability states, and other language facts. |
| `styio-service-response-envelope` | Stable status projection from `StyioServiceResponse`. It exposes status, document id, revision, protocol version, toolchain id, payload counts, stdout/stderr byte counts, and success flags without exposing raw language payloads or raw tool output. |
| `styio-result-adapter/` | Converts StyioService protocol results into Vityo diagnostics, completions, hover payloads, semantic spans, semantic blocks, formatting edits, inlay hints, parameter info, document symbols, references, code actions, rename plans, and refactoring plans. |
| `styio-service-capability-detector` | Observes fresh, empty, unavailable, failed, protocol-error, or stale capability states from StyioService responses without inferring unsupported capabilities from empty payloads. |
| `styio-service-analysis-driver` | Asynchronously combines local Vityo analysis with fresh StyioService diagnostics and rejects stale results. |
| `capability-routed-styio-language-service` | Routes `StyioLanguageService` calls to registered providers by capability, with a fallback service for missing capabilities. Its document analysis result can merge syntax, diagnostics, semantic tokens, formatting edits, semantic blocks, inlay hints, document symbols, and references from different capability providers. |
| `styio-service-runtime` | Owns the local StyioService session lifecycle, provider registration refresh, manifest synchronization, lifecycle events, and metadata-only runtime status snapshots for diagnostics, completion, hover, semantic tokens, and other service capabilities. |
| `local-styio-language-service` | Vityo local fallback service for tokens, local symbols, references, hover, completion, rename, and structural diagnostics. It is not Styio semantic truth. |
| `project-document-rule-provider` | Provider contract for project-rule facts: diagnostics, document symbols, references, and quick fixes. The contract itself does not import the legacy service. |
| `project-document-rule-registry` | Ordered registry/composite for project-rule providers. It lets current Vityo rules and future StyioService-backed project facts coexist behind the same provider contract. |
| `styio-service-project-document-rule-provider` | Project-rule provider backed by fresh `StyioServiceResultCache` responses. It lets cached StyioService diagnostics, symbols, references, code actions, formatting, hints, and semantic facts participate in project-rule merging before Vityo local rules. Cache lookup must use the same `configPath` and `workingDirectory` context as the editor-facing cached service. |
| `current-project-document-rule-provider` | Current provider implementation that serves project-rule facts from `ProjectDocumentDiagnostics`, `ProjectDocumentQuickFixProvider`, and `StyioSymbolIndex` without calling `SimpleStyioLanguageService`. |
| `project-document-diagnostics` | Current project-document diagnostics provider for compiler diagnostics, numeric diagnostics, and migrated local rule diagnostics such as missing assignment, duplicate imports, import block optimization, unreachable code, redundant explicit types, redundant parentheses, constant conditions, boolean expression simplification, local type issues, call argument issues, duplicate declarations, parameter shadowing, unused parameters, unused local symbols, and read-only resource writes. |
| `project-document-quick-fixes` | Current project-document quick-fix provider for migrated diagnostic fixes, currently numeric simplification, missing-assignment, syntax/delimiter fixes, unreachable-code line removal, unused-local-symbol cleanup, read-only resource write removal, duplicate resource/task declaration removal, duplicate declaration rename fixes, parameter shadowing rename fixes, unused-parameter change-signature cleanup, import block optimization, redundant explicit type removal, redundant parentheses removal, constant condition simplification, boolean expression simplification, unresolved current-file reference fixes, unresolved resource/task stub creation, missing function return fixes, missing task return fixes, missing task return value fixes, unresolved task return value fixes, call argument fixes, initializer type mismatch fixes, assignment type mismatch fixes, operator/condition type mismatch fixes, function return type mismatch fixes, resource write type mismatch fixes, await result/fallback type mismatch fixes, task return type mismatch fixes, and invalid task return expression fixes. |
| `legacy-project-document-rule-provider` | Compatibility adapter that can merge current providers with a supplied legacy service. It is not the default project-document provider. |
| `project-styio-document-service` | Project-document bridge that uses current local service for interactive language behavior while merging project-rule facts from `project-document-rule-provider`. It also exposes diagnostic quick fixes as cursor intentions for the editor code-action menu. |
| `language-result-cache` | Stores service results by document version, contract version, toolchain identity, `configPath`, and `workingDirectory` carried by `StyioServiceResponse`. It exposes a manifest snapshot with status and fact counts only, never raw language payloads. |
| `cached-styio-language-service` | Synchronous `StyioLanguageService` facade that serves local analysis plus fresh cached StyioService facts. It should receive project context from `AppBootstrap` or project-service construction so cache lookup is exact in multi-config workspaces. |
| `styio-completion-feature` | Independently testable IDE completion feature used by the local fallback service. It turns a `SemanticSnapshot` into keyword, type, and resolved-symbol completion items without owning Styio semantic truth. |
| `styio-formatting-feature` | Independently testable IDE formatting feature used by the local fallback service for deterministic whitespace cleanup and formatting code actions. Cached StyioService formatting edits take priority when present. |
| `styio-hover-feature` | Independently testable IDE hover feature used by the local fallback service. It turns resolved snapshot elements and syntax operator metadata into hover payloads while cached StyioService hover records take priority when present. |
| `styio-inlay-hint-feature` | Independently testable IDE inlay hint feature used by the local fallback service. It derives lightweight literal type hints from local snapshot facts without claiming compiler type truth. |
| `styio-navigation-feature` | Independently testable IDE navigation feature used by the local fallback service. It turns `ResolvedElement` / `ResolvedReference` snapshot facts into definition, references, and rename plans. |
| `styio-refactor-feature` | Independently testable IDE refactor feature used by the local fallback service. It turns local snapshot facts and selected source ranges into safe delete, inline variable, introduce variable, extract function, and change signature plans. |
| `styio-semantic-token-feature` | Independently testable IDE semantic-token feature used by the local fallback service. It turns resolved snapshot declarations and references into local fallback semantic spans without owning Styio semantic truth. |
| `styio-syntax-diagnostic-feature` | Independently testable local fallback syntax-diagnostic feature. It provides responsive delimiter diagnostics and delimiter quick fixes from token spans while real Styio syntax truth remains owned by StyioService. |
| `language-fixture-confidence-matrix/` | Defines true/false fixture expectation confidence and gate semantics for Styio syntax fixtures. It scans fixture roots through File System Manager and composes `StyioServiceConnector`-backed validation into a local matrix gate without implementing Styio syntax. |

## 3. Observed Styio CLI Capability Boundary

As of 2026-05-17, the real `styio-nightly` CLI has been observed with:

```text
styio --parser-engine nightly --styio-ast --error-format jsonl --file <file>
```

The current CLI behavior is:

| Capability | Observed CLI behavior | Vityo interpretation |
|---|---|---|
| Syntax diagnostics for invalid files | Emits JSONL diagnostic records when parsing fails. | Treat as real StyioService diagnostic truth. |
| Syntax diagnostics for valid files | Exits successfully and may emit no diagnostic records. | Treat as a successful diagnostics result with zero diagnostics. |
| AST text | Emits plain text AST when `--styio-ast` is enabled. | Do not treat as Vityo JSONL language facts. |
| Completion | No observed JSONL completion records from the current CLI. | Use Vityo local fallback or derived cached facts only; do not claim raw StyioService completion payload. |
| Hover | No observed JSONL hover records from the current CLI. | Use Vityo local fallback or derived cached facts only; do not claim raw StyioService hover payload. |
| Semantic tokens / symbols / references | No observed structured JSONL semantic records from the current CLI. | Use local fallback or future StyioService facts; do not infer compiler semantic truth from plain AST text. |

Latest local check on 2026-05-17:

```text
styio --parser-engine nightly --error-format jsonl --file value.true.styio

status=0
stdout_bytes=0
stderr_bytes=0
```

```text
styio --parser-engine nightly --error-format jsonl --file unknown-token.false.styio

status=3
stderr includes one JSONL ParseError diagnostic.
```

This means the current Vityo protocol decoder is ahead of the current CLI output contract. It can consume completion, hover, semantic, symbol, reference, code action, rename, and refactor JSONL records once StyioService produces them, either as individual JSONL records or as a published `record: facts` envelope. The same envelope can also declare capability states such as `available`, `empty`, or `unsupported`, so Vityo does not have to guess support from missing payloads. The current CLI should still only be treated as a reliable syntax diagnostics source.

Because `--styio-ast` currently emits plain text AST instead of Vityo JSONL language facts, Vityo's default CLI request must not pass `--styio-ast`. It may only be enabled explicitly for debugging or future protocol modes that define a structured AST contract.

Capability status must preserve that distinction:

| State | Meaning |
|---|---|
| `available` diagnostics with zero payload | The Styio syntax check completed successfully and found no diagnostics. |
| `empty` completion / hover / semantic tokens | The response carried no raw payload and no Vityo-derived route exists for that capability. |
| `derived` completion / hover / semantic tokens | Vityo can serve the feature from fresh StyioService semantic facts such as symbols or references, but the response did not carry the dedicated high-level payload. |
| Local fallback result | Keeps the editor usable, but is not StyioService truth. |

Do not use local fallback capability as evidence that the upstream StyioService capability is implemented.

## 4. Current Implementation Anchors

```text
frontend/vityo_app/lib/src/view_ide/language/service/
  language_service_foundation.dart
  legacy_project_document_rule_provider.dart
  current_project_document_rule_provider.dart
  local_styio_language_service.dart
  project_document_diagnostics.dart
  project_document_quick_fixes.dart
  project_document_rule_provider.dart
  project_styio_document_service.dart
  project_styio_language_service.dart
  styio_service_capability_detector.dart
  styio_service_connector.dart
  styio_service_runtime.dart
  styio_toolchain_discovery.dart
frontend/vityo_app/lib/src/view_ide/language/features/
  styio_completion_feature.dart
  styio_formatting_feature.dart
  styio_hover_feature.dart
  styio_inlay_hint_feature.dart
  styio_navigation_feature.dart
  styio_refactor_feature.dart
  styio_semantic_token_feature.dart
  styio_syntax_diagnostic_feature.dart
frontend/vityo_app/lib/src/view_ide/toolchain/
  styio_toolchain_discovery.dart
  styio_toolchain_discovery_io.dart
  styio_toolchain_discovery_stub.dart
```

Implemented boundaries:

| Boundary | Current artifact |
|---|---|
| ResolvedElement / ResolvedReference | `language_service_foundation.dart` |
| SemanticSnapshot | `language_service_foundation.dart` |
| ProviderRegistry | `language_service_foundation.dart` |
| Local fallback language service | `local_styio_language_service.dart` |
| Project document diagnostics | `project_document_diagnostics.dart` |
| Project document quick fixes | `project_document_quick_fixes.dart` |
| Project document rule provider | `project_document_rule_provider.dart` |
| Current project document rule provider | `current_project_document_rule_provider.dart` |
| Legacy project rule adapter | `legacy_project_document_rule_provider.dart` |
| Project-document migration bridge | `project_styio_document_service.dart` |
| Project-level workspace language service | `project_styio_language_service.dart` |
| Capability Detector | `styio_service_capability_detector.dart` |
| StyioService connector contract | `styio_service_connector.dart` |
| CLI JSONL protocol decoder | `styio_service_connector.dart` |
| StyioService response envelope | `StyioServiceResponse.payloadCounts` and `StyioServiceResponse.toJson` |
| Toolchain payload codec consumption | `styio_service_connector.dart` consuming `ToolchainPayloadCodec` |
| Result adapter, fact merge, and stale rejection | `styio_service_connector.dart` |
| Result adapter to SemanticSnapshot binding | `StyioServiceResultAdapter.semanticSnapshot` |
| Language result cache | `styio_service_connector.dart` |
| Cached synchronous service facade | `styio_service_connector.dart` |
| Toolchain connector | `styio_service_connector.dart` through Toolchain Runtime or Toolchain Manager |
| Platform Styio toolchain discovery | `styio_toolchain_discovery.dart` |
| Platform runtime driver creation | `styio_service_runtime.dart` |
| Runtime capability status projection | `StyioServiceRuntimeStatusSnapshot` |
| Document file path binding | `WorkspaceDocumentStore.filePathForDocumentId` |
| Parser-verified local fixture | `test/fixtures/language_service/semantic_snapshot.true.styio` |
| Language fixture confidence matrix | `language_fixture_confidence_matrix.dart` |

Runtime direction:

```text
Interaction / Editor
  -> StyioLanguageService surface
    -> CapabilityRoutedStyioLanguageService
      -> CachedStyioLanguageService for registered StyioService capabilities
      -> LocalStyioLanguageService fallback for missing capabilities
      -> LocalStyioLanguageService immediately
      -> Language Result Cache when fresh StyioService results exist
    -> Editor refreshAnalysis after async result is cached
      -> StyioServiceAnalysisDriver asynchronously
      -> StyioServiceConnector
        -> Toolchain Runtime / languageService toolchain
          -> Platform Styio toolchain discovery
          -> Styio CLI / StyioService
            -> document file path from WorkspaceDocumentStore
```

The local service may keep the editor responsive, but parser and semantic truth must come from StyioService when a fresh response is available.

Fresh StyioService results may currently override these Vityo facts:

| Fact | Cached service behavior |
|---|---|
| Diagnostics | Replaces local diagnostics when response is fresh. |
| Completion items | Used by `completeAt` when present. |
| Hover payloads | Used by `hoverAt` when the cached hover range contains the offset. |
| Semantic spans | Replaces local semantic spans in `analyzeDocument` when present. |
| Semantic block ranges | Replaces local semantic block ranges in `analyzeDocument` when present. |
| Formatting edits | Used by `formatDocument` when present. |
| Inlay hints | Replaces local inlay hints in `analyzeDocument`; also powers cached `inlayHints`. |
| Parameter info | Used by `parameterInfoAt` when the cached invocation range contains the offset. |
| Document symbols | Replaces local document symbols in `analyzeDocument` when present. |
| References | Replaces local references in `analyzeDocument`; also powers cached definition/references lookup. |
| Code actions | Used by cached `intentionsAt` and `quickFixesForDiagnostic` when present. |
| Rename plans | Used by cached `renameAt` when the requested `newName` and offset match a fresh StyioService rename plan. |
| Refactoring plans | Used by cached safe delete, inline variable, introduce variable, extract function, and change signature commands when the requested offset/range/name matches a fresh StyioService plan. |

When a fresh StyioService response carries semantic snapshot facts such as document symbols, references, or semantic spans but does not carry a dedicated capability payload, `CachedStyioLanguageService` may route local IDE features through the merged StyioService-backed `SemanticSnapshot`. Current fallback-through-snapshot behavior covers completion, hover, definition, references, rename, safe delete, inline variable, and change signature. This lets Vityo use compiler/service element facts without inventing language truth or requiring StyioService to immediately provide every high-level UI payload.

This service can consume these protocol records before StyioService produces all of them. If a record is absent, Vityo must keep the local fallback result or return an empty capability result instead of inventing Styio semantic truth.

Capability state is observational. `available` means a fresh response carried raw payload for that capability. `derived` means Vityo can provide the capability from fresh StyioService semantic facts, such as document symbols and references, even though the response did not carry the dedicated high-level payload. `empty` means the fresh response carried no raw payload and Vityo has no current derived route for that capability. `empty` must not be treated as proof that StyioService does not support the capability; only explicit unavailable, failed, protocol-error, or stale states should drive recovery or degraded status.

Capability snapshots inherit `StyioServiceResponse.toolchainId` by default so recovery UI, cache manifests, and capability state all point at the same selected Styio toolchain.

Capability UIs should distinguish `capabilitiesWithFreshPayload` from `capabilitiesWithUsableResult`. The first set only contains raw StyioService payloads. The second set also includes derived semantic-snapshot fallbacks.

`StyioServiceCapabilitySnapshot.providerCapabilityWireValues(includeDerived: ...)` is the bridge from observed capability state into provider registration or routing metadata. Use `includeDerived: true` when the provider can serve a feature through merged semantic facts, and `includeDerived: false` when a caller must require a dedicated raw StyioService payload.

`StyioServiceCapabilitySnapshot.providerDescriptor(...)` can produce a `LanguageProviderDescriptor` directly from the observed capability state. This keeps ProviderRegistry registration aligned with actual StyioService capability detection instead of hand-written capability lists.

`StyioServiceCapabilitySnapshot.providerRegistration(...)` can produce a full `LanguageProviderRegistration<T>` for a concrete provider instance. This is the preferred bridge when a fresh StyioService capability snapshot is used to register or refresh a provider in `LanguageProviderRegistry`.

`StyioServiceCapabilityRegistrar` wraps the refresh/unregister operation against `LanguageProviderRegistry`. It is the Vityo-side dynamic registration entrypoint for capability snapshots; product code should use it instead of duplicating provider descriptor and registration assembly.

`StyioServiceCapabilityRegistrar.refreshFromReport(...)` connects `StyioServiceAnalysisReport` directly to ProviderRegistry refresh. This lets an async StyioService analysis result update provider capabilities without forcing callers to manually run capability detection first.

`StyioServiceCapabilityNegotiator.analyzeAndRefresh(...)` is the end-to-end Vityo-side negotiation flow: run `StyioServiceAnalysisDriver`, produce an analysis report, detect raw and derived capabilities, and refresh `LanguageProviderRegistry`.

The negotiation request must preserve document project context. When available, callers should pass the same `filePath`, `configPath`, and `workingDirectory` used by editor refresh and cache binding. This keeps provider capability registration, result cache writes, and runtime status snapshots aligned with the exact Styio project configuration that produced the response.

`StyioServiceCapabilitySession` keeps the negotiation inputs together for a longer-lived provider session. Product code can call `refresh(document)` after analysis-triggering document changes and `dispose()` to unregister the provider from `LanguageProviderRegistry`.

`StyioServiceCapabilitySession.refresh(...)` and `StyioServiceRuntimeSession.refresh(...)` may receive `filePath`, `configPath`, and `workingDirectory`. Runtime session integrations must use these parameters instead of analyzing a bare `DocumentState`, otherwise saved-file CLI analysis, Styio config selection, and multi-workspace cache lookup can diverge from the editor-facing language service.

When a session is created with `LanguageProviderRegistryManifestStore`,
`refresh(document)` writes the current language provider manifest after the
runtime registry refresh, and `dispose()` unregisters the provider before
rewriting or deleting the manifest. This keeps status surfaces aligned with the
actual runtime provider registry and prevents stale StyioService provider
metadata from surviving session shutdown.

`StyioServiceRuntimeSession` is the local lifecycle anchor for a future real
StyioService server, daemon, LSP, or embedded session. It owns a
`StyioServiceAnalysisDriver`, a `LanguageProviderRegistry`, and a
`StyioServiceCapabilitySession` together. Refreshing the runtime session runs
analysis, updates capability registration, and persists provider manifest
metadata when a manifest store is attached. Disposing it unregisters the
provider and clears the manifest if no provider remains.

`StyioServiceRuntimeSession.events` emits metadata-only lifecycle events for
`refreshing`, `active`, `failed`, and `disposed` states. These events are the
local Vityo-side lifecycle surface for status panels and future StyioService
server/LSP/daemon event binding. They must not include raw provider instances or
raw language payloads.

`StyioServiceRuntimeStatusSnapshot` is the Service-owned status projection for
that runtime session. It may expose runtime state, provider manifest metadata,
primary capability states, usable/fresh capability counts, and lifecycle state.
It must not expose raw diagnostics, completion items, hover markdown, semantic
tokens, syntax trees, or raw StyioService output to Interaction or Appearance.

```text
StyioServiceRuntimeSession
  -> StyioServiceRuntimeStatusSnapshot
    -> Interaction / LanguageServiceStatusSurface
      -> ShellRuntimeModel
        -> Appearance / EditorSurface language-service pane
```

`LanguageServiceStatusSurface` is the Interaction-owned conversion point. It
turns Service metadata into titles, messages, severity, and UI-consumable
capability rows. Appearance renders that surface only; it does not decide
language truth, capability freshness, retry policy, or toolchain recovery.

`LanguageProviderRegistry.manifest(...)` exposes a metadata-only manifest for
status surfaces, extension loading, and review tooling. The manifest contains
schema state, language id, provider id, display name, priority, and advertised
capability ids. It must not contain provider runtime instances, service objects,
closures, cached language payloads, diagnostics, completion labels, hover
markdown, or raw StyioService output.

```text
LanguageProviderRegistry
  -> LanguageProviderRegistryManifest
    -> status / extension discovery / review surfaces
```

Runtime routing still uses `resolve(...)` and `providersFor(...)`; manifest
projection is introspection only and must not drive provider execution.

`LanguageProviderRegistryManifestStore` persists that metadata-only manifest
through a Service-owned `FoundationDataStoreOwner`. It is allowed to store
provider descriptors and capability ids for workspace or user status surfaces.
It must not store the provider runtime object and must not replace
`LanguageProviderRegistry` as the runtime routing mechanism.

```text
LanguageProviderRegistry.manifest
  -> LanguageProviderRegistryManifestStore
    -> FoundationDataStoreOwner(service.language.provider-registry)
      -> FoundationDataStore
```

`StyioServiceResultCacheManifestStore` persists only the cache manifest through a
Service-owned Foundation DataStore Owner. It stores document id, revision,
protocol version, toolchain id, status, payload counts, and message metadata. It
must not persist raw diagnostics, completions, hovers, semantic spans,
references, code actions, rename plans, or other language payload lists.

```text
StyioServiceResultCache.snapshot
  -> StyioServiceResultCacheManifestStore
    -> FoundationDataStoreOwner(service.language.result-cache)
      -> FoundationDataStore
```

`StyioServiceAnalysisDriver` may receive a `StyioServiceResultCacheManifestStore`.
When it stores a fresh StyioService response in `StyioServiceResultCache`, it
also persists the metadata-only manifest. The runtime cache remains in memory.
The persisted manifest is for status, debugging, recovery, and stale-cache
visibility.

`StyioServiceResultCacheManifestStore.watch()` exposes metadata-only manifest
changes for status surfaces. Delete events carry a null snapshot; write/update
events carry the manifest counts only.

Project-level analysis uses `ProjectStyioDocumentService` as a migration bridge. The bridge keeps interactive document behavior on the current local service and merges only project-rule facts from `ProjectDocumentRuleProvider`: diagnostics, document symbols, references, and quick fixes. The default provider is `ProjectDocumentRuleRegistry.current`, whose current registration is `CurrentProjectDocumentRuleProvider`. This keeps the default path compatible with current Vityo rules while leaving a stable slot for future StyioService-backed project-rule providers.

`LegacyProjectDocumentRuleProvider` remains available only as a compatibility adapter. It no longer sources project symbols and references from the legacy service. It builds those facts through the current `StyioSymbolIndex`, runs current `ProjectDocumentDiagnostics` and `ProjectDocumentQuickFixProvider`, and can merge a supplied legacy service when explicitly requested.

The bridge is intentionally temporary. It exists to keep current project diagnostics and quick fixes working while project rules are moved either to StyioService protocol facts or to current service-layer rule providers.

The CLI connector must receive a real file path. For Vityo-owned workspace documents, the path is resolved by `WorkspaceDocumentStore.filePathForDocumentId`. For absolute project files, the document id may already be the file path.

The test fixture naming rule applies here: parser-expected fixtures use `.true.styio` or `.false.styio`, and `.true.styio` fixtures must pass the real Styio parser command used by the connector. The repository CI wrapper defaults to `test/fixtures/language_service` and `test/fixtures/styio_language/syntax_contract`; broader fixture sets must be passed explicitly with `--fixture-root`.

Platform discovery currently checks `VITYO_STYIO_BIN`, common local binary paths such as `/usr/local/bin/styio`, Windows executable extensions such as `styio.exe`, and host lookup through `which styio` or `where.exe styio` on IO platforms. Non-IO platforms return an empty toolchain catalog and keep the local fallback service active.

## 4. Non-Responsibilities

| Capability | Owner |
|---|---|
| Styio grammar, parser, semantic truth, type facts, scope graph | StyioService / Styio toolchain |
| Editor state, command routing, workspace edit application | Interaction Layer |
| Rendering diagnostics, hover, completion, semantic colors | Appearance Layer |
| Toolchain installation, selected binary, process environment | Environment Layer / Toolchain |
| Local account/profile/sync | Service Layer / User Service |

## 5. Current Cutover State

`ProjectStyioLanguageService` no longer directly or indirectly defaults to the legacy `SimpleStyioLanguageService`. The project-rule contract is `ProjectDocumentRuleProvider`; the default implementation is `ProjectDocumentRuleRegistry.current`, currently registering `CurrentProjectDocumentRuleProvider`. Project symbols and references now come from the current `StyioSymbolIndex`; compiler, numeric, missing-assignment, duplicate import, import block optimization, unreachable-code, redundant explicit type, redundant parentheses, constant condition, boolean expression simplification, local type issue, call argument, duplicate declaration, parameter shadowing, unused-parameter, unused local symbol, and read-only resource write diagnostics come from `ProjectDocumentDiagnostics`; migrated numeric, missing-assignment, syntax/delimiter, unreachable-code, unused-local-symbol, read-only resource write, duplicate resource/task declaration, duplicate declaration rename, parameter shadowing rename, unused-parameter, import optimization, redundant explicit type, redundant parentheses, constant condition, boolean expression simplification, unresolved current-file reference, unresolved resource/task, missing function return, missing task return, missing task return value, unresolved task return value, call argument, initializer type mismatch, assignment type mismatch, operator/condition type mismatch, function return type mismatch, resource write type mismatch, await result/fallback type mismatch, task return type mismatch, and invalid task return expression quick fixes come from `ProjectDocumentQuickFixProvider`.

`LocalStyioLanguageService` is not the correct direct replacement for project-level language behavior. It remains an interactive local fallback for document-level responsiveness. Project-level diagnostics, imported symbol behavior, workspace reference facts, cleanup fixes, and project expression simplification must continue to flow through `ProjectDocumentRuleProvider` until those facts are supplied by StyioService protocol records.

This means the remaining architecture gap is not a default legacy dependency. The remaining gap is that Vityo still owns local fallback and project-rule heuristics while StyioService protocol facts are incomplete. The migration must be completed by moving project diagnostics, import graph rules, symbol resolution, task/resource type checks, and project quick fixes behind current StyioService facts or a published StyioService contract.

Current evidence:

```text
flutter test test/project_document_rule_provider_test.dart test/styio_project_language_service_test.dart test/styio_project_symbol_snapshot_test.dart test/local_styio_language_service_test.dart test/styio_service_connector_test.dart
```

The suite passes with `ProjectStyioDocumentService` as the default project document bridge. It fails when `ProjectStyioLanguageService` defaults directly to `LocalStyioLanguageService`, so this is a real architectural dependency, not only a documentation issue.

The required direction is:

```text
ProjectStyioLanguageService
  -> ProjectStyioDocumentService
    -> ProjectDocumentRuleProvider
      -> ProjectDocumentRuleRegistry.current
        -> CurrentProjectDocumentRuleProvider
          -> ProjectDocumentDiagnostics
          -> ProjectDocumentQuickFixProvider
          -> StyioSymbolIndex
        -> future StyioService-backed project-rule providers
  -> StyioService facts when available
```

`LegacyProjectDocumentRuleProvider` may remain only as an explicit compatibility adapter. It must not become the default project-document provider again.

`SimpleStyioLanguageService` may remain as a legacy implementation file for older compatibility imports and explicit adapters, but the new `view_ide` language and service barrel exports must not expose it as a current Language Service entrypoint.

Provider registry resolution is capability-aware. `LanguageProviderRegistry.resolve(languageId, capability: ...)` must choose a provider that explicitly advertises the requested capability, such as `completion`, `diagnostics`, `hover`, `definition`, or `semantic-tokens`. Capability IDs should use the same wire values as `StyioServiceCapability` where the capability overlaps StyioService. This allows Vityo to route different language capabilities to StyioService, local fallback, or future providers without changing the editor command surface.

`SemanticSnapshot` can be built from local syntax or from `StyioDocumentAnalysis` facts. The analysis-backed path binds `DocumentSymbol` and `ReferenceSpan` records into `ResolvedElement` and `ResolvedReference`, so cached StyioService facts and local fallback facts can share the same navigation foundation.

`StyioServiceResultAdapter.semanticSnapshot` is the service-result entrypoint for that binding. It first merges local analysis with a fresh `StyioServiceResponse`, then builds a `SemanticSnapshot` from the merged facts. This gives upper layers a direct way to consume StyioService-backed `ResolvedElement` / `ResolvedReference` without reading protocol DTOs or duplicating merge/stale logic.

Document revision is part of the language-service truth boundary. Cached
language-service features must read through `documentId + revision +
protocolVersion + toolchainId`, and stale cached revisions must not feed
diagnostics, completion, hover, semantic spans, references, rename, or derived
semantic-snapshot fallbacks. The regression anchor is
`cached language service rejects stale cached revision for IDE features`.

## 6. Toolchain Contract Binding

`ToolchainStyioServiceConnector` must request a language-service toolchain that satisfies the protocol contract used by `StyioCliJsonlProtocol`.

Current binding:

```text
StyioCliJsonlProtocol.protocolVersion
  -> ToolchainRequirement.metadata['contract']
    -> ToolchainResolver
      -> ToolchainRuntime
        -> selected Styio language-service executable
```

The default protocol contract token is `styio-cli-jsonl-v1`. A discovered Styio language-service descriptor must advertise the same `contract` metadata before the connector runs it.

This keeps Styio protocol compatibility in Toolchain resolution instead of letting Language Service execute whichever active binary happens to be selected.

`ToolchainStyioServiceConnector.checkHealth` exposes Toolchain Runtime preflight to Language Service callers. It uses the same protocol contract requirement as document analysis, so editor recovery/status UI can distinguish missing, mismatched, and executable-failing StyioService toolchains before a full analysis request is issued.

`ToolchainManagerStyioServiceConnector` is the managed-catalog variant. It loads the persisted `ToolchainCatalog` through `ToolchainManager`, creates a runtime from the current `PlatformManagerBundle`, and then delegates to the runtime-backed connector. This keeps StyioService startup aligned with Configuration-owned toolchain selection instead of requiring Language Service callers to manually assemble a runtime.

`StyioServiceToolchainCacheInvalidator` is the Language Service binding point for
Toolchain catalog changes. It consumes `ToolchainCatalogConfigurationChange`
events from Toolchain Configuration, retains cached StyioService results for the
currently active language-service toolchain, and clears cached results when the
catalog is deleted or no language-service toolchain is active.

```text
ToolchainCatalogConfigurationChange
  -> StyioServiceToolchainCacheBinding
    -> StyioServiceToolchainCacheInvalidator
    -> StyioServiceResultCache.retainToolchains / clear
      -> CachedStyioLanguageService stops serving stale toolchain facts
```

`StyioServiceToolchainCacheBinding` owns the stream subscription to
`ToolchainConfigurationStore.watchCatalog(...)` or an equivalent catalog-change
stream. Product wiring should create and dispose this binding with the language
service session instead of manually calling the invalidator.

When `StyioServiceToolchainCacheBinding` is given a
`StyioServiceResultCacheManifestStore`, it keeps the persisted manifest aligned
with cache invalidation: retained cache entries rewrite the metadata manifest,
and an empty cache deletes the manifest.

This keeps diagnostics, semantic facts, hover, completion, references, and
rename results bound to the selected Styio toolchain instead of letting old
toolchain responses survive a configuration change.

## 7. Language Result Cache Manifest

`StyioServiceResultCache.snapshot` is the status and debug surface for cached StyioService results.

`StyioServiceResponse.toolchainId` is part of cache identity. Connectors that launch a real toolchain must propagate the resolved `ToolchainRuntimeResult.toolchainId` into the response, and `StyioServiceResultCache.store` must use that id by default. This prevents results from different Styio versions or channels from sharing one document/revision cache slot.

When a caller does not specify a `toolchainId`, `StyioServiceResultCache.lookupDocument` may return a cached result only if exactly one matching toolchain entry exists for the document, revision, and protocol version. If multiple toolchains have results for the same document version, lookup returns no result rather than mixing Styio versions.

It exposes:

| Field family | Meaning |
|---|---|
| Identity | `documentId`, `revision`, `protocolVersion`, and `toolchainId`. |
| Status | `StyioServiceStatus` and optional failure message. |
| Fact counts | Diagnostics, completions, hovers, semantic spans, formatting edits, semantic blocks, inlay hints, document symbols, references, code actions, rename plans, refactoring plans, and parameter info counts. |

It must not expose raw language payloads such as diagnostic messages, completion labels, hover markdown, edit text, symbol names, reference ranges, or refactoring edits.

The cache snapshot is for observability and recovery UI only. Language behavior must still read fresh cache entries through `CachedStyioLanguageService` or project-rule providers that perform stale-response checks.

## 8. Analysis Report Surface

`StyioServiceAnalysisDriver.analyzeDocumentWithReport` is the status-aware analysis path.

It returns:

| Field | Meaning |
|---|---|
| `analysis` | The merged Vityo analysis after local fallback and StyioService response handling. |
| `response` | The raw `StyioServiceResponse` status, message, protocol version, and toolchain id. |
| `cachedResponseStored` | Whether a fresh response was written to `StyioServiceResultCache`. |
| `cacheSnapshot` | Optional manifest snapshot for this document. |

The existing `analyzeDocument` method remains the simple analysis-only path and delegates to the report method.

`StyioServiceCapabilityDetector.detectReport` converts an analysis report into a capability snapshot, preserving document revision and toolchain identity. UI and recovery surfaces should use this route instead of reconstructing capability state from unrelated response/cache objects.

Capability snapshots expose `toJson` for status surfaces. The JSON manifest contains document identity, protocol version, toolchain id, capability ids, states, and optional status messages only; it must not include diagnostics, completion labels, hover markdown, edit text, symbol names, or other language payloads.

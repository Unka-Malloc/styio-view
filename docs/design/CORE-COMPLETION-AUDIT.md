# Vityo Core Completion Audit

**Purpose:** Record the Vityo Core Completion Audit reference material for Vityo architecture, release, or maintenance work.

**Last updated:** 2026-05-17

This audit maps the active core implementation objective to concrete artifacts and verification evidence. It is intentionally stricter than a test summary: a passing test suite is evidence only when it covers the stated requirement.

## 1. Objective Restated As Deliverables

```text
1. Complete the environment foundation chain:
   Foundation <- Platform Manager <- Platform Adapter <- Platform Context <- Platform Detector

2. Complete Configuration + Toolchain.

3. Implement a functionally complete Language Service.
```

For this audit, "complete" means:

| Deliverable | Success criteria |
|---|---|
| Foundation | Provides reusable DataStore, resource coordination, credential storage, and shared base contracts without depending on higher layers. |
| Platform Detector | Produces platform component facts from probers without owning higher-level behavior. |
| Platform Context | Stores composable platform facts such as file system, shell, process, network, resource, clipboard, notification, local service, and PTY facts. |
| Platform Adapter | Converts platform facts into compatibility decisions without direct product behavior. |
| Platform Manager | Exposes system-specific managers that functional layers can call without talking to raw OS APIs directly. |
| Configuration | Persists IDE settings, shell/environment overlays, credentials, and Toolchain catalog state through Foundation/DataStore. |
| Toolchain | Resolves, configures, verifies, installs, runs, and reports toolchains, including signed managed-download provenance. |
| Language Service | Connects to real Styio language truth, caches project-context results, exposes diagnostics/completion/hover/semantic/reference/rename facts, and keeps UI fallback clearly separated from compiler truth. |

## 2. Prompt-To-Artifact Checklist

| Requirement | Primary artifacts | Verification evidence | Current verdict |
|---|---|---|---|
| Foundation exists as a lower layer | `frontend/vityo_app/lib/src/view_ide/foundation/` | `flutter test test/foundation_test.dart test/credential_data_store_test.dart` was included in the focused core suite. | Covered by focused tests, not independently audited line-by-line in this file. |
| Platform Detector exists below Context | `frontend/vityo_app/lib/src/view_ide/environment/system_compatibility/platform_detector/` | Focused platform tests in the core suite cover Platform Context and system compatibility managers. | Implemented surface present; full detector-by-detector audit still pending. |
| Platform Context stores facts, not behavior | `frontend/vityo_app/lib/src/view_ide/environment/system_compatibility/platform_context/` | `test/platform_context_test.dart` was included in focused core suite. | Covered by focused tests. |
| Platform Adapter derives compatibility from facts | `frontend/vityo_app/lib/src/view_ide/environment/system_compatibility/platform_adapter/` | `test/system_compatibility_managers_test.dart` was included in focused core suite. | Covered by focused tests. |
| Platform Manager exposes system managers | `frontend/vityo_app/lib/src/view_ide/environment/system_compatibility/platform_manager/platform_manager.dart` | Full Flutter test after latest changes passed. | Covered as integration surface; manager-by-manager completion audit still pending. |
| File System Manager supports upper layers | `frontend/vityo_app/lib/src/view_ide/environment/system_compatibility/file_system/` | `test/file_system_manager_test.dart` was included in focused core suite. | Covered by focused tests. |
| Shell Manager / PTY Manager support runtime use | `frontend/vityo_app/lib/src/view_ide/environment/system_compatibility/shell/`, `frontend/vityo_app/lib/src/view_ide/environment/system_compatibility/pty/` | `test/shell_manager_test.dart`, `test/pty_manager_test.dart`, and terminal runtime tests pass. | Covered by focused tests. |
| Configuration persists settings via Foundation | `frontend/vityo_app/lib/src/view_ide/environment/configuration/` | `test/configuration_toolchain_test.dart` passes. | Covered. |
| Credentials do not live in ordinary config | `FoundationCredentialDataStore`, `CredentialDataStore`, `ConfigurationStore` | Credential and raw-secret rejection tests pass in `test/configuration_toolchain_test.dart`. | Covered. |
| Environment overlays are IDE-local, not OS mutations | `environment_variable_configuration.dart` | Environment overlay tests pass in `test/configuration_toolchain_test.dart`. | Covered. |
| Toolchain catalog persists and scopes by platform | `toolchain_catalog.dart`, `toolchain_configuration_store.dart`, `toolchain_manager.dart` | Catalog, selection, platform target scoping, and manager tests pass in `test/configuration_toolchain_test.dart`. | Covered. |
| Toolchain managed downloads verify bytes | `toolchain_install_executor.dart` | Checksum, size, staging, binary preservation, and mismatch tests pass. | Covered. |
| Toolchain managed downloads verify signed provenance | `toolchain_provenance_verifier.dart`, `toolchain_install_policy.dart`, `toolchain_install_executor.dart` | `test/toolchain_provenance_verifier_test.dart` passes. | Covered for Ed25519 verifier boundary and executor integration. |
| Toolchain catalog/config can carry signed download metadata | `toolchain_managed_download_config.dart` | `test/toolchain_managed_download_config_test.dart` passes. | Covered for metadata persistence and plan generation. |
| Real Styio release provenance assets are present | Release catalog entries, real public keys, real signature URLs, signed artifacts | No real release key/signature asset was provided in this repo. | Not complete. Requires Styio release process inputs. |
| App bootstrap seeds Styio language-service toolchain catalog | `app_bootstrap.dart` | `test/app_bootstrap_toolchain_test.dart` passes in full Flutter suite. | Covered for local bootstrap behavior. |
| Language Service connects to Styio CLI diagnostics | `styio_service_connector.dart`, `styio_service_runtime.dart` | Connector, runtime, fixture gate, and language status tests pass. | Covered for current CLI diagnostics path. |
| Language Service can consume published Styio facts envelopes and explicit capability states | `styio_service_connector.dart`, `styio_service_capability_detector.dart`, `STYIO-SERVICE-PROTOCOL-CONTRACT.md`, `test/fixtures/styio_service/facts_envelope.jsonl` | Connector/capability filtered test -> `+8 All tests passed`; language status surface test -> `+6 All tests passed`. | Covered for Vityo-side future facts ingestion and capability declaration contract. |
| Language result cache is project-context aware | `styio_service_connector.dart`, `styio_service_project_document_rule_provider.dart` | `test/language_result_cache_context_binding_test.dart` and project provider tests passed in focused language suite. | Covered. |
| Diagnostics surface can consume service output | Routed/cached language service, editor status widgets | Full Flutter test passed, including language service status widget and smoke tests. | Covered for current service/fallback output. |
| Completion/hover/semantic/reference/rename consume real Styio facts | Language service payload/fact adapters, semantic snapshot, editor features | UI and fallback feature tests pass, but current real Styio CLI does not emit observed JSONL facts for completion, hover, semantic tokens, symbols, or references. | Not complete as real StyioService capability. |
| Full frontend tests pass after latest core changes | `frontend/vityo_app` | `flutter test` -> `+844 ~9 All tests passed`. | Covered for Flutter frontend. |
| Full repo delivery gates pass | Repo-level scripts, docs gates, CI gates | Not run in this audit. | Not complete. |

## 3. Latest Verification Snapshot

Focused Toolchain provenance/config tests:

```text
flutter test \
  test/toolchain_managed_download_config_test.dart \
  test/toolchain_provenance_verifier_test.dart \
  test/configuration_toolchain_test.dart

+54 All tests passed
```

Focused Platform Manager bundle contract test:

```text
flutter test test/platform_manager_bundle_contract_test.dart

+1 All tests passed
```

Focused Language Service protocol/capability tests:

```text
flutter test test/styio_service_connector_test.dart --name "JSONL protocol|capability detector"

+8 All tests passed
```

Focused Language Service status surface tests:

```text
flutter test test/language_service_status_surface_test.dart test/editor_language_service_status_widget_test.dart

+6 All tests passed
```

Frontend-wide Flutter suite:

```text
flutter test

+844 ~9 All tests passed
```

Latest upstream Styio CLI boundary check:

```text
/home/unka/Unka-Malloc/styio-nightly/build/bin/styio \
  --parser-engine nightly \
  --error-format jsonl \
  --file test/fixtures/styio_language/syntax_contract/value.true.styio

status=0
stdout_bytes=0
stderr_bytes=0
```

```text
/home/unka/Unka-Malloc/styio-nightly/build/bin/styio \
  --parser-engine nightly \
  --error-format jsonl \
  --file test/fixtures/styio_language/syntax_contract/unknown-token.false.styio

status=3
stderr includes one JSONL ParseError diagnostic.
```

Earlier focused Foundation / Platform / Configuration / Toolchain suite:

```text
flutter test \
  test/foundation_test.dart \
  test/credential_data_store_test.dart \
  test/platform_context_test.dart \
  test/system_compatibility_managers_test.dart \
  test/file_system_manager_test.dart \
  test/shell_manager_test.dart \
  test/pty_manager_test.dart \
  test/configuration_toolchain_test.dart \
  test/toolchain_status_surface_test.dart \
  test/toolchain_status_widget_test.dart

+124 All tests passed
```

## 4. Explicit Non-Completion Items

| Gap | Why it prevents completion | Next concrete action |
|---|---|---|
| Real Styio release provenance assets are absent. | Vityo can verify signed managed downloads, but cannot ship a complete managed install path without real release keys, signature URLs, and signed artifacts. | Add real release metadata when the Styio release process provides public keys and signature assets. |
| Real StyioService semantic facts are absent from current CLI output. | Vityo can route/cache/display facts, but completion/hover/semantic/reference/rename cannot be called functionally complete until facts come from Styio language truth. | Integrate the embedded/API/LSP contract once `styio-nightly` exposes semantic facts. |
| Clipboard, Notification, and Local Service managers have only bundle-level/product-agnostic evidence. | The Platform Manager set is complete and audited, but these managers do not yet have concrete upper-layer product workflows. | Add product-path tests when clipboard, notification, or local-service consumers are implemented. |
| Full repo delivery gates have not been run. | Flutter tests do not cover docs gates, repo hygiene, or any external delivery checks. | Run repo-level delivery gates when the implementation scope is ready for closure. |

## 5. Safe Status Statement

The current state is:

```text
Foundation, Platform, Configuration, and Toolchain have substantial implemented surfaces with passing focused and frontend-wide tests.
Toolchain managed-download provenance now has Ed25519 verifier and catalog/config metadata support.
Language Service is strong on Vityo-side routing, caching, UI integration, and fallback features, but it is not functionally complete against real Styio language truth until upstream StyioService emits semantic facts.
The active objective must not be marked complete yet.
```

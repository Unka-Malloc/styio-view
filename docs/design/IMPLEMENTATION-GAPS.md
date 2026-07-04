# Vityo Core Implementation Gaps

**Purpose:** Record the Vityo Core Implementation Gaps reference material for Vityo architecture, release, or maintenance work.

**Last updated:** 2026-05-17

This document records objective-level gaps for the current core implementation goal:

```text
Foundation <- Platform Manager <- Platform Adapter <- Platform Context <- Platform Detector
Configuration + Toolchain
Functionally complete Language Service
```

It is not a replacement for module design documents. It only records why the current implementation must not be treated as complete yet.

For the checklist-style objective audit, see `docs/design/CORE-COMPLETION-AUDIT.md`.

## 1. Current Evidence Snapshot

| Area | Evidence currently present | Status |
|---|---|---|
| Foundation | `docs/design/foundation/README.md`; `frontend/vityo_app/lib/src/view_ide/foundation/`; `foundation_test.dart` and related owner/datastore tests. | Implemented surface exists; focused Foundation tests pass. |
| Platform stack | `Platform Detector -> Platform Context -> Platform Adapter -> Platform Manager` is documented in `docs/design/environment/README.md` and implemented under `environment/system_compatibility/`. | Implemented surface exists; focused Platform manager tests pass. |
| Configuration | Configuration Store, Credential DataStore, environment overlays, and shell configuration are documented and tested. | Implemented surface exists; focused Configuration tests pass. |
| Toolchain | Toolchain Manager, discovery, catalog persistence, runtime, install policy, install executor, Styio language-service catalog bootstrap, Ed25519 provenance verifier boundary, and managed-download provenance catalog metadata are present. | Implemented surface exists; focused Toolchain tests pass, but real Styio release provenance assets are not populated. |
| Language Service | Routed/cached service, result adapter, capability detector, project document service, project language service, fixture matrix, and Styio CLI connector are present and tested. | Vityo-side service is substantially implemented; upstream StyioService facts are incomplete. |

## 2. Known Blocking Gaps

| Gap | Owner | Why it blocks "complete" |
|---|---|---|
| Styio CLI currently emits JSONL diagnostics for parse failures, but does not currently emit observed JSONL completion, hover, semantic token, symbol, or reference facts. | StyioService / Styio toolchain upstream, consumed by Vityo Service. | Vityo can route, cache, display, and derive from facts, but a functionally complete language service needs real upstream language facts. |
| Real Styio release provenance assets are not populated. | Styio release process / Vityo Toolchain configuration. | Vityo can now persist managed-download metadata, carry trusted public keys, plan signed downloads, and verify Ed25519 signatures before staging, but complete managed install requires real release keys, signature URLs, and signed artifacts from the Styio release process. |
| Full all-gates completion audit has not been performed for every Platform Manager component and integration path. | Vityo Environment. | Focused manager tests pass, but the objective requires complete delivery evidence, not only focused test evidence. |
| Full repo delivery gates beyond frontend Flutter tests have not been performed after the latest core changes. | Vityo repo delivery. | The frontend Flutter suite is green, but repo-level delivery gates and objective-level completion audit are broader than Flutter tests alone. |

## 3. Non-Blocking But Important Follow-Ups

| Follow-up | Reason |
|---|---|
| Add a stable embedded or daemon StyioService contract once upstream exposes parser/semantic API facts. | Avoid parsing CLI text output and keep Vityo decoupled from Styio implementation internals. |
| Populate production Toolchain release trust roots and signature metadata. | The config and verifier path exists, but managed downloads need real Styio release provenance inputs instead of test-only keys. |
| Build a checklist-driven completion audit for Foundation, Platform, Configuration, Toolchain, and Service. | Prevents treating substantial implementation effort as completion proof. |
| Run full repo gates only when the current change set is ready for delivery closure. | Focused tests are sufficient during implementation, but not for final completion. |

## 4. Focused Verification Evidence

The following focused verification has been run during the current implementation pass:

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

This provides focused evidence for Foundation, Platform Context, Platform Manager components, Configuration, and Toolchain. It does not replace a full completion audit or full repo gate run.

Additional Toolchain provenance verification evidence:

```text
flutter test \
  test/toolchain_managed_download_config_test.dart \
  test/toolchain_provenance_verifier_test.dart \
  test/configuration_toolchain_test.dart

+54 All tests passed
```

Latest frontend-wide verification:

```text
flutter test

+844 ~9 All tests passed
```

Latest upstream Styio CLI boundary check:

```text
<styio-workspace>/build/bin/styio \
  --parser-engine nightly \
  --error-format jsonl \
  --file test/fixtures/styio_language/syntax_contract/value.true.styio

status=0
stdout_bytes=0
stderr_bytes=0
```

```text
<styio-workspace>/build/bin/styio \
  --parser-engine nightly \
  --error-format jsonl \
  --file test/fixtures/styio_language/syntax_contract/unknown-token.false.styio

status=3
stderr includes one JSONL ParseError diagnostic.
```

This confirms the current upstream CLI still provides syntax diagnostics evidence, not completion/hover/semantic/reference facts.

Current dependency note:

```text
frontend/vityo_app/pubspec.yaml includes crypto for SHA-256 hashing and cryptography for Ed25519 signature verification.
Toolchain descriptor metadata can store managedDownload config, including download URI, SHA-256, size, signature URI, trusted hosts, and trusted Ed25519 public keys.
```

Therefore Vityo must not treat checksum verification or an unsigned JSON manifest as signature/provenance verification. `requireManagedDownloadSignature` must only plan managed downloads when a provenance signature URI and trusted public key are available.

## 5. Current Safe Statement

The current implementation is advancing core and necessary functionality. It should be described as:

```text
Foundation, Platform, Configuration, Toolchain, and Language Service have substantial implemented surfaces and focused tests.
The full objective is not complete because upstream language facts, real Styio release provenance assets, and full completion audit coverage remain open.
```

Do not mark the active goal complete until each blocking gap has either been implemented or explicitly removed from the objective.

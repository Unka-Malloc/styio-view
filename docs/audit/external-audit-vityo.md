# External Audit: Vityo

**Purpose:** External audit report for the 2026-04-22 `Vityo` review using `styio-audit` project `Vityo` and module `for-vityo`.

**Last updated:** 2026-05-02

**Date:** 2026-04-22
**Scope:** `Vityo`, audited through the external `styio-audit` framework with `project=Vityo` and module `for-vityo`.
**Status:** Open findings remain.

This report records the code audit outcome for the Flutter workspace, adapter, module, runtime, and platform lifecycle surfaces in `Vityo`. The audit intentionally focuses on the seven design principles, lifecycle state machines, test coverage, gate strictness, and UI/state consistency.

## Bottom Line

The repo has a strong amount of surface-area coverage already. During the parallel remediation pass, the original critical/high findings were narrowed substantially:

1. The prototype dev server now has Host/Origin checks, per-process API credentials, workspace-limited file-content reads, and mutations disabled by default.
2. The hosted control-plane IO client now requires a bearer token, validates endpoint URIs, uses request timeouts, and bounds response reads.
3. The execution overlay now snapshots files instead of symlinking back to the source workspace and uses resolved path containment.
4. Shell-level command gating, web hosted-client hardening, route text precision, and live product gates remain open follow-up areas.

The downstream `nightly` delivery line now uses repository-local `local-ci-gate`, `windows-native`, and `macos-native` workflow jobs so the default quality signal includes repository hygiene, docs governance, Flutter analyze/test, prototype editor selftest, and host-native desktop debug builds.

## Parallel Remediation Shards

- [Prototype Server Hardening Finding Shard](./agent-findings/prototype-server-hardening.md) closes the unauthenticated local API boundary for the prototype server with token/cookie auth, Host/Origin validation, and default-off mutations.
- [View Hosted Control Plane Client Hardening](./agent-findings/hosted-control-plane-client-hardening.md) closes the IO hosted-client timeout, response-size, auth-header, route-construction, and malformed-response gaps.
- [Execution Overlay Hardening Audit Shard](./agent-findings/execution-overlay-hardening.md) closes the overlay write-through and symlink escape class for the IO execution adapter.

## Findings

### Critical

1. `prototype/dev_server.py` exposed unauthenticated local file and workspace mutation APIs. This is remediated for the prototype boundary: API routes now require the local session credential or explicit token, mutating routes also require same-origin requests, and file mutations are disabled unless `STYIO_DEV_SERVER_ENABLE_MUTATION=1` is set.
   - Evidence: `prototype/dev_server.py:198`, `prototype/dev_server.py:305`, `prototype/dev_server.py:366`, `prototype/dev_server.py:381`, `prototype/dev_server.py:435`
   - Principles: 5 Secure And Bounded, 4 Fail Closed, 7 Recoverable Evolution

### High

2. `_IoHostedControlPlaneClient` concatenated base URLs as strings, did not model auth or tokens, had no timeout, and drained the full response before decode. The IO client now validates URIs, requires `VITYO_HOSTED_TOKEN`, applies request timeouts, disables redirects, and bounds streamed response reads.
   - Evidence: `frontend/vityo_app/lib/src/backend_toolchain/hosted_control_plane_io.dart:258`, `:274`, `:293`
   - Principles: 3 Typed Contracts, 4 Fail Closed, 5 Secure And Bounded, 6 Evidence Must Match The Claim

3. The execution overlay linked source workspace entries into a temporary directory. The IO adapter now builds a bounded snapshot, skips symlink entries, and blocks changed project active files that resolve outside the workspace root.
   - Evidence: `frontend/vityo_app/lib/src/backend_toolchain/execution_adapter_io.dart:1229`, `:1251`, `:1263`, `:1295`
   - Principles: 5 Secure And Bounded, 7 Recoverable Evolution

4. `ShellModel.executeCommand` still lets run-path execution reach the adapter directly, rather than gating from the route snapshot first. That weakens the command state machine and makes blocked routes depend on downstream adapter behavior.
   - Evidence: `frontend/vityo_app/lib/src/app/state/shell_model.dart:118`, `:136`, `:227`
   - Principles: 2 Explicit Ownership, 4 Fail Closed, 6 Evidence Must Match The Claim

5. Hosted IO response parsing now treats HTTP status, malformed JSON, non-object success bodies, oversized bodies, and malformed envelope fields as first-class failure modes. Higher-level adapters can still expose some hosted failures as raw exceptions.
   - Evidence: `frontend/vityo_app/lib/src/backend_toolchain/hosted_control_plane_io.dart:289`, `:293`, `:300`
   - Principles: 3 Typed Contracts, 4 Fail Closed, 5 Secure And Bounded

### Medium

6. Execution-overlay path-containment checks now resolve real paths before comparison. Some non-overlay route-selection paths should still be reviewed before the broader class is declared fully closed.
   - Evidence: `frontend/vityo_app/lib/src/backend_toolchain/execution_adapter_io.dart:1431`, `:1440`; `frontend/vityo_app/lib/src/backend_toolchain/project_workflow_selection.dart:128`, `:141`
   - Principles: 3 Typed Contracts, 5 Secure And Bounded

7. `AppBootstrap` advertises cloud capability from platform alone, not from a resolved hosted config or workspace state. That can overstate availability in the UI and route summaries.
   - Evidence: `frontend/vityo_app/lib/src/app/app_bootstrap.dart:100`, `:106`
   - Principles: 2 Explicit Ownership, 6 Evidence Must Match The Claim

8. `RuntimeSurface` always pulls the CLI capability detail for the execution banner, even on hosted/cloud or FFI routes. The UI can therefore describe the wrong route.
   - Evidence: `frontend/vityo_app/lib/src/runtime/runtime_surface.dart:60`, `:98`, `:142`
   - Principles: 2 Explicit Ownership, 6 Evidence Must Match The Claim

9. Active document loads in `ShellModel` are fire-and-forget. Rapid file switching can still write stale state or drop load errors if the pending load resolves after the active path changed.
   - Evidence: `frontend/vityo_app/lib/src/app/state/shell_model.dart:361`, `:582`, `:589`
   - Principles: 3 Typed Contracts, 4 Fail Closed, 7 Recoverable Evolution

### Low

10. Product workflow tests are gated by `VITYO_PRODUCT_GATE=1`, so the default green path does not prove live product closure by itself. The repository-local CI gate covers Flutter analyze/test and prototype health; the live product workflow remains an explicit release-relevant extension lane.
    - Evidence: `frontend/vityo_app/test/local_product_workflow_test.dart:27`, `frontend/vityo_app/test/hosted_product_workflow_test.dart:29`, `.github/workflows/local-ci-gate.yml:1`
    - Principles: 6 Evidence Must Match The Claim, 7 Recoverable Evolution

## Lifecycle State Machines

### Workspace / Document

The workspace-document state machine is mostly present in docs and tests:

- Seeded and loaded document behavior is covered by `workspace_document_store_test.dart` and `editor_controller_editing_test.dart`.
- Dirty and saved transitions are covered by the editor/controller tests.
- The remaining gap is stale async load handling when `_loadActiveWorkspaceDocument()` resolves after the active file has already changed.

Observed states: `seeded -> loaded -> dirty -> saving -> saved -> failed -> disposed`.

### Adapter / Command

The adapter-command machine is present in the code, but shell-level gating is still too permissive:

- `blocked`, `ready`, `running`, `succeeded`, `failed`, and cleanup behavior are modeled.
- The `run` command still delegates too early.
- Hosted failure parsing still relies on JSON assumptions instead of typed failure classification.

Observed states: `unavailable -> ready -> running -> succeeded|failed -> cleaned`.

### Module Lifecycle

Module lifecycle is the most coherent of the four major machines:

- Core modules stay mounted and cannot be uninstalled.
- Optional modules can be staged, mounted, or uninstalled with explicit data-reclamation flags.
- The existing `module_lifecycle_test.dart` coverage matches the expected mount/uninstall state transitions.

Observed states: `declared -> available -> enabled|disabled -> staged|uninstalled -> failed`.

### Runtime Replay

Runtime replay and debug lanes are well represented in the UI model and tests:

- `runtime_surfaces_test.dart` covers rendering of a published runtime event replay.
- `hosted_control_plane_client_test.dart` covers runtime event ingestion for hosted workflows.
- The remaining risk is stale or misleading route text when the active adapter kind is not CLI.

Observed states: `empty -> recording -> replayed -> summarized -> rendered -> cleared -> failed`.

## Test Coverage

I ran the following Flutter tests successfully:

```text
flutter test test/module_lifecycle_test.dart test/runtime_surfaces_test.dart test/hosted_control_plane_client_test.dart test/shell_model_test.dart test/execution_adapter_test.dart test/workspace_document_store_test.dart
```

Coverage strengths:

- module lifecycle transitions
- runtime replay rendering
- hosted control-plane workflow lanes
- shell command dispatch
- execution adapter routing
- workspace document persistence

Coverage gaps:

- web hosted-control-plane parity with the hardened IO client
- stale async document-load rejection
- direct regression coverage for route gating on `run`
- live hosted/local product gates without environment opt-in

## Gate Strictness

Before this audit, `styio-audit` validated the framework and project module, but the full gate was blocked by an ignored open defect queue record in `docs/audit/defects/STYIO-VIEW-2026-04-22.md`. That scratch record has been migrated into this tracked audit report and [NEXT-STAGE-GAP-LEDGER.md](../rollups/NEXT-STAGE-GAP-LEDGER.md), and the ignored scratch file is removed before submission.

The downstream delivery workflow now exposes `local-ci-gate`, `windows-native`, and `macos-native` as required repository-local CI statuses for `nightly`, instead of the older `styio-ci` / `build-and-test` naming. They run the composed delivery gate with external `styio-audit` skipped because the released policy gate runs separately in `.github/workflows/styio-audit.yml`.

The product workflow tests remain environment-gated, so they should continue to be treated as a release-relevant lane rather than proof from the default test run.

## Commands Run

- `python3 -m styio_audit.cli list-modules`
- `python3 -m styio_audit.cli validate-modules`
- `python3 -m styio_audit.cli gate --repo <vityo-workspace> --project Vityo --framework-only`
- `python3 -m styio_audit.cli gate --repo <vityo-workspace> --project Vityo`
- `flutter test test/module_lifecycle_test.dart test/runtime_surfaces_test.dart test/hosted_control_plane_client_test.dart test/shell_model_test.dart test/execution_adapter_test.dart test/workspace_document_store_test.dart`
- `python3 -m unittest prototype/test_dev_server_security.py`
- `flutter test test/hosted_control_plane_io_hardening_test.dart`
- `flutter test test/execution_adapter_test.dart`

## Remaining Risks

1. Web hosted-control-plane hardening still needs parity with the IO client.
2. Product workflow coverage still depends on an env-gated lane, so the full execution matrix is not yet default.
3. Shell run-route gating, route text precision, and stale async document-load rejection remain follow-up work.
4. `nightly` merge governance depends on GitHub Rulesets requiring `audit`, `styio-audit`, `local-ci-gate`, `windows-native`, and `macos-native` checks.

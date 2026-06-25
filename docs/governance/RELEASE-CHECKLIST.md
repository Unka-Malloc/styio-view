# Vityo Release Checklist

**Purpose:** Provide the release and checkpoint checklist for Vityo, including IDE architecture gates, compatibility facade validation, sandbox/security baseline checks, and performance budget evidence.

**Owner:** Governance owner (`CODEOWNERS` -> governance domain)
**Last updated:** 2026-06-25

## Release Rule

A release or checkpoint candidate must prove four things before it is cut:

1. The IDE architecture boundary still holds: `view_ide/` owns domain/application contracts and `view_render/` owns Flutter presentation.
2. Legacy import paths remain compatibility facades only; no new logic is added under migrated roots.
3. Sandbox, agent permission, module manifest security, redaction, and secret handling have explicit tests or gate coverage.
4. Performance-sensitive editor, language, workspace, runtime, AI context, watcher, and UI virtualization paths have benchmark files and a regression gate path.

## Required Commands

Run from the repository root unless a command states otherwise:

```bash
python3 scripts/docs-index.py --write
python3 -m pytest tests/test_docs_tooling_coverage.py
python3 scripts/check_architecture_boundaries.py
python3 scripts/check_compat_facades.py
python3 scripts/check_security_baseline.py
python3 scripts/check_performance_budgets.py
python3 scripts/release-readiness-gate.py --skip-build
git diff --check
```

For a full release candidate, also run:

```bash
./scripts/delivery-gate.sh --mode checkpoint
python3 scripts/release-readiness-gate.py
python3 scripts/performance-gate.py --threshold 1.10
```

Use `--skip-build` only for metadata, docs, or governance-only changes where a Flutter release build is not part of the evidence being claimed.

## PR Evidence Checklist

Every PR should state:

1. Which owner surfaces changed: architecture, agent, module, adapter, editor, workspace, governance, docs, or CI.
2. Which compatibility surfaces changed, including schema versions, deprecations, and facade roots.
3. Which security-sensitive files changed, especially sandbox, secret store, log redactor, module manifest security, and agent permission model.
4. Which performance-sensitive paths changed and whether `scripts/performance-gate.py` or `scripts/check_performance_budgets.py` was run.
5. Which docs and indexes were refreshed.

## IDE Architecture Gate

Architecture changes must pass:

```bash
python3 scripts/check_architecture_boundaries.py
```

The gate rejects:

1. `view_ide/` importing or exporting `view_render/`.
2. `view_ide/` importing Flutter presentation APIs.
3. `view_render/` importing unregistered `view_ide/` implementation files.
4. `view_render/` importing legacy compatibility roots.

New `view_render -> view_ide` dependencies require a narrow registration in `VIEW_RENDER_ALLOWED_VIEW_IDE_IMPORTS` in `scripts/check_architecture_boundaries.py` plus architecture review.

## Compatibility Facade Gate

Compatibility facade changes must pass:

```bash
python3 scripts/check_compat_facades.py
```

Legacy top-level `backend_toolchain/`, `editor/`, and `language/` files may only contain a single `export` statement that resolves under the allowed migrated target roots. Any parser, adapter, state, or UI logic must move to the owning `view_ide/` or `view_render/` surface instead of growing inside the facade.

## Sandbox And Security Gate

Security-sensitive changes must pass:

```bash
python3 scripts/check_security_baseline.py
```

The baseline currently requires these files to exist and stay free of known-dangerous patterns:

1. `frontend/vityo_app/lib/src/view_ide/environment/execution/execution_sandbox.dart`
2. `frontend/vityo_app/lib/src/view_ide/environment/configuration/log_redactor.dart`
3. `frontend/vityo_app/lib/src/view_ide/environment/configuration/secret_store.dart`
4. `frontend/vityo_app/lib/src/view_ide/module_host/module_manifest_security.dart`
5. `frontend/vityo_app/lib/src/view_ide/agent/agent_permission_model.dart`

Security review is required when a change alters permission elevation, subprocess execution, secret storage, log redaction, manifest trust, or network access.

## Performance Gate

Performance-sensitive changes must first pass the static budget coverage check:

```bash
python3 scripts/check_performance_budgets.py
```

When Dart or Flutter is available locally, run the benchmark regression gate:

```bash
python3 scripts/performance-gate.py --threshold 1.10
```

Use a custom baseline when reviewing a focused performance branch:

```bash
python3 scripts/performance-gate.py --baseline docs/review/performance-baseline.json --threshold 1.10
```

Do not save a new baseline with `--save-baseline` unless the PR explicitly explains why the new measurements are the accepted release floor.

## Deprecation And Migration

Breaking changes must not be hidden inside a release checklist. They require:

1. An ADR or governance note explaining the compatibility break.
2. A migration section in [API-COMPATIBILITY.md](./API-COMPATIBILITY.md).
3. A release note entry and affected owner review.
4. Gate updates proving old paths fail intentionally or remain as documented facades.

## Residual Risk Log

If a release candidate ships with known gaps, record them in:

1. [../rollups/NEXT-STAGE-GAP-LEDGER.md](../rollups/NEXT-STAGE-GAP-LEDGER.md) for active product/architecture gaps.
2. [../review/Logic-Conflicts.md](../review/Logic-Conflicts.md) for unresolved conflicts.
3. [../history/](../history/) for recovery notes after an interrupted checkpoint.

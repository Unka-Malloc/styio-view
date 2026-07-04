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

A formal product release candidate must additionally prove that the launch artifact is the production deliverable, not a debug, prototype, lab, or experimental build. Release closure requires platform release builds, packaging/signing or distribution evidence, release notes, install/update/uninstall behavior, rollback or recovery evidence, and no skipped build evidence for the claimed launch platform.

## CI Gate Classification

Every CI check listed below runs on every PR and push to `nightly`. The distinction between *default CI* and *opt-in product gate* is at the script level, not the workflow level: all workflows are always triggered, but certain gates inside them require explicit environment variables or external fixtures to execute their full product-matrix scope.

### Default CI (always runs, no external fixtures required)

| Workflow / Gate | What It Proves | Evidence Claim |
|-----------------|----------------|----------------|
| `repo-hygiene.yml` | Tracked-tree governance, dependency policy, supply chain, GitHub Actions pin, architecture boundary, compat facade, security baseline, performance budget, license policy, import boundary, ecosystem CLI doc, incoming history range | Repository hygiene and policy compliance is maintained |
| `audit.yml` | Supply chain governance, dependency policy, GitHub Actions pin audit, security baseline, license policy, architecture boundary, compat facade | Security, supply-chain, and architecture policy gates pass |
| `styio-audit.yml` | External styio-audit gate against released policy | Cross-repository audit policy is satisfied |
| `project-coverage-gate.yml` | Python coverage >= 95%, Flutter coverage >= 85% | Project coverage floors are met |
| `local-ci-gate.yml` (linux job) | `delivery-gate.sh --mode push` (no --skip-health, no --skip-ecosystem by default), `flutter build linux --release` | Linux delivery floor + native release build |
| `local-ci-gate.yml` (windows job) | `delivery-gate.sh --mode push --skip-audit`, `flutter build windows --release` | Windows delivery floor + native release build |
| `local-ci-gate.yml` (macos job) | `delivery-gate.sh --mode push --skip-audit`, `flutter build macos --release` | macOS delivery floor + native release build |
| `windows-native.yml` | `delivery-gate.sh --mode push --skip-audit`, `flutter analyze`, `flutter build windows --release`, upload coverage + build artifacts | Windows-specific delivery gate + release build + artifact upload |

### Opt-In Product Gates (require `VITYO_PRODUCT_GATE=1` and external fixtures)

These gates are **not** executed by default CI. They require explicit activation and external fixtures (Styio/Pafio executables, hosted control plane endpoints). Their passing state is **not** part of default CI green.

| Gate Script | What It Proves | Trigger |
|-------------|----------------|---------|
| `ecosystem-product-gate.py` | Full product workflow matrix: desktop-local and hosted/cloud lanes complete install/use/pin/fetch/vendor/pack/run/test/preflight; managed toolchain switch; multi-package workspace; filesystem registry distribution; registry conflict and missing-package failure; compile/dependency/preflight structured error return | `VITYO_PRODUCT_GATE=1` + external fixtures |
| `ecosystem-sample-workflow-gate.py` (styio-pafio sibling) | Cross-repo sample workflow: managed toolchain switch, vendored offline, registry-hosted source, explicit `--package` selection and publish-policy protection | `VITYO_PRODUCT_GATE=1` + styio-pafio checkout |
| Product coverage gate (within `delivery-gate.sh`) | Product-matrix coverage beyond default CI unit/widget test scope | `VITYO_PRODUCT_GATE=1` + external fixtures |

### What Default CI Green Means

Default CI green means:
- Repository hygiene, security, architecture, compat facade, performance budgets, and license policy all pass.
- Linux, Windows, and macOS each complete the delivery floor and produce a native `--release` Flutter build.
- Project coverage floors (Python 95%, Flutter 85%) are met.
- External styio-audit policy passes.

Default CI green does **not** mean:
- Full product workflow matrix has been executed (requires `VITYO_PRODUCT_GATE=1`).
- Cross-repository ecosystem sample workflows have passed.
- Platform packaging, signing, distribution, or install/update/uninstall have been verified.
- The build artifact is a production-signed, distributed release.

## Skip Flags And Closure Evidence

The delivery gate supports several `--skip-*` flags. Each has a narrow legitimate use. Using one in CI does not prove the skipped step passed; it proves only that CI chose not to run it.

| Flag | Legitimate Use | Cannot Claim |
|------|----------------|--------------|
| `--skip-build` | Metadata, docs, governance-only changes; non-release checkpoints where Flutter release build is not part of claimed evidence | Release build evidence for any platform being launched |
| `--skip-health` | Docs/process-only deliveries where checkpoint health (Flutter analyze, tests, coverage, selftest) is verified separately or is out of scope | That Flutter analyze, tests, coverage, or selftest passed |
| `--skip-audit` | Checkpoints where external styio-audit is enforced by the separate required `styio-audit` check; explicitly scoped docs/process recovery | That external audit policy is satisfied (use the separate styio-audit check for that) |
| `--skip-ecosystem` | Targeted recovery, not normal CI | That ecosystem CLI doc consistency was checked |

**Rule:** A PR or checkpoint claiming product closure must show positive evidence for every gate relevant to the claimed scope. Relying on `--skip-*` flags as evidence of passing is invalid. The evidence record must include the actual gate output or a reference to the CI run that executed that gate without the skip flag.

## Terminal Closure Constraint

The Better Plan checkpoint `6fd0bfe7-3d65-429f-8a6d-fd0a0fc08092` ("Clarify product gate default-CI evidence policy to launch-ready production release closure") is the terminal governance checkpoint in its chain. It cannot be marked **completed** unless the repository has launch-ready production release evidence meeting all criteria in the [Formal Product Launch Gate](#formal-product-launch-gate) section. Documentation-only clarification of the policy is necessary but not sufficient for closure — the checkpoint requires actual release evidence, not just policy text.

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
flutter build linux --release
flutter build windows --release
flutter build macos --release
```

Use `--skip-build` only for metadata, docs, governance-only changes, or non-release checkpoints where a Flutter release build is not part of the evidence being claimed. A formal product release cannot use `--skip-build` as release evidence for any platform being launched.

## Formal Product Launch Gate

Before declaring product launch readiness, the release owner must verify:

1. The launch channel has a production release artifact, not a debug or prototype artifact.
2. Linux, Windows, and macOS launch claims each have native `--release` build evidence when that platform is included in the release.
3. Platform-specific packaging, signing/notarization, installer/update/uninstall, release notes, and rollback or recovery evidence are attached to the release record.
4. Prototype governance and selftest evidence is treated only as regression evidence; it cannot replace release build, packaging, signing, or launch evidence.
5. Any unsupported or upstream-blocked capability is exposed as a user-visible capability gap with owner, reason, recovery guidance, and release-note coverage.

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

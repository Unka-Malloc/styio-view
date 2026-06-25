# Extension Module Runbook

**Purpose:** Define the extension/module domain owner's responsibilities, owned paths, review checklist, and required gates for Vityo's extension and contribution system. Enforce manifest schema validation, contribution routing, activation lifecycle, and extension isolation.

**Last updated:** 2026-06-24

## Mission

Own the Vityo extension and contribution model: extension manifest schema, typed contribution points, activation lifecycle, extension host isolation, capability matrix integration, and staged update mechanism. Enforce that extensions use Styio-native manifests (not VS Code API), contributions are typed (not string-based), and activation is capability-gated.

## Owned Surface

Primary paths:
1. `frontend/vityo_app/lib/src/view_ide/module_host/`
2. `frontend/vityo_app/assets/module_manifests/`
3. `frontend/vityo_app/assets/capability_matrices/`
4. `docs/design/Vityo-Extension-And-Contribution-Model.md`
5. `docs/teams/EXTENSION-MODULE-RUNBOOK.md`

Key SSOTs:
1. `扩展模型 -> ../design/Vityo-Extension-And-Contribution-Model.md`
2. `模块平台 Runbook -> ./MODULE-PLATFORM-RUNBOOK.md`
3. `API 兼容性 -> ../governance/API-COMPATIBILITY.md`
4. `ADR-0009 -> ../adr/ADR-0009-module-runtime-and-staged-updates.md`

## Daily Workflow

1. Review PRs touching extension/module paths against the review checklist.
2. Verify extension manifests have valid schemaVersion, unique ID, and satisfiable requiredCapabilities.
3. Verify contributions use typed Dart classes, not string identifiers.
4. Verify extension isolation level is appropriate for declared permissions.
5. Verify activation lifecycle (validate → register → activate → deactivate) is tested.
6. Verify staged update cycle (verify → stage → activate → rollback on failure).

## Change Classes

1. Small: New contribution point validation rule, minor manifest field addition. Run flutter test on extension tests.
2. Medium: New contribution point type, isolation level change, activation event addition. Run full extension test suite plus flutter analyze.
3. High: Manifest schema version bump, contribution routing change, extension security model change. Requires ADR and team review.

## Required Gates

Minimum:
```bash
cd frontend/vityo_app && flutter test test/extension_manifest_contract_test.dart test/extension_contribution_manifest_test.dart test/module_lifecycle_test.dart
cd frontend/vityo_app && flutter analyze
```

## Cross-Team Dependencies

1. Architecture team must review extension model changes.
2. Agent team must review agent provider/tool contribution changes.
3. Language team must review language contribution changes.
4. Theme/UX team must review theme contribution changes.
5. Security/governance team must review extension isolation and permission changes.

## Handoff / Recovery

Record:
1. Which contribution points were added or modified.
2. Which manifest schema changes were made.
3. Which activation events were added.
4. Which extension isolation rules were updated.
5. Next recovery point and pending extension features.

# Contributing To Vityo Nightly

**Purpose:** Give contributors and agents the repository-level workflow for safe changes, review routing, documentation updates, and local validation.

**Last updated:** 2026-06-25

## Start Here

Vityo nightly is a downstream integration repository. Multiple people and agents may edit the worktree at the same time, so every change must be narrow, owner-routed, and easy to recover.

Before changing files:

1. Check `git status --short` and treat unrelated dirty files as someone else's work.
2. Read the owning docs for the area you touch, starting with [docs/teams/COORDINATION-RUNBOOK.md](docs/teams/COORDINATION-RUNBOOK.md).
3. Keep product code, docs, scripts, and generated artifacts separated in the PR description.
4. Do not revert or rewrite unrelated concurrent changes.

## Owner Routing

Use these entry points:

1. Architecture and boundaries: [docs/teams/ARCHITECTURE-RUNBOOK.md](docs/teams/ARCHITECTURE-RUNBOOK.md)
2. Runtime and agent: [docs/teams/RUNTIME-AGENT-RUNBOOK.md](docs/teams/RUNTIME-AGENT-RUNBOOK.md)
3. Agent security and permission details: [docs/teams/AGENT-RUNTIME-RUNBOOK.md](docs/teams/AGENT-RUNTIME-RUNBOOK.md)
4. Module and platform: [docs/teams/MODULE-PLATFORM-RUNBOOK.md](docs/teams/MODULE-PLATFORM-RUNBOOK.md)
5. Adapter contracts: [docs/teams/ADAPTER-CONTRACTS-RUNBOOK.md](docs/teams/ADAPTER-CONTRACTS-RUNBOOK.md)
6. Docs and delivery: [docs/teams/DOCS-DELIVERY-RUNBOOK.md](docs/teams/DOCS-DELIVERY-RUNBOOK.md)
7. Governance: [docs/governance/README.md](docs/governance/README.md)

Root [CODEOWNERS](CODEOWNERS) is the current nightly owner map. Placeholder owners are routing labels until real GitHub team slugs are assigned; see [docs/governance/CODEOWNERS-POLICY.md](docs/governance/CODEOWNERS-POLICY.md).

## IDE Architecture Rules

Vityo separates domain/application code from Flutter presentation:

1. `frontend/vityo_app/lib/src/view_ide/` owns domain models, editor state, workspace state, agent permissions, module host contracts, backend toolchain contracts, and other non-Flutter application logic.
2. `frontend/vityo_app/lib/src/view_render/` owns Flutter widgets, surfaces, themes, responsive layout, and visual bindings.
3. `frontend/vityo_app/lib/src/app/` wires the layers together.
4. Legacy roots such as `backend_toolchain/`, `editor/`, and `language/` are compatibility facades only.

Run:

```bash
python3 scripts/check_architecture_boundaries.py
python3 scripts/check_compat_facades.py
```

## Compatibility And Deprecation

Public models, adapter contracts, module manifests, agent tool interfaces, workspace models, and configuration schemas follow [docs/governance/API-COMPATIBILITY.md](docs/governance/API-COMPATIBILITY.md).

When changing a public surface:

1. Preserve `schemaVersion` and unknown-field tolerance.
2. Add optional fields for compatible changes.
3. Treat required-field additions, removals, type changes, and semantic changes as breaking.
4. Document deprecations with replacement path, removal target, and migration evidence.
5. Keep old import paths as one-line facades only when compatibility is still required.

## Security Baseline

Security-sensitive changes must follow [SECURITY.md](SECURITY.md) and [docs/governance/SECURITY-AND-SUPPLY-CHAIN.md](docs/governance/SECURITY-AND-SUPPLY-CHAIN.md).

Run:

```bash
python3 scripts/check_security_baseline.py
```

This gate covers sandbox execution, log redaction, secret storage, module manifest trust checks, and agent permission modeling. Add tests for unauthorized, malformed, timeout, and oversized inputs whenever the changed code accepts external data or executes tools.

## Performance Baseline

Run the static budget coverage check for editor, language, workspace, runtime, AI context, watcher, or UI virtualization changes:

```bash
python3 scripts/check_performance_budgets.py
```

When Dart or Flutter is available locally, run:

```bash
python3 scripts/performance-gate.py --threshold 1.10
```

Do not update the performance baseline unless the PR intentionally changes the accepted release floor and explains the tradeoff.

## Documentation Updates

Update docs in the same change when behavior, architecture, ownership, security, compatibility, release gates, or local development commands change.

Common documentation commands:

```bash
python3 scripts/docs-index.py --write
python3 -m pytest tests/test_docs_tooling_coverage.py
git diff --check
```

For broader docs/process validation:

```bash
./scripts/docs-gate.sh
python3 scripts/repo-hygiene-gate.py --mode tracked
```

## Release Evidence

For release and checkpoint rules, use [docs/governance/RELEASE-CHECKLIST.md](docs/governance/RELEASE-CHECKLIST.md).

Fast static release evidence:

```bash
python3 scripts/release-readiness-gate.py --skip-build
```

Full release candidate evidence:

```bash
./scripts/delivery-gate.sh --mode checkpoint
python3 scripts/release-readiness-gate.py
```

## Pull Request Requirements

Every PR should include:

1. Scope summary and owner surfaces changed.
2. Tests and gates run, including skipped gates with reason.
3. Compatibility, deprecation, migration, and release-note impact.
4. Security and performance impact when relevant.
5. Residual risks or follow-up gaps.

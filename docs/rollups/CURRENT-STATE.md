# Current State

**Purpose:** Provide the compressed entry point for Vityo's current governance
and ecosystem-owner boundaries.

**Last updated:** 2026-07-30

## Summary

1. Vityo owns IDE presentation and adapter composition, not package,
   compiler, registry, or hosted-workspace truth.
2. Local project facts come only from `pafio metadata --json` (`metadata v1`).
   Missing or invalid metadata produces a blocked project snapshot rather than
   local manifest or cache inference.
3. Local project workflows use Pafio's stable workflow JSON. Pafio owns
   project sync, build orchestration, vendor, pack, and publish clients.
4. Compiler identity and capability come directly from
   `styio --machine-info=json`. Styio continues to own diagnostics, receipts,
   runtime events, and language-service contracts.
5. Hosted workspace lifecycle, registry control, cloud jobs, and workers come
   only from `Platform hosted-workspace v1`.
6. Vityo does not read Pafio private storage and does not install, select, pin,
   or cache Styio through Pafio.
7. The opt-in desktop product gate composes real Pafio metadata with a real
   system Styio machine contract. The coordinated ecosystem matrix additionally
   verifies Platform hosted and registry ownership at fixed revisions.
8. Documentation indexes, lifecycle checks, repository hygiene, security, and
   release evidence remain mandatory governance surfaces.

## Read Order

1. `../contracts/ProjectGraphAdapter.md`
2. `../contracts/HostedWorkspaceCloudRoutes.md`
3. `../external/for-pafio/Pafio-Metadata-Contract.md`
4. `../external/for-styio/Styio-Compile-Run-Contract.md`
5. `../external/for-platform/Platform-Hosted-Workspace-Contract.md`
6. `../teams/ADAPTER-CONTRACTS-RUNBOOK.md`

## Recovery Baseline

```bash
python3 scripts/docs-lifecycle.py refresh
python3 scripts/docs-index.py --write
python3 scripts/docs-audit.py
python3 scripts/repo-hygiene-gate.py --mode tracked
```

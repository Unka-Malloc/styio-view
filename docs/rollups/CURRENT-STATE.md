# Current State

**Purpose:** Provide the compact entry point for Vityo's product identity,
governance, and ecosystem-owner boundaries.

**Last updated:** 2026-07-30

## Summary

1. **Vityo is the agent-native IDE for Styio.** It is the sole user-facing
   product; compatible Agents connect through the versioned Vityo Agent
   Protocol.
2. Vityo owns source and workspace revisions, IDE presentation, adapter
   composition, permission presentation, change preview, and workspace
   transactions. Agent runtimes own provider access, context selection, tool
   loops, Agent policy, durable sessions, and multi-Agent orchestration.
3. Vityo does not own package, compiler, registry, or hosted-workspace truth.
   Editing, language service, build, test, run, and observation remain fully
   available without an Agent.
4. Local project facts come only from `pafio metadata --json` (`metadata v1`).
   Missing or invalid metadata produces a blocked project snapshot rather than
   local manifest or cache inference.
5. Local project workflows use Pafio's stable workflow JSON. Pafio owns project
   sync, build orchestration, vendor, pack, and publish clients.
6. Compiler identity and capability come directly from
   `styio --machine-info=json`. Styio owns diagnostics, receipts, runtime
   events, and language-service contracts.
7. Hosted workspace lifecycle, registry control, cloud jobs, and workers come
   only from `Platform hosted-workspace v1`.
8. Vityo does not read Pafio private storage and does not install, select, pin,
   or cache Styio through Pafio.
9. The opt-in desktop product gate composes real Pafio metadata with a real
   system Styio machine contract. The coordinated ecosystem matrix additionally
   verifies Platform hosted and registry ownership at fixed revisions.
10. Direct IDE-side provider/controller artifacts from the superseded Agent
    architecture remain migration inventory in
    `Vityo-Implementation-Gaps.md`; they are not accepted extension points.
11. Documentation indexes, lifecycle checks, repository hygiene, security, and
    release evidence remain mandatory governance surfaces.

## Read Order

1. `../design/Vityo-Product-Spec.md`
2. `../design/Vityo-Agent-Native-IDE-Architecture.md`
3. `../design/Vityo-System-Architecture.md`
4. `../design/Vityo-Implementation-Gaps.md`
5. `../contracts/ProjectGraphAdapter.md`
6. `../contracts/HostedWorkspaceCloudRoutes.md`
7. `../external/for-pafio/Pafio-Metadata-Contract.md`
8. `../external/for-styio/Styio-Compile-Run-Contract.md`
9. `../external/for-platform/Platform-Hosted-Workspace-Contract.md`
10. `../teams/ADAPTER-CONTRACTS-RUNBOOK.md`

## Recovery Baseline

```bash
python3 scripts/docs-lifecycle.py refresh
python3 scripts/docs-index.py --write
python3 scripts/docs-audit.py
python3 scripts/repo-hygiene-gate.py --mode tracked
```

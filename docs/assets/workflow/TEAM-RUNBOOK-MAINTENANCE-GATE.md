# Team Runbook Maintenance Gate

**Purpose:** Define the delivery gate that requires team runbooks under `docs/teams/` to be updated and kept in the standard template shape when files in corresponding team-owned folders are added, modified, renamed, or deleted.

**Last updated:** 2026-04-23

## Command

Local worktree gate:

```bash
python3 scripts/team-docs-gate.py
```

Staged-only gate:

```bash
python3 scripts/team-docs-gate.py --mode staged
```

Branch or CI gate:

```bash
python3 scripts/team-docs-gate.py --base origin/main
```

## Format Gate

All non-coordination runbooks must follow [TEAM-RUNBOOK-TEMPLATE.md](./TEAM-RUNBOOK-TEMPLATE.md) and contain these H2 sections, in order:

1. `Mission`
2. `Owned Surface`
3. `Daily Workflow`
4. `Change Classes`
5. `Required Gates`
6. `Cross-Team Dependencies`
7. `Handoff / Recovery`

`docs/teams/COORDINATION-RUNBOOK.md` must instead use:

1. `Mission`
2. `Module Map`
3. `Ownership Table`
4. `Review Matrix`
5. `Escalation Rules`
6. `Checkpoint Policy`
7. `Release / Cutover Gates`
8. `Handoff / Recovery`

## Folder Mapping

| Team doc | Watched paths |
|----------|---------------|
| `SHELL-EDITOR-RUNBOOK.md` | `products/vityo_app/lib/src/app/`, `products/vityo_app/lib/src/view_render/shell/`, `products/vityo_app/lib/src/view_render/editor/`, `products/vityo_app/lib/src/view_render/runtime/`, `products/vityo_app/lib/src/view_render/agent/`, `products/vityo_app/lib/src/view_render/theme/`, `products/vityo_app/lib/src/view_render/platform/`, `products/vityo_app/lib/src/ide/editor/`, `products/vityo_app/lib/src/editor/`, `products/vityo_app/lib/src/frontend_shell/`, `products/vityo_app/lib/src/view_ide/language/`, `products/vityo_app/lib/src/language/`, `prototype/` |
| `RUNTIME-AGENT-RUNBOOK.md` | `products/vityo_app/lib/src/view_ide/runtime/`, `products/vityo_app/lib/src/view_ide/agent/`, `products/vityo_app/lib/src/view_render/runtime/`, `products/vityo_app/lib/src/view_render/agent/`, `products/vityo_app/lib/src/runtime/`, `products/vityo_app/lib/src/agent/` |
| `MODULE-PLATFORM-RUNBOOK.md` | `products/vityo_app/lib/src/module_host/`, `products/vityo_app/lib/src/platform/`, module manifests, capability matrices, platform bootstrap script |
| `ADAPTER-CONTRACTS-RUNBOOK.md` | `products/vityo_app/lib/src/backend_toolchain/`, legacy integration façade, `docs/contracts/`, `docs/external/for-styio/`, `docs/external/for-pafio/` |
| `THEME-UX-RUNBOOK.md` | `products/vityo_app/lib/src/view_render/theme/`, `products/vityo_app/lib/src/view_render/platform/`, `products/vityo_app/lib/src/theme/`, `products/vityo_app/lib/src/platform/viewport_profile.dart`, shared prototype style files |
| `DOCS-DELIVERY-RUNBOOK.md` | `README.md`, `docs/`, docs scripts, hygiene/docs/delivery gate scripts |

Generated `docs/**/INDEX.md` files do not themselves require runbook updates.

## Stats Requirement

When any team runbook or `COORDINATION-RUNBOOK.md` changes, `docs/teams/DOC-STATS.md` must also be refreshed in the same delivery.

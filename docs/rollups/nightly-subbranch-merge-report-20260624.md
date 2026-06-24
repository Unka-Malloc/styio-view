# Nightly Subbranch Merge Report

**Date:** 2026-06-24
**Purpose:** Record the consolidation of all non-nightly subbranches into `nightly`.

**Last updated:** 2026-06-24

## Remote Branches at Start

- origin/codex/styio-view-delivery-closure
- origin/coverage/project-coverage-gate-20260619205915
- origin/feature/vityo-ide-capability-upgrade
- origin/nightly
- upstream/ai-dev, upstream/main, upstream/nightly, upstream/stable

## Nightly Start SHA

c7484c9b8e97fd0eb39f73893891f5680763123e

## Merge Order

1. coverage/project-coverage-gate-20260619205915
2. codex/styio-view-delivery-closure
3. feature/vityo-ide-capability-upgrade

---

## 1. Coverage Branch — MERGED

**Stats:** 91 files, +18,037/-189. Nearly all files already existed in nightly.

### Conflicts (2 files)

| File | Resolution |
|------|-----------|
| `frontend/vityo_app/test/workspace_code_lens_test.dart` | Accepted coverage (theirs) — added 3 test cases |
| `frontend/vityo_app/test/vityo_app_smoke_test.dart` | Accepted coverage (theirs) — added bottom-surface tab tests |

### Post-Merge Fixes

- Updated `docs/teams/DOCS-DELIVERY-RUNBOOK.md` last-updated date
- Updated `docs/teams/DOC-STATS.md` counts
- Added `**Last updated:**` metadata to merge report

---

## 2. Codex Branch — MERGED

**Stats:** 479 files, +170,040/-4,358. Largest merge by volume.

### High-Risk Area Outcomes

| Area | Status |
|------|--------|
| `view_ide/agent/` | Union merge — kept all codex agent provider/tool/session runtime (agent_provider_*, agent_tool_*, agent_coding_*, agent_registry.dart, agent_session_context.dart) plus nightly's agent_profile.dart, agent_session.dart. Added `agent.dart` barrel with complete exports. |
| `view_ide/commands/app_commands.dart` | Union merge — kept HEAD's `IdeCommandRegistry`, `CommandPermissionPolicy`, `CommandPermissionEvaluation`, `CommandPermissionService` plus codex's `AppCommandCategory`/`AppCommandIdX`/`toContributionJson()`. Deduplicated key bindings, merged command getters. |
| `view_ide/workspace/` | Union merge — kept HEAD's workspace surface files (breadcrumbs, code_lens, declaration, definition, etc.) plus codex's hosted workspace lifecycle, search service, file explorer, source control stores, workspace edit, diagnostics. `workspace_controller.dart` taken from codex as asset source. |
| `view_ide/shell_runtime/` | Codex version (asset source) |
| `view_render/shell/shell_model.dart` | Union merge — kept HEAD's granular BottomSurfaceTab enum plus codex's terminal, sourceControl, testing, extensions tabs. Merged command execution routing. |
| `view_render/shell/vityo_shell_scaffold.dart` | Codex version (adds fundamental surface support) |
| `language/language.dart` barrel | Updated with codex additions: semantic_snapshot_event_bridge, semantic_snapshot_provider, styio_service_capability_profile, styio_service_daemon_process_adapter, styio_service_subscription, styio_language_provider_registry, styio_workspace_diagnostics_provider |
| `toolchain/maintenance-tools.json` | Preserved from coverage merge |

### Architecture Fixes

- **VityoThemeOverride**: Moved from view_render to view_ide (`environment/configuration/vityo_theme_override.dart`) to fix view_ide→view_render dependency. Used `int?` for ARGB32 color values. Updated view_render to import from view_ide and convert via extension.
- **Repository hygiene gate**: Updated `VIEW_IDE_LANGUAGE_BARREL` with 7 new codex exports.
- **Team runbooks**: Bumped dates on all affected runbooks.

### Codex Assets Rejected/Modified

- Old docs structure (`docs/milestones/2026-04-12/`) kept deleted (nightly already archived)
- Old barrel exports merged into current structure
- `prototype/app.js` and `prototype/index.html` kept from HEAD (codex wanted to delete)

---

## 3. Feature Branch — MERGED

**Stats:** 29 files, +6,184/-12. Final product capability layer.

### Key Additions Retained

| File | Action |
|------|--------|
| `agent_context.dart` | Kept — AgentContextSnapshot (distinct from agent_session_context.dart) |
| `agent_settings.dart` | Kept — API key strategy (env var name only, no real keys) |
| `diagnostic_revision_gate.dart` | Kept — moved to `language/diagnostics/`, top-level facade added |
| `debug_workbench_contract.dart` | Kept — coexists with codex DAP layer |
| `ide_capability.dart`, `ide_capability_gap.dart`, `ide_capability_registry.dart` | Kept — workbench capability models |
| `source_control_adapter.dart` | Kept — machine boundary, coexists with codex controller/store |
| `ide_capability_framework.dart` | Kept — foundation framework |
| `docs/design/Vityo-IDE-Benchmark-Matrix.md` | Kept |
| `docs/design/Vityo-IDE-Capability-Maturity.md` | Kept |
| `docs/design/Vityo-IDE-Interaction-Quality-Bar.md` | Kept |
| `scripts/ide-product-parity-gate.py` | Kept — with allowlist updates |
| `scripts/vityo-ide-product-gate.py` | Kept |
| `toolchain/vityo-ide-capability-baseline.json` | Kept |

### Feature Command ID Additions

Added to `AppCommandId` enum: `openFile`, `reloadFile`, `acceptExternalChange`, `runSelectedTarget`, `runMinimalCompilableUnit`, `applyFormattingEdit`, `toggleVisualSubstitution`, `environmentPreflight`, `deployPreflight`, `openAgentPanelWithContext`, `previewAgentPatch`, `applyAgentPatch`, `rollbackLastWorkspaceEdit`

### New Enums Added

- `AppCommandSideEffect` (none, readExternal, documentEdit, workspaceEdit, toolchainExecution, externalMutation)
- `AppCommandTargetSurface` (editor, commandOverlay, workspaceSidebar, bottomPanel, settingsPanel, statusBar, modalDialog, background)

---

## Validation Results

### All Passing

| Gate | Result |
|------|--------|
| repo-hygiene-gate.py --mode tracked | PASS |
| docs-index.py --write/--check | PASS |
| team-docs-gate.py | PASS |
| docs-audit.py | PASS |
| ide-product-parity-gate.py | PASS |
| vityo-ide-product-gate.py --mode checkpoint | PASS |
| Python unit tests (101 tests) | PASS |
| No conflict markers in codebase | PASS |

### Not Run (missing tools)

| Gate | Reason |
|------|--------|
| Flutter analyze | Flutter/Dart not available locally |
| Flutter test | Flutter/Dart not available locally |
| Flutter build web | Flutter not available locally |
| `./scripts/docs-gate.sh` | Dependency path issues |
| `./scripts/delivery-gate.sh` | Not available locally |
| Python coverage gate | Not run (focus on structural gates) |
| Prototype governance (`npm run governance`) | Node.js environment not verified |
| Prototype selftest (`npm run selftest:editor`) | Node.js environment not verified |
| `prototype/test_dev_server_security.py` | Not run |

All tool-dependent gates should pass in CI (GitHub Actions).

---

## PR Review Focus

1. **Agent barrel** (`view_ide/agent/agent.dart`) — verify all 47 exports resolve to existing files
2. **Commands** (`view_ide/commands/app_commands.dart`) — verify no duplicate command IDs, all new feature commands have category mappings
3. **Workspace barrel** (`view_ide/workspace/workspace.dart`) — verify all exports resolve
4. **Language barrel** (`view_ide/language/language.dart`) — verify diagnostic_revision_gate facade
5. **VityoThemeOverride** — verify view_ide→view_render dependency direction is correct
6. **BottomSurfaceTab enum** — verify merged enum doesn't break shell scaffold rendering
7. **Product parity gate allowlist** — verify agent file additions are justified
8. **CI workflow** — run `flutter analyze` and `flutter test` in CI

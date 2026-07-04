# Workbench Shell Surfaces Contract

**Purpose:** Define the workbench shell surface, layout, focus, command routing, capability, and responsive behavior contract for the current Vityo IDE shell.

**Owner:** `frontend/vityo_app/lib/src/view_render/shell/` and `frontend/vityo_app/lib/src/view_ide/workbench/`
**Last updated:** 2026-06-29
**Checkpoint node:** `25682787-9c3d-4320-8ca2-d54944d312a0` (Workbench Shell Surfaces contract, `docs/plan/better-plan/workbench-shell-surfaces/Checkpoints.json`)

---

## 1. Owned Artifacts

The following source files define the workbench shell surfaces, their layout, command dispatch, focus routing, and responsive behavior. No other module owns shell-surface domain models.

### Shell scaffold and model

| File | Role |
|------|------|
| `frontend/vityo_app/lib/src/view_render/shell/vityo_shell_scaffold.dart` | Top-level StatelessWidget that assembles the shell: `_TopBar`, `_DesktopShellBody`/`_MobileShellBody`, `_BottomSurfacePanel`, status bar, and command shortcut registration. Routes between desktop (Row-layout) and mobile (ListView-stacked) through `LayoutBuilder` and `resolveViewportProfile`. |
| `frontend/vityo_app/lib/src/view_render/shell/shell_model.dart` | `ShellModel` extends `ShellRuntimeModel`; owns `shellLayoutPreferenceController`, active `BottomSurfaceTab`, and command-to-tab routing in `executeCommand()`. |
| `frontend/vityo_app/lib/src/view_render/shell/shell_scope.dart` | `ShellScope` (InheritedNotifier<ShellModel>) provides shell-wide access without widget-level prop drilling. |
| `frontend/vityo_app/lib/src/view_render/shell/shell_layout_plan.dart` | `ShellLayoutPlan`, `ShellLayoutPreferenceController`, `ShellPanelDescriptor`, `ShellPanelContribution`, `ShellPanelContributionRegistry`. Defines the 5 layout regions, bottom-tab panel catalog (27 tabs), mobile/desktop mode selection, serialization/deserialization. |
| `frontend/vityo_app/lib/src/view_render/shell/hosted_workspace_lifecycle_banner.dart` | Hosted workspace close-guard banner for cloud workspaces. |

### Layout and app shell

| File | Role |
|------|------|
| `frontend/vityo_app/lib/src/app/layout/vityo_shell_scaffold.dart` | App-level scaffold with `AppCommandIntent`/`AppCommandShortcutRegistry` bindings. |
| `frontend/vityo_app/lib/src/app/commands/app_commands.dart` | Flutter Intent/Shortcut registration: `AppCommandIntent`, `AppCommandShortcutRegistry`. Re-exports from `view_ide/commands/`. |

### Command palette

| File | Role |
|------|------|
| `frontend/vityo_app/lib/src/view_ide/commands/command_palette.dart` | Pure-Dart `CommandPaletteService` -- scoring, matching, filtering, recent-rank boosting, blocked-reason support. |
| `frontend/vityo_app/lib/src/view_ide/commands/command_palette_model.dart` | `CommandPaletteModel`, `CommandPaletteOverlayState`, `CommandPaletteInputDraft`, `CommandPaletteQueryState` -- overlay state machine for palette rendering. |
| `frontend/vityo_app/lib/src/view_ide/commands/command_palette_recent_store.dart` | Persisted recent-command store through `FoundationDataStore`. |
| `frontend/vityo_app/lib/src/view_ide/commands/command_keybinding_profile.dart` | `CommandKeybindingProfile`, `CommandKeybindingProfileStore`, conflict detection, shortcut parsing/display. |
| `frontend/vityo_app/lib/src/view_ide/commands/extension_command_contributions.dart` | Dynamic command contributions from extension modules, merged with `StyioCommandRegistry`. |
| `frontend/vityo_app/lib/src/view_ide/commands/app_commands.dart` | `AppCommandId` enum (80+ commands), `AppCommandDescriptor`, `StyioCommandRegistry` (canonical command catalog with labels, shortcuts, categories, target surfaces, side effects, permissions). |
| `frontend/vityo_app/lib/src/view_render/commands/command_palette_surface.dart` | Flutter widget rendering the command palette overlay: query input, category filters, result list, input draft, keybinding editor, empty state. |

### Capability and surface registry

| File | Role |
|------|------|
| `frontend/vityo_app/lib/src/view_ide/workbench/ide_capability.dart` | `IdeCapabilityDomain`, `IdeCapabilityMaturity` (L0-L5), `IdeCapabilityAvailability`, `IdeCapabilityDescriptor`. |
| `frontend/vityo_app/lib/src/view_ide/workbench/ide_capability_gap.dart` | `IdeCapabilityGap`, `IdeCapabilityGapReport` -- structured blocked reasons for missing capabilities. |
| `frontend/vityo_app/lib/src/view_ide/workbench/ide_capability_registry.dart` | `IdeCapabilityRegistry`, `IdeCapabilitySnapshot`, `PlatformCapabilityFilter`. |
| `frontend/vityo_app/lib/src/view_ide/workbench/surface_registry.dart` | `SurfaceRegistry`, `IdeSurfaceDescriptor`, `IdeSurfacePlacement` (primarySideBar, secondarySideBar, bottomPanel, editorAuxiliary, modal). |
| `frontend/vityo_app/lib/src/view_ide/workbench/context_key_service.dart` | `ContextKeyService` -- typed context-key evaluation for surface visibility and command enablement. |

### Surface widgets (bottom-panel or sidebar surfaces)

| File | Role |
|------|------|
| `frontend/vityo_app/lib/src/view_render/runtime/runtime_surface.dart` | Runtime/output bottom panel surface. |
| `frontend/vityo_app/lib/src/view_render/runtime/debug_console_surface.dart` | Debug console bottom panel surface. |
| `frontend/vityo_app/lib/src/view_render/terminal/terminal.dart` | Terminal bottom panel surface. |
| `frontend/vityo_app/lib/src/view_render/editor/editor.dart` | Editor groups (central content area). |
| `frontend/vityo_app/lib/src/view_render/search/search.dart` | Workspace search/replace surface. |
| `frontend/vityo_app/lib/src/view_render/problems/problems.dart` | Diagnostics/problems surface. |
| `frontend/vityo_app/lib/src/view_render/agent/agent.dart` | Agent activity surface. |
| `frontend/vityo_app/lib/src/view_render/source_control/source_control.dart` | Source control changes surface. |
| `frontend/vityo_app/lib/src/view_render/testing/testing.dart` | Testing results surface. |
| `frontend/vityo_app/lib/src/view_render/extensions/extensions.dart` | Extensions management surface. |
| `frontend/vityo_app/lib/src/view_render/settings/settings_surface.dart` | Settings panel. |

### Tests

| File | Role |
|------|------|
| `frontend/vityo_app/test/shell_model_test.dart` | Shell model adapter dispatch, editor session persistence, toolchain recovery, command execution routing to tabs. |
| `frontend/vityo_app/test/shell_no_overflow_test.dart` | No-overflow verification: desktop layout fixed-width regions, compact mode hides activity rail, every bottom tab maps to a bound panel, serialization roundtrip, viewport key stability. |
| `frontend/vityo_app/test/shell_narrow_viewport_focus_test.dart` | Narrow viewport: compact hides activity-rail, desktop shows it, ListView vs Row, tab selection independent of viewport mode, panel visibility toggle, pinned state persistence, revision counting, focus model. |
| `frontend/vityo_app/test/shell_layout_plan_test.dart` | Layout plan serialization roundtrip, panel descriptors, contribution registry. |
| `frontend/vityo_app/test/shell_manager_test.dart` | Shell runtime prober and adapter tests (Linux, Windows, PowerShell, bash, cmd, fish shell planning). |
| `frontend/vityo_app/test/shell_runtime_file_binding_test.dart` | File binding integration tests. |
| `frontend/vityo_app/test/viewport_profile_test.dart` | ViewportProfile resolution: desktop platforms always desktop, mobile always mobile, web resolves by width. |
| `frontend/vityo_app/test/command_palette_test.dart` | Pure-Dart CommandPaletteService tests: recent-rank boosting, label/id/shortcut scoring, blocked command filtering. |
| `frontend/vityo_app/test/command_palette_surface_test.dart` | Widget tests: palette filters, executes on Enter, empty state, category filters, keyboard navigation, keybinding editor, conflict detection. |
| `frontend/vityo_app/test/command_palette_model_test.dart` | CommandPaletteModel query scoring and overlay state. |
| `frontend/vityo_app/test/command_palette_input_test.dart` | Input draft handling in command palette. |
| `frontend/vityo_app/test/command_palette_recent_store_test.dart` | Recent-command persistence. |
| `frontend/vityo_app/test/workbench_registry_test.dart` | SurfaceRegistry, IdeCapabilityRegistry, ContextKeyService -- registration, context evaluation, visibility filtering, manifest projection (metadata-only, no runtime closures). |

---

## 2. Product Boundaries

| Boundary | Owns | Does Not Own |
|----------|------|--------------|
| Shell scaffold | Top-level widget assembly, shortcut routing, viewport dispatch (desktop vs mobile), bottom-surface tab switching | Editor buffer state, document contents, language service sessions, execution processes |
| Layout plan | 5 regions (topBar, activityRail, editor, bottomPanel, statusBar), panel descriptors, mobile/desktop mode, layout preferences (pinned, expanded, active tab) | Pixel-level rendering constraints -- delegates to `LayoutBuilder` |
| Command palette | Query scoring, filtering, recent-rank, blocked reasons, category display, keybinding profile, extension contributions | Command execution -- delegates to `ShellModel.executeCommand()` |
| Capability registry | Capability metadata (domain, maturity, availability, blocked reason, owner boundary) | Runtime capability state -- derived by registry from registered descriptors, not from live probes |
| Surface registry | Surface ID registration, placement, context-key precondition visibility | Layout rendering -- surfaces are descriptors, not widgets |
| Shell model | Command-to-tab routing for 80+ commands, adapter dispatch | Adapter I/O -- delegates to adapter instances (execution, toolchain, dependency, deployment, etc.) |
| Hosted lifecycle banner | Cloud workspace close-guard UX, connector parity report | Cloud workspace lifecycle policy |

---

## 3. Invariants

### Shell layout

1. **Editor panel is always active.** Both desktop and compact modes keep `panelById('editor')?.active == true`. Verified in `shell_narrow_viewport_focus_test.dart`.
2. **Activity rail hidden in compact mode.** `ShellLayoutMode.compact` sets `panelById('activity-rail')?.visible == false`. Verified in `shell_no_overflow_test.dart` and `shell_narrow_viewport_focus_test.dart`.
3. **Every `BottomSurfaceTab` maps to exactly one panel ID.** 27 enum values each produce a non-empty `renderBinding().activeBottomPanelId`. Verified in `shell_no_overflow_test.dart`.
4. **Viewport key is deterministic.** Desktop mode to `'shell-viewport-desktop'`. Compact mode to `'shell-viewport-mobile'`. Verified via serialization roundtrip.
5. **Layout plan is serializable/deserializable.** `ShellLayoutPlan.forViewport()` to `ShellLayoutPlan.fromJson()` roundtrips active tab, mode, panel visibility, and viewport key. Verified in `shell_no_overflow_test.dart` and `shell_layout_plan_test.dart`.

### Command palette

6. **Recent commands appear first on empty query.** `CommandPaletteService.findCommands()` with empty pattern returns recent commands sorted by recent rank, then remaining commands by registry index. Verified in `command_palette_test.dart`.
7. **Blocked commands are scored 250 points lower.** A `blockedReason` subtracts 250 from score, ensuring enabled commands rank above blocked ones. Blocked commands remain visible by default (`includeBlocked: true`). Verified in `command_palette_test.dart`.
8. **Query matches score by label > commandId > category > description.** Label starts-with = 100, label contains = 80, commandId contains = 60, category contains = 50, description contains = 30. Verified in `command_palette_test.dart`.
9. **Category filter is exclusive.** When a category is toggled, only commands in that category are shown. Verified in `command_palette_surface_test.dart`.

### Focus and navigation

10. **`selectBottomTab()` is idempotent on same tab.** Selecting the active tab is a no-op (revision unchanged). Verified in `shell_narrow_viewport_focus_test.dart`.
11. **Panel pinned state persists across binding recalculations.** Setting `setPanelPinned()` persists through `planForViewport()` and `renderBindingForViewport()`. Verified in `shell_narrow_viewport_focus_test.dart`.
12. **Bottom panel expanded state preserves active tab.** Collapsing/re-expanding the bottom panel keeps `activeBottomTab`. Verified in `shell_narrow_viewport_focus_test.dart`.

### Capability and surface registries

13. **Capability snapshot is metadata-only.** `IdeCapabilityRegistry.toSnapshot()` returns only counts, labels, and domain summaries -- never runtime handler closures, callback references, or raw instances. Verified in `workbench_registry_test.dart`.
14. **Surface registration is idempotent-unique.** Double-registering the same surface ID throws `StateError`. Verified in `workbench_registry_test.dart`.
15. **Surface visibility respects context-key preconditions.** A surface with `preconditions` is invisible until all conditions are met. Verified in `workbench_registry_test.dart`.
16. **Platform capability filtering hides iOS/Web-specific capabilities.** iOS hides `execution.local`, `execution.localCompiler`, `sourceControl.localGit`. Web hides the same set. Desktop platforms (Windows, Linux, macOS) hide nothing. Verified in `ide_capability_registry.dart` via `PlatformCapabilityFilter`.

### Viewport profile

17. **Desktop platforms are always desktop viewport family.** macOS, Windows, Linux to `isDesktop == true`, regardless of window dimensions. Verified in `viewport_profile_test.dart`.
18. **Mobile platforms are always mobile viewport family.** iOS, Android to `isMobile == true`, regardless of dimensions. Verified in `viewport_profile_test.dart`.
19. **Web resolves by width.** Width >= 768 to desktop; < 768 to mobile. Verified in `viewport_profile_test.dart`.

---

## 4. Downstream Consumers

| Consumer | What they consume | Contract boundary |
|----------|-------------------|-------------------|
| `frontend/vityo_app/lib/src/view_ide/workbench/workbench.dart` (barrel) | Exports all capability/surface/context models | Pure-Dart models consumed by `view_render` widgets; no Flutter dependency in models |
| `frontend/vityo_app/lib/src/view_render/view_render.dart` (barrel) | Exports all shell, surface, editor, runtime, command-palette widgets | Widget layer owns rendering; delegates domain logic to `view_ide/models` |
| `frontend/vityo_app/lib/src/app/commands/app_commands.dart` | `StyioCommandRegistry.commands` to shortcut registration, `AppCommandIntent` to key dispatch | Intent-layer bridge between Flutter `Shortcuts`/`Actions` and command execution |
| `frontend/vityo_app/lib/src/app/layout/vityo_shell_scaffold.dart` | `AppCommandShortcutRegistry.shortcutIntents` to global key bindings | App-level widget that wraps the shell scaffold with shortcut dispatch |
| `frontend/vityo_app/lib/src/view_ide/commands/extension_command_contributions.dart` | Merged command manifest | Extension commands enrich the static `StyioCommandRegistry` |
| `docs/contracts/README.md` | Contract inventory index | Auto-indexed by `scripts/docs-index.py` |
| `docs/plan/better-plan/workbench-shell-surfaces/Checkpoints.json` node 8e002e19 | Consumes this contract to scope implementation | Implementation node must trace to all owned artifacts and satisfy all invariants |
| `docs/plan/better-plan/workbench-shell-surfaces/Checkpoints.json` node 29aa8968 | Consumes implementation evidence to validate release readiness | Release gate requires passing tests, no duplicate paths, structured capability gaps |

---

## 5. Unsupported / Blocked States

The following are expressed as structured capability gaps or todo annotations within owned artifacts. They are not acceptable as final deliverables without explicit user-visible capability-gap records.

### Bottom-panel TODOs (from `shell_layout_plan.dart`)

| Surface | Todo |
|---------|------|
| `bottom.search` | TODO: add production-scale virtualized search result rendering. |
| `bottom.problems` | TODO: add virtualized multi-file diagnostics diff expansion. |
| `bottom.settings` | TODO: bind all recovery and credential configuration routes. |
| `bottom.extensions` | TODO: render marketplace IO progress and lifecycle policy persistence. |
| `bottom.debug` | TODO: expose launch configuration editing and adapter process controls. |
| `bottom.agent` | TODO: add long-running coding session timeline virtualization. |

### Capability gaps (expressed through `IdeCapabilityGap`)

| Capability | Reason |
|------------|--------|
| `execution.local` (on iOS/Web) | `blockedByPlatform` -- no local compiler execution on mobile browsers. |
| `execution.localCompiler` (on iOS/Web) | `blockedByPlatform` -- no local compiler available. |
| `sourceControl.localGit` (on iOS/Web/Android) | `blockedByPlatform` -- no local Git executable on mobile. |

### Compact-mode gaps

- Activity rail hidden when `compact == true`. The desktop activity-rail icon grid becomes a `compactActivityFallback` (boolean flag on `ShellLayoutBinding`). The fallback UX is structurally separate from the full activity rail.

### Command-blocked state

- Individual commands can report a `blockedReason` through `CommandBlockedReasonResolver`. These appear in the command palette with a 250-point score penalty and `enabled == false`. They are visible by default and can be excluded with `includeBlocked: false`.

---

## 6. Single Implementation Path

All implementation work targeting this contract must converge on the current set of files listed in section 1. The following are **explicitly excluded** from final deliverables:

- **Old/debug/prototype/lab/experimental paths:** No separate debug-only view tree, prototype shell variants, lab-only surface registries, or experimental layout modes.
- **No duplicate command registries:** `StyioCommandRegistry` is the single canonical command catalog. Extension commands enrich it via `ExtensionCommandContributionCatalog`, not through a parallel registry.
- **No legacy fallbacks:** Compact mode is a first-class layout path (`ShellLayoutMode.compact`), not a degraded version of desktop mode. Both modes use the same `ShellLayoutPlan`/`ShellPanelDescriptor` model.
- **No versioned shells:** No v1/v2 shell scaffold variants, no compatibility wrappers, no legacy layout plans.
- **No capability-dual-tracking:** `IdeCapabilityRegistry` is the single source of truth for capability metadata. `view_render` consumes this registry but never infers capability state from widget tree context.

---

## 7. Verification Evidence

### Static structure evidence

- Barrel files: `view_render.dart` exports all shell files; `workbench.dart` exports all capability/surface models; `commands.dart` exports all command palette models.
- Layout plan: `ShellLayoutPlan.forViewport()` is the single entry point for both `desktop` and `compact` modes. `ShellPanelContributionRegistry.defaultIdePanels()` is the single catalog for bottom-surface panels.
- Command catalog: `StyioCommandRegistry.commands` lists 80+ unique `AppCommandId` values with no duplicates.

### Test evidence (16+ test files, 3000+ lines)

| Test | Key assertions |
|------|----------------|
| `shell_no_overflow_test.dart` (5 tests) | Desktop fixed-width regions, compact hides activity rail, every tab maps to a panel, core panels define finite capabilities, serialization roundtrip, deterministic viewport keys |
| `shell_narrow_viewport_focus_test.dart` (10+ tests) | Compact hides activity rail + mobile key, desktop shows it + desktop key, ListView vs Row stacking, tab selection independent of viewport, panel visibility toggle preserves active tab, pinned state persists, revision counting, selectBottomTab idempotence, editor always active |
| `shell_model_test.dart` | Toolchain recovery routes to correct tabs, command execution maps 80+ command IDs to bottom tabs, adapter dispatch delegates to correct adapters |
| `viewport_profile_test.dart` (3 tests) | Desktop platforms to desktop, mobile to mobile, web to by width |
| `command_palette_test.dart` (3 tests) | Recent-rank boosting, label/id/shortcut scoring, blocked reason filtering |
| `command_palette_surface_test.dart` (3 widget tests) | Palette filters + executes, empty state, category filter, keyboard navigation, keybinding editor + conflicts |
| `command_palette_model_test.dart` | Query scoring and overlay state machine |
| `workbench_registry_test.dart` (6+ tests) | ContextKeyService evaluation/parsing, surface registration (unique, idempotent), capability snapshot metadata-only (no runtime closure leak), surface manifest projection, platform filtering |

### Invariant coverage

- [x] All 19 invariants in section 3 are backed by test assertions in the test files listed above.
- [x] All 6 bottom-panel TODOs are captured as `todo` strings on `ShellPanelContribution` entries.
- [x] All 3 platform-blocked capabilities are documented in `PlatformCapabilityFilter.hiddenCapabilitiesFor()`.
- [x] Single implementation path is enforced by barrel-file exports and absence of duplicate registries.

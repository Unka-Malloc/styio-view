# Vityo IDE Benchmark Matrix

**Purpose:** Map VSCode, IntelliJ IDEA Community, Codex, and OpenCode capability families to Vityo product capabilities. Every row targets a Vityo product outcome, not a clone of another IDE.

**Last updated:** 2026-06-24

**Status:** Active product benchmark

## 1. How to Read This Matrix

Each row names a modern-IDE capability family, states what the four benchmarks deliver at production maturity, then maps that to a **Vityo product capability**. The matrix is a design tool, not a scorecard: "Gap" records where Vityo currently falls short of the target, and "Non-goals" rules out paths that would contradict Vityo's Styio-native identity.

| Column | Meaning |
|---|---|
| Capability Family | A named infrastructure-level ability expected of a modern IDE. |
| Benchmark Standard | What VSCode / IntelliJ IDEA Community / Codex / OpenCode deliver at production maturity. |
| Vityo Target | The Styio-native Vityo product capability. Not "be like X". |
| Current | What Vityo has today (code anchors, test anchors, design baseline). |
| Gap | Missing implementation, integration, upstream dependency, or validation. |
| Repo Anchors | Concrete file paths proving current state. |
| Validation | How we prove the gap is closed. |
| Non-goals | Paths explicitly excluded. |

---

## 2. Editor Core

| # | Capability Family | Benchmark Standard | Vityo Target | Current | Gap | Repo Anchors | Validation | Non-goals |
|---|---|---|---|---|---|---|---|---|
| E1 | Document Model | Undo/redo, selection, cursor, multi-cursor, line-based editing, zero-latency input | Styio Source Buffer with undo/redo, selection, cursor, keyboard input; visual substitution is display-only | Document state, selection state, undo/redo, keyboard editing, glyph substitution cursor mapping exist | Multi-cursor, large-file degradation policy, full IME composition | `view_ide/editor/document/`, `view_ide/editor/selection/`, `view_ide/editor/controller/` | Widget tests for undo/redo, selection; large-file (>10K lines) perf test | No silent Source Buffer mutation; no VS Code TextModel clone |
| E2 | Visual Substitution | N/A (Styio-unique) | Glyph substitution for `->`, `|>`, `{ }` block surfaces, semantic decorations; user-toggleable | Glyph substitution engine exists, user toggle wired | Full semantic block surface driven by language service | `view_ide/editor/render_plan/`, `prototype/editor-modules/glyph-presets.js` | Toggle test: substitution on/off preserves Source Buffer; copy/paste uses raw text | No substitution during save; no substitution-bypassing diagnostic positions |
| E3 | Viewport / Layout | Responsive editor layout, minimap, breadcrumbs, split editors | Desktop/mobile dual layout, narrow viewport adaptation, workspace breadcrumbs | Desktop/mobile layouts exist; workspace breadcrumbs exist | Split editor, minimap | `view_render/shell/`, `view_ide/workspace/workspace_breadcrumbs.dart` | Narrow-viewport widget test; breadcrumb navigation test | No hardcoded desktop layout on mobile |
| E4 | File Binding | File open/save/reload, conflict detection, external change handling, readonly state | Styio file binding with conflict detection, readonly, provider-unavailable states, structured error mapping | Open/save, conflict detection, deleted-file, readonly, provider-unavailable states exist | Provider reconnect UI | `view_ide/interaction/document_resource_binding.dart` | Conflict detection test; external-change reload test | No auto-save that bypasses user intent |

---

## 3. Language Intelligence

| # | Capability Family | Benchmark Standard | Vityo Target | Current | Gap | Repo Anchors | Validation | Non-goals |
|---|---|---|---|---|---|---|---|---|
| L1 | Syntax Highlighting | Token-based + semantic highlighting, LSP SemanticTokens | Token span + semantic span layered highlighting; StyioService-driven | Token spans, semantic spans, syntax highlighter exist | Stable upstream semantic token classification | `view_ide/language/styio_syntax_highlighter.dart`, `view_ide/language/styio_language_service.dart` | Highlighting correctness against `.true.styio` fixtures | No regex-only highlighting as primary strategy |
| L2 | Diagnostics | Problems panel, inline diagnostics, severity filtering, source-range stable | Document-bound, revision-bound, source-range stable diagnostics; severity normalized; stale rejected | Workspace problems service, diagnostics model, quick-fix loop exist | Stale-revision rejection, capability-gap model for missing upstream | `view_ide/workspace/workspace_problems.dart`, `view_ide/language/language_contract.dart` | Stale revision test; capability gap test; multi-diagnostic sort stability test | No fake diagnostics when upstream is unavailable |
| L3 | Completion | Context-aware completion, snippet support, documentation resolve | CompletionItem with insertText, detail, kind; StyioService-driven | Completion items in language contract exist | Upstream completion provider | `view_ide/language/language_contract.dart` | Completion smoke test | No hardcoded completion database |
| L4 | Hover | Type info, documentation, signature on hover | HoverPayload with range and markdown | Hover type exists in language contract | Upstream hover provider | `view_ide/language/language_contract.dart` | Hover smoke test | No regex-based type inference |
| L5 | Go-to-Definition | Symbol resolution to declaration, peek definition | DefinitionTarget from reference resolution | Definition target type exists; workspace definition navigator exists | Upstream reference resolution | `view_ide/workspace/workspace_definition.dart` | Definition navigation test | No string-match fallback as primary |
| L6 | Find References | Project-wide reference search, declaration/usage classification | ReferenceSpan with declaration/usage marking; workspace reference search | Reference spans in language contract; workspace reference search exists | Upstream reference provider | `view_ide/workspace/workspace_reference_search.dart` | Reference search test | No grep-based fallback as primary |
| L7 | Rename | Safe rename with preview, workspace edit application | RenamePlan with TextEdit collection; rename preview and apply | Rename plan type exists; workspace rename dialog exists | Upstream rename safety analysis | `view_ide/workspace/workspace_rename.dart` | Rename preview test; rename apply via transaction test | No global string replace bypassing document model |
| L8 | Code Actions | Quick fixes, source actions, lightbulb, preview/apply | DiagnosticQuickFix with preview/apply through workspace edit; capability gap when upstream blocked | Workspace code actions model exists | Upstream code action provider; capability gap rendering | `view_ide/workspace/workspace_code_actions.dart` | Quick fix preview test; apply via transaction test; capability gap test | No inline Source Buffer mutation |
| L9 | Formatting | Format document/selection, TextEdit-style return | FormattingEdit with range+newText; preview/apply through workspace edit | Formatting edit type exists in language contract | Upstream formatting provider | `view_ide/language/language_contract.dart` | Formatting preview test; apply test | No silent formatting on save without user opt-in |

---

## 4. Project / Workspace Model

| # | Capability Family | Benchmark Standard | Vityo Target | Current | Gap | Repo Anchors | Validation | Non-goals |
|---|---|---|---|---|---|---|---|---|
| P1 | Project Graph | Project model, module graph, dependency tree, build targets | Styio project graph as first-class product model: workspace members, packages, dependencies, targets, toolchain, lock/vendor/build state | Project graph snapshot, canonical file inference, workspace members/packages/dependencies/targets display exist | Machine payload consumption (waiting on pafio); canonical vs hosted source marking | `view_ide/backend_toolchain/project_graph_contract.dart`, `view_ide/backend_toolchain/project_graph_adapter.dart` | Project graph summary serialization test; source marking test | No reading PAFIO_HOME private directories |
| P2 | Workspace Explorer | File tree, project view, dependency view, outline | File tree as one view; project graph as product model; workspace members, dependencies, targets, toolchain state visible | Workspace sidebar with project workflow, compiler handshake, required handoffs cards exist | Graph-first navigation (currently file-tree-first) | `view_ide/workspace/`, `view_render/shell/` | Explorer keyboard navigation test; graph summary test | No private directory structure inference |
| P3 | Dependency Management | Package manager integration, dependency tree, version resolution | fetch/vendor workflow lanes through DependencySourceAdapter | Dependency source adapter, fetch/vendor commands exist | Upstream pafio dependency resolution | `view_ide/backend_toolchain/dependency_source_adapter.dart` | Fetch/vendor lane state test | No Vityo-owned dependency resolver |
| P4 | Toolchain Management | Compiler/SDK version management, toolchain pinning | Managed Styio toolchain lifecycle: install, use, pin, clear, health check | Toolchain manager, catalog, install executor, health check exist | Real managed download endpoint; richer selector UX | `view_ide/toolchain/`, `view_ide/backend_toolchain/toolchain_management_adapter.dart` | Toolchain status surface test | No Vityo-owned compiler distribution |

---

## 5. Command System

| # | Capability Family | Benchmark Standard | Vityo Target | Current | Gap | Repo Anchors | Validation | Non-goals |
|---|---|---|---|---|---|---|---|---|
| C1 | Command Registry | Command palette, command IDs, keybindings, enablement, categories | IDE-grade command registry: stable IDs, categories, descriptions, enablement, capability requirements, side-effect levels, undoability, permission levels | IdeCommandRegistry with 37 commands, categories, permissions, shortcuts exists | Agent-visible command filtering; missing agent/toggle-substitution commands; capability-gap enablement | `view_ide/commands/app_commands.dart`, `view_ide/commands/command_palette.dart` | Registry registration/lookup/filtering test; enablement with blocked reason test; agent-filtered list test | No runtime-only objects in command manifest |
| C2 | Command Palette | Fuzzy search, recent commands, keyboard navigation | Command palette with fuzzy matching, recent ranking, blocked-reason display, keyboard navigation | CommandPaletteService with fuzzy scoring, recent ranking, blocked reasons exists | Keyboard navigation in palette UI | `view_ide/commands/command_palette.dart` | Palette match test; keyboard navigation test | No palette that bypasses permission checks |
| C3 | Keybindings | Configurable keybindings, chord support, platform-aware defaults | Keybinding model with platform-aware defaults, configurable overrides | AppCommandShortcutSpec with platform modifiers exists | Configurable keybinding store; chord support | `view_ide/commands/app_commands.dart` | Keybinding resolution test | No hardcoded OS-specific keymaps |

---

## 6. Run / Debug / Runtime Surface

| # | Capability Family | Benchmark Standard | Vityo Target | Current | Gap | Repo Anchors | Validation | Non-goals |
|---|---|---|---|---|---|---|---|---|
| R1 | Run Configuration | Run targets, launch profiles, environment variables | Minimal compilable unit run; target selector; workflow lane summary | Run command, execution adapter, workflow lane summaries exist | Structured blocked reasons for ambiguous/missing target | `view_ide/backend_toolchain/execution_adapter.dart`, `view_ide/shell_runtime/shell_runtime_model.dart` | Run command blocked-reason test; target selection test | No Vityo-owned build system |
| R2 | Runtime Events | Structured runtime events, ordered stream, event replay | RuntimeEventEnvelope with stable ordering; family-based lane summary; event replay | Runtime event adapter, replay summary, lane summaries, graph summaries exist | Richer execution-graph detail payload (upstream) | `view_ide/backend_toolchain/runtime_event_adapter.dart`, `view_ide/runtime/runtime_replay_summary.dart` | Event replay test; unknown family degradation test | No fake runtime events |
| R3 | Debug Console | stdout/stderr/diagnostic stream, log filtering | Unified event stream for stdout/stderr/diagnostics; debug console replay | Debug console with lane trace, filter tokens exists | Live streaming (currently compile-plan artifact replay) | `view_ide/runtime/`, `view_render/runtime/` | stdout/stderr/diagnostic event stream test | No separate debugger process model |
| R4 | Execution Workflow | Build, run, test, deploy as structured workflow lanes | Run, fetch, vendor, environment, deploy workflow lanes with structured status | Four workflow lanes exist with unified command flow, blocked detection, recent result summary | Deploy/environment preflight lane detail | `view_ide/backend_toolchain/project_workflow_selection.dart`, `view_ide/shell_runtime/` | Workflow lane state test; failed lane isolation test | No Vityo-owned deployment engine |

---

## 7. Settings / Profile / Theme

| # | Capability Family | Benchmark Standard | Vityo Target | Current | Gap | Repo Anchors | Validation | Non-goals |
|---|---|---|---|---|---|---|---|---|
| S1 | Settings Schema | JSON-schema settings, searchable, import/export | VityoSettingsSchema: schema-owned, migratable, serializable, import/export, safe for Agent context | Settings surface test exists; configuration store exists | Full settings schema with migration; profile projection | `view_ide/environment/`, `view_render/theme/` | Settings roundtrip test; schema migration test; missing-setting fallback test | No raw secrets in settings files |
| S2 | Profile | User profile, local-first, optional sync | VityoProfileSnapshot: local-first, sync-optional, provider-missing-safe | Agent prompt profile exists | Profile snapshot model; profile sync absent is non-blocking | `view_ide/agent/agent_profile.dart` | Profile local-first test; missing-sync test | No login-required profile |
| S3 | Theme | Theme presets, token-level customization, semantic color mapping | Theme covering IDE shell, editor, semantic blocks, glyph, diagnostics, runtime, agent, focus/selection | Theme tokens, presets, glyph presets exist | Theme editor UI; agent panel theme; runtime surface theme | `view_render/theme/`, `prototype/editor-modules/theme-presets.js` | Theme preset roundtrip test; visual substitution toggle test | No commercial-brand default theme names |

---

## 8. Agentic IDE

| # | Capability Family | Benchmark Standard | Vityo Target | Current | Gap | Repo Anchors | Validation | Non-goals |
|---|---|---|---|---|---|---|---|---|
| A1 | Agent Context | Workspace-scoped context: active document, selection, diagnostics, project graph, runtime events | AgentContextSnapshot with scope, redaction; workspace/document/selection/diagnostics/project/runtime/commands/capability-gap context channels | Agent session, prompt profile, context channels exist | Context snapshot model; redaction policy; scope model; serialized context for provider | `view_ide/agent/agent_session.dart`, `view_ide/agent/agent_profile.dart` | Context snapshot serialization test; redaction test; scope exclusion test | No raw secrets/tokens in context |
| A2 | Agent Permissions | Permission model: read-only, workspace-write, toolchain, network; user approval flow | AgentPermissionLevel with layered approval; dangerous actions require higher permission | PermissionRequestScope, PermissionDecision exist | Permission policy per action category; permission audit trail | `view_ide/agent/agent_session.dart` | Permission level test; dangerous action denied test | No silent permission bypass |
| A3 | Patch Workflow | Preview diff, apply, rollback; structured edits | AgentPatchPreview → preview without mutation; AgentWorkspaceEditApplication via transaction with undo | FileChangePreview, PatchApplyPlan exist | Workspace edit application model; rollback of last agent edit | `view_ide/agent/agent_session.dart` | Patch preview no-mutation test; apply via transaction test; rollback test | No direct file write bypassing document model |
| A4 | Agent Provider | Multiple provider support; local-only mode; OpenAI-compatible endpoint | AgentProviderAdapter with local-only, provider-missing, OpenAI-compatible endpoint; no hardcoded provider | AgentProviderEndpoint, AgentProviderRoute exist; OpenAI-compatible protocol defined | Provider HTTP call; provider-missing UI state; local-only context display | `view_ide/agent/agent_profile.dart` | Provider-missing UI test; local-only mode test | No hardcoded single provider; no API keys in config files |
| A5 | Agent Commands | Agent-visible command catalog; agent triggers actions through command registry | Agent consumes command catalog; actions go through command registry, workspace edit, or execution adapter | Command registry exists | Agent-visible command filtering; agent command execution path | `view_ide/commands/` | Agent command list test; agent cannot bypass document model test | No agent direct file system access |

---

## 9. Module / Extension Runtime

| # | Capability Family | Benchmark Standard | Vityo Target | Current | Gap | Repo Anchors | Validation | Non-goals |
|---|---|---|---|---|---|---|---|---|
| M1 | Module Lifecycle | Extension install/uninstall/enable/disable; staged update | Core/optional module lifecycle; staged update; platform capability matrix; install/uninstall/disable | Module lifecycle, manifest, registry, capability matrix exist | Real package download/staging/activation | `view_ide/module_host/` | Module lifecycle test; capability matrix test | No auto-loading untrusted modules |
| M2 | Contribution Points | Extension contributes commands, views, language features, themes | Module contribution points through registry: commands, renderers, language providers, capabilities | Foundation registry with kind/owner/state filtering exists | Concrete module contribution adoption | `view_ide/module_host/module_registry.dart` | Registry manifest test; contribution filtering test | No runtime-only objects in registry manifest |

---

## 10. Hosted / Remote Workspace

| # | Capability Family | Benchmark Standard | Vityo Target | Current | Gap | Repo Anchors | Validation | Non-goals |
|---|---|---|---|---|---|---|---|---|
| H1 | Hosted Workspace | Remote/cloud workspace, retention, export | Hosted workspace lifecycle: create, use, close, export, retention window, deletion | Hosted workspace record snapshot, hosted control plane client exist | Retention/export UX validation | `view_ide/backend_toolchain/hosted_control_plane.dart`, `view_ide/workspace/hosted_workspace_document_store.dart` | Hosted workspace lifecycle test | No local-only assumption for Web |
| H2 | Cloud Execution | Remote build/run, cloud-only platforms | Cloud execution route for iOS/Web; hosted execution envelope | Cloud adapter route exists; hosted execution codec exists | Platform-matrix validation | `view_ide/backend_toolchain/hosted_execution_codec.dart` | Cloud execution envelope test | No cloud-only assumption for Desktop |

---

## 11. Performance / Interaction Quality

| # | Capability Family | Benchmark Standard | Vityo Target | Current | Gap | Repo Anchors | Validation | Non-goals |
|---|---|---|---|---|---|---|---|---|
| Q1 | Input Latency | <16ms editor input latency, no perceptible typing lag | Editor input latency target defined; render slice/repaint scope bounded | Editor surface exists | Latency measurement baseline; large-file degradation policy | `view_ide/editor/`, `view_render/editor/` | Input latency widget test | No telemetry-based measurement |
| Q2 | Keyboard Navigation | Full keyboard access to all IDE features | Keyboard navigation baseline: command palette, diagnostics, explorer, runtime lanes, agent panel, settings | Keyboard shortcuts exist for commands | Keyboard navigation in palette/diagnostics/explorer/agent UI | `view_ide/commands/` | Keyboard-only navigation test for core actions | No mouse-only interaction paths |
| Q3 | Accessibility | Screen-reader support, contrast compliance, focus management | Semantics baseline, contrast requirements, focus model, screen-reader labels | Not explicitly tested | Semantics tree; contrast validation; focus trap in panels | `view_render/` | Contrast test; semantics test | No ARIA-only approach (Flutter semantics tree instead) |
| Q4 | Container Integrity | No overflow, responsive layout, internal scrolling | No-overflow layout rule; narrow viewport behavior; internal scrolling/折叠 | Product spec mandates no overflow | Automated overflow detection | `view_render/shell/`, `view_render/platform/` | Container overflow widget test | No horizontal scroll on narrow viewports for primary content |

---

## 12. Testability / Release Gates

| # | Capability Family | Benchmark Standard | Vityo Target | Current | Gap | Repo Anchors | Validation | Non-goals |
|---|---|---|---|---|---|---|---|---|
| T1 | Product Gates | CI/CD quality gates: lint, test, build, coverage, hygiene | Product gate suite: repo hygiene, docs gate, Flutter analyze/test, coverage, release readiness | Multiple gates exist: hygiene, docs, coverage, release readiness, ecosystem | Unified product gate for IDE capability checks | `scripts/repo-hygiene-gate.py`, `scripts/release-readiness-gate.py` | All gates pass | No gate that depends on external services |
| T2 | Test Coverage | >80% coverage on core IDE logic | Test coverage targets for editor, language, workspace, runtime, agent | Coverage gate at 95% for Python; Flutter tests exist | IDE-specific capability coverage measurement | `scripts/project-coverage-gate.py` | Coverage report | No coverage as sole quality metric |
| T3 | Documentation Gates | Docs index, lifecycle, audit, cross-reference integrity | Docs index auto-generation, lifecycle validation, audit, cross-reference integrity | Docs index, lifecycle, audit scripts exist | IDE benchmark/maturity docs not yet in index | `scripts/docs-index.py`, `scripts/docs-audit.py` | Docs index includes new documents | No stale docs in index |

---

## 13. Capability Gap Model

Every row in this matrix where Current < Target must express the gap through Vityo's structured capability gap model:

| Gap Kind | Meaning | UI Behavior |
|---|---|---|
| `upstream-blocked` | Styio or Pafio must provide a machine contract first | Show blocked reason in relevant panel; do not guess |
| `implementation-needed` | Design exists, repo-local code missing | Show as "coming soon" or hidden behind feature flag |
| `partially-implemented` | Code exists but product path incomplete | Show available features; mark missing sub-features |
| `validation-needed` | Code exists but product gate not proven | Feature available; gate pending |
| `decision-needed` | Design boundary not settled | Feature hidden until decision recorded in ADR |

Capability gaps must never cause UI crashes, fake results, or silent degradation to lower-quality fallback without marking confidence/source.

---

## 14. References

- [Vityo-Product-Spec.md](./Vityo-Product-Spec.md) — Product SSOT
- [Vityo-System-Architecture.md](./Vityo-System-Architecture.md) — System architecture
- [Vityo-Implementation-Gaps.md](./Vityo-Implementation-Gaps.md) — Active gap register
- [Vityo-IDE-Capability-Maturity.md](./Vityo-IDE-Capability-Maturity.md) — Capability maturity model
- [Vityo-IDE-Interaction-Quality-Bar.md](./Vityo-IDE-Interaction-Quality-Bar.md) — Interaction quality baseline
- [../contracts/INDEX.md](../contracts/INDEX.md) — Adapter contracts

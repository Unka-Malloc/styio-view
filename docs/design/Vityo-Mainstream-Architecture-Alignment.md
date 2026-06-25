# Vityo Mainstream Architecture Alignment

**Purpose:** Map Vityo's architecture to mainstream IDE/agentic-IDE patterns without cloning any competitor. This document defines where Vityo aligns, where it intentionally diverges, and what governance rules maintain the alignment.

**Owner:** Architecture owner (`CODEOWNERS` → architecture domain)
**Last updated:** 2026-06-25

---

## 1. Architecture Reference Model

Vityo's architecture is organized into seven horizontal layers with strict import-direction rules:

```
┌──────────────────────────────────────────────┐
│  view_render/   Flutter presentation surface │  ← Flutter Material/Widgets allowed
├──────────────────────────────────────────────┤
│  view_ide/      Domain / application /       │  ← NO Flutter presentation imports
│                 adapter contract / state      │
├──────────────┬───────────────────────────────┤
│  agent/      │  module_host/                 │  ← Agent core + extension host
│              │  contribution / activation     │
├──────────────┴───────────────────────────────┤
│  legacy roots        Compatibility facades    │  ← One-line export only, no new logic
├──────────────────────────────────────────────┤
│  app/        Composition root                │  ← Bootstrap, DI, feature flags
├──────────────────────────────────────────────┤
│  prototype/  Web Editor (manual maintenance)  │  ← Not a Flutter build output
└──────────────────────────────────────────────┘
```

### 1.1 Boundary Rules

| Layer | May Import | Must NOT Import |
|-------|-----------|-----------------|
| `view_render/` | `view_ide/`, Flutter Material/Widgets/Cupertino | `agent/` provider core, `module_host/` activation |
| `view_ide/` | Standard Dart, `backend_toolchain/` (shim only) | Flutter Material, Widgets, Cupertino, `dart:ui` |
| `view_ide/agent/` | `view_ide/` models, adapter contracts | `view_render/`, Flutter |
| `view_ide/module_host/` | `view_ide/` contracts | `view_render/`, Flutter |
| `app/` | All layers | Nothing restricted (composition root) |
| `prototype/` | Self-contained | `frontend/vityo_app/` (build artifact boundary) |

## 2. Industry Alignment Map

### 2.1 VS Code → Vityo Mapping

| VS Code Concept | Vityo Equivalent | Intentional Divergence |
|----------------|-----------------|----------------------|
| Extension manifest (`package.json`) | `module_manifest.dart` / `extension_manifest_contract.dart` | Styio-native schema; no VS Code API compat |
| Contribution points | `extension_contribution_router.dart` → domain-specific contribution models | Typed contributions per domain, not string-based |
| Activation events | `extension_lifecycle.dart` → `activationEvents` in manifest | Capability-matrix gated, not file-pattern gated |
| Command palette | `commands/` → `app_commands.dart` + `command_palette_model.dart` | Styio command model, not VS Code keybindings |
| Status bar / panels | `view_render/` surfaces | Flutter-native, not webview CSS |
| Language features | `language/` adapter contracts | Capability-negotiated, not `onLanguage:xyz` |

### 2.2 Theia → Vityo Mapping

| Theia Concept | Vityo Equivalent | Intentional Divergence |
|--------------|-----------------|----------------------|
| Platform + product shell | `app/` (composition root) + `view_render/shell/` | No browser DOM; Flutter rendering |
| Extension mechanism | `module_host/` + `extension_*` | Not VS Code extension protocol; Styio-first |
| Vendor-neutral governance | `docs/governance/` + `CODEOWNERS` | Own governance, not Eclipse Foundation |
| Release SBOM | `scripts/release-readiness-gate.py` → SBOM check | Proprietary toolchain discovery |

### 2.3 IntelliJ Community → Vityo Mapping

| IntelliJ Concept | Vityo Equivalent | Intentional Divergence |
|-----------------|-----------------|----------------------|
| Build entry points | `scripts/bootstrap-*.sh` + CI workflows | No Gradle; Flutter + Python toolchain |
| Test entry points | `flutter test` + `tests/` Python suite | Modular per-package tests |
| Component ownership | `CODEOWNERS` + `docs/teams/*-RUNBOOK.md` | Team runbooks with owned paths |
| Long-term migration | ADR system (`docs/adr/`) | No compatibility with IntelliJ APIs |

### 2.4 LSP 3.17 → Vityo Mapping

| LSP Concept | Vityo Equivalent | Intentional Divergence |
|------------|-----------------|----------------------|
| JSON-RPC header/content | `styio_service_connector.dart` | Styio binary protocol over stdio/socket |
| Capability flags | `styio_service_capability_detector.dart` + `capability_profile` | Versioned negotiation, unknown-field tolerance |
| Server lifecycle | `styio_service_runtime.dart` + `styio_service_daemon_process_adapter.dart` | Daemon management, not just start/stop |
| Text document sync | `hosted_workspace_document_store.dart` | Versioned snapshots, not incremental text |

### 2.5 DAP → Vityo Mapping

| DAP Concept | Vityo Equivalent | Intentional Divergence |
|------------|-----------------|----------------------|
| Debug adapter protocol | `debug_workbench_contract.dart` + `debug_adapter_protocol.dart` | Styio adapter model, not DAP wire format |
| Launch/attach | `debug_launch_contract.dart` + `debug_launch_readiness_io.dart` | Readiness gates, not just configuration |
| Breakpoints | `debug_breakpoint_store.dart` | Workspace-snapshot-bound breakpoints |
| Output events | `runtime_output_channels.dart` + `runtime_output_channel_history_store.dart` | Typed output channels, not stdout/stderr only |
| Capability exchange | Capability negotiation in `debug_workbench_contract.dart` | Schema-versioned, with blocked reasons |

### 2.6 Codex CLI → Vityo Mapping

| Codex Concept | Vityo Equivalent | Intentional Divergence |
|--------------|-----------------|----------------------|
| CLI agent | `agent/` package (not CLI; embedded) | IDE-integrated, no standalone CLI agent |
| Tool approval | `agent_tool_permission.dart` + `agent_tool_permission_policy_store.dart` | Configurable, auditable, testable |
| Destructive/open-world | Permission levels: `destructive`, `open-world`, `full-access` | Redaction + journal for all tool calls |
| Provider routing | `agent_provider_registry.dart` + `agent_provider_route_executor.dart` | Multi-provider with health history |
| Agent context | `agent_context.dart` + `agent_workspace_snapshot.dart` | Workspace snapshot, diagnostic snapshot, runtime snapshot |

## 3. Architecture Governance Rules

### 3.1 Import Rules

1. `view_ide/` files MUST NOT import from `package:flutter/material.dart`, `package:flutter/widgets.dart`, or `package:flutter/cupertino.dart`.
2. `view_render/` files MUST NOT import from `view_ide/agent/`, `view_ide/language/service/`, or `view_ide/module_host/`.
3. Legacy `backend_toolchain/`, `editor/`, and `language/` files MUST NOT add new business logic; only one-line compatibility exports are allowed.
4. `view_ide/agent/` files MUST NOT import from `view_render/`.

Enforcement:

```bash
python3 scripts/check_architecture_boundaries.py
python3 scripts/check_compat_facades.py
```

### 3.2 Model Rules

1. Every public model/contract must have a `schemaVersion` field.
2. Every adapter payload must support unknown field tolerance.
3. Every capability declaration must have `blocked` reason when not `implemented`.
4. Every agent tool must have a permission level, redaction test, and journal test.
5. Every sandbox, secret, log redaction, module manifest security, or agent permission change must pass `python3 scripts/check_security_baseline.py`.
6. Every performance-sensitive editor, language, workspace, runtime, AI context, watcher, or UI virtualization change must keep `python3 scripts/check_performance_budgets.py` passing.

### 3.3 Naming Rules

1. No competitor names (VSCode, JetBrains, IntelliJ, Eclipse, Theia, Codex) in UI-visible strings.
2. Architecture docs may reference competitors for alignment context only.
3. File paths use `styio_` prefix for Styio-specific implementations, `vityo_` for Vityo-specific.

## 4. Cross-Reference

- [Vityo Product Spec](./Vityo-Product-Spec.md) — product invariants and boundaries
- [Vityo System Architecture](./Vityo-System-Architecture.md) — original system architecture document
- [Vityo Extension And Contribution Model](./Vityo-Extension-And-Contribution-Model.md) — extension architecture
- [Vityo Agent Runtime Architecture](./Vityo-Agent-Runtime-Architecture.md) — agent system design
- [Vityo Protocol And Capability Negotiation](./Vityo-Protocol-And-Capability-Negotiation.md) — protocol design
- [ADR-0010](../adr/ADR-0010-vityo-view-ide-view-render-boundary.md) — view_ide / view_render boundary decision
- [CODEOWNERS](../../CODEOWNERS) — architecture domain ownership

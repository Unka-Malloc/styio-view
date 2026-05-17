# Design Index

**Purpose:** Provide the inventory for `docs/design/`; product, system, delivered baseline, and gap-register boundaries live in [README.md](./README.md).

**Last updated:** 2026-05-17

## Directories

| Path | Entry | Summary |
|------|-------|---------|
| `architecture-views/` | [Architecture Views](./architecture-views/README.md) | Design-only review views such as vertical flow diagrams; not runtime implementation roots. |
| `appearance/` | [Appearance](./appearance/README.md) | App shell surfaces, rendering, theme mapping, editor renderer, diagnostics renderer, hover renderer, and completion renderer. |
| `interaction/` | [Interaction](./interaction/README.md) | Commands, editor controller, workspace edit application, focus, keybindings, and user/editor behavior. |
| `service/` | [Service Layer Design](./service/README.md) | Service roots that directly serve upper layers; internal connectors, adapters, caches, and fixture gates live under concrete service directories. |
| `foundation/` | [Foundation](./foundation/README.md) | Shared application mechanics: DataStore API, DataStore Owner contract, registry, workspace scope, resource coordination, and the Foundation development-unit boundary. |
| `environment/` | [Environment](./environment/README.md) | System compatibility, platform detector, platform context, platform managers, configuration, toolchain, extension, fallback, and execution environment capabilities. |

## Files

| Path | Entry | Summary |
|------|-------|---------|
| `Vityo-Product-Spec.md` | [Vityo Product Spec](./Vityo-Product-Spec.md) | Product-level SSOT for positioning, terms, invariants, feature domains, platform strategy, and acceptance boundaries. |
| `Vityo-System-Architecture.md` | [Vityo System Architecture](./Vityo-System-Architecture.md) | System hierarchy, adapter boundaries, platform execution backend, and mainline implementation strategy. |
| `Vityo-Delivered-Design-Baseline.md` | [Vityo Delivered Design Baseline](./Vityo-Delivered-Design-Baseline.md) | Completed implementation-plan outcomes consolidated into stable design documentation. |
| `Vityo-Implementation-Gaps.md` | [Vityo Implementation Gaps](./Vityo-Implementation-Gaps.md) | Active unfinished implementation, integration, validation, upstream-contract, and design-decision gaps. |
| `Vityo-Layer-Directory-Outline.md` | [Vityo Layer Directory Outline](./Vityo-Layer-Directory-Outline.md) | Directory outline by architecture layer, including design docs, current implementation anchors, and intended implementation homes. |

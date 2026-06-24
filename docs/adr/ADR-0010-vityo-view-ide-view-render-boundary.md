# ADR-0010: Vityo view_ide / view_render Boundary

**Purpose:** Establish a strict architectural boundary between the domain/application layer and the presentation surface.

**Last updated:** 2026-06-24

**Status:** Accepted
**Date:** 2026-06-24
**Deciders:** Architecture owner
**Replaces:** None (new ADR)

---

## Context

Vityo's Flutter codebase grew organically, resulting in unclear boundaries between domain logic and presentation. Files in `view_ide/` began importing Flutter Material and Widgets libraries, coupling domain models and adapter contracts to a specific presentation framework. This violates the product principle that Vityo's IDE domain model should be presentation-agnostic.

## Decision

We establish a strict boundary between `view_ide/` and `view_render/`:

1. **`view_ide/`** is the **domain/application layer**. It contains:
   - Domain models (editor state, workspace model, agent context)
   - Adapter contracts (language service, project graph, execution, debug)
   - State management (not tied to any UI framework)
   - Command definitions
   - Capability registries
   - Tool permission models

   **Import rule:** `view_ide/` MUST NOT import `package:flutter/material.dart`, `package:flutter/widgets.dart`, `package:flutter/cupertino.dart`, or `dart:ui`.

2. **`view_render/`** is the **presentation surface**. It contains:
   - Flutter widgets, screens, and surfaces
   - Theme and styling
   - Platform viewport profiles
   - UI-specific state bindings

   **Import rule:** `view_render/` consumes `view_ide/` models but MUST NOT import from `view_ide/agent/` provider core, `view_ide/language/service/`, or `view_ide/module_host/` activation logic.

3. **`app/`** is the **composition root**. It wires `view_ide` domain objects to `view_render` widgets through dependency injection and feature flags.

## Consequences

### Positive

- Domain models are testable without Flutter widget tests.
- Adapter contracts can be validated without a running Flutter environment.
- The agent system can be tested independently of any UI.
- Clear separation enables potential future non-Flutter presentation surfaces.
- Import rules are machine-enforceable via `architecture_boundary_gate_test.py`.

### Negative

- Some boilerplate in `app/` for wiring domain to presentation.
- Existing code that violates this boundary must be migrated.
- Developers must understand and respect the boundary.

### Neutral

- The boundary is enforced by `scripts/architecture_boundary_gate_test.py` which scans imports.
- Violations are caught in CI, not at runtime.

## Enforcement

### Automated Gate

`scripts/architecture_boundary_gate_test.py` scans all Dart files in `view_ide/` for forbidden Flutter imports. Violations cause CI failure.

### Code Review Checklist

Reviewers must verify:
1. New `view_ide/` files do not import Flutter presentation libraries.
2. New `view_render/` files do not import agent providers, language services, or module host activation logic.
3. New domain models in `view_ide/` do not reference Flutter types (e.g., `Color`, `Widget`, `BuildContext`).

### Migration Path

Existing violations will be addressed incrementally:
1. Phase 1: Stop adding new violations (enforced by gate).
2. Phase 2: Refactor existing violations file by file.
3. Phase 3: Remove grandfathered exceptions from gate.

## Validation

- `scripts/architecture_boundary_gate_test.py` — automated import scan
- `flutter analyze` — static analysis (indirect enforcement)
- Code review checklist in `docs/teams/ARCHITECTURE-RUNBOOK.md`

## Related

- [ADR-0009: Module Runtime and Staged Updates](./ADR-0009-module-runtime-and-staged-updates.md)
- [Vityo Mainstream Architecture Alignment](../design/Vityo-Mainstream-Architecture-Alignment.md)
- [Vityo System Architecture](../design/Vityo-System-Architecture.md)
- [Architecture Runbook](../teams/ARCHITECTURE-RUNBOOK.md)

# ADR-0010: Vityo view_ide / view_render Boundary

**Purpose:** Establish a strict architectural boundary between the domain/application layer and the presentation surface.

**Last updated:** 2026-07-31

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
   - Domain models (editor state, workspace model, revision-bound IDE facts)
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

   **Import rule:** `view_render/` consumes only registered `view_ide/` contract/model surfaces. Until a top-level `view_ide/contracts/` package exists, the canonical registration list is `VIEW_RENDER_ALLOWED_VIEW_IDE_IMPORTS` in `scripts/check_architecture_boundaries.py`. New `view_render -> view_ide` imports must be reviewed by adding a narrow registration entry instead of importing arbitrary implementation modules.

3. **`app/`** is the **composition root**. It wires `view_ide` domain objects to `view_render` widgets through dependency injection and feature flags.

4. **Legacy source roots are removed.** Old top-level `backend_toolchain/`, `editor/`, and
   `language/` import paths are not compatibility surfaces and must not be restored.

## Consequences

### Positive

- Domain models are testable without Flutter widget tests.
- Adapter contracts can be validated without a running Flutter environment.
- The agent system can be tested independently of any UI.
- Clear separation enables potential future non-Flutter presentation surfaces.
- Import rules are machine-enforceable via `scripts/check_architecture_boundaries.py` and
  `scripts/import-boundary-gate.py`.

### Negative

- Some boilerplate in `app/` for wiring domain to presentation.
- Existing code that violates this boundary must be migrated.
- Developers must understand and respect the boundary.

### Neutral

- The boundary is enforced by resolved import graph checks.
- Violations are caught in CI, not at runtime.

## Enforcement

### Automated Gate

`scripts/check_architecture_boundaries.py` scans Dart `import` and `export` directives, resolves relative and `package:vityo_app/...` URIs, and fails when:

1. `view_ide/` imports or exports `view_render/`.
2. `view_ide/` imports Flutter presentation APIs.
3. `view_render/` imports `view_ide/` targets that are not registered contract/model surfaces.
4. `view_render/` imports legacy compatibility roots such as `backend_toolchain/`, `editor/`, `language/`, or `integration/`.

### Code Review Checklist

Reviewers must verify:
1. New `view_ide/` files do not import Flutter presentation libraries.
2. New `view_render/` files use existing registered contract/model surfaces, or add a narrow `VIEW_RENDER_ALLOWED_VIEW_IDE_IMPORTS` entry with an architecture review.
3. New domain models in `view_ide/` do not reference Flutter types (e.g., `Color`, `Widget`, `BuildContext`).
4. Removed legacy import roots are not restored.

### Migration Path

The source-root migration is complete. New violations are rejected by the architecture and import
boundary gates; no compatibility phase remains.

## Validation

- `scripts/check_architecture_boundaries.py` — resolved import/export graph scan
- `scripts/import-boundary-gate.py` — product import-boundary scan
- `python3 -m unittest tests.test_architecture_boundaries` — gate unit tests
- `flutter analyze` — static analysis (indirect enforcement)
- Code review checklist in `docs/teams/ARCHITECTURE-RUNBOOK.md`

## Related

- [ADR-0009: Module Runtime and Staged Updates](./ADR-0009-module-runtime-and-staged-updates.md)
- [Vityo Mainstream Architecture Alignment](../design/Vityo-Mainstream-Architecture-Alignment.md)
- [Vityo System Architecture](../design/Vityo-System-Architecture.md)
- [Architecture Runbook](../teams/ARCHITECTURE-RUNBOOK.md)

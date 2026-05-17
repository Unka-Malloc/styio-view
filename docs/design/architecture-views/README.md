# Architecture Views

**Purpose:** Document the `docs/design/architecture-views/` collection scope, ownership, and maintenance rules.
**Last updated:** 2026-05-17

Architecture Views are design-only review documents. They may show vertical flows, dependency paths, and cross-layer movement, but they must not become runtime implementation roots.

Concrete implementation directories must stay under horizontal architecture directories such as `appearance/`, `interaction/`, `service/`, and `environment/`.

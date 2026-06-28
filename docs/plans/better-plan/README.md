# Better Plan Workspace

**Purpose:** Store the Better Plan workflow index for existing Vityo planning, milestone, gap, rollup, audit, and governance documents without replacing their owner files as the product source of truth.

**Last updated:** 2026-06-28

## Scope

This directory contains machine-readable Better Plan state:

1. `Manifest.json` indexes the functional plans derived from existing owner documents.
2. Each plan directory contains one `Checkpoints.json` execution graph.
3. Source facts remain in `docs/design/`, `docs/milestones/`, `docs/rollups/`, `docs/review/`, `docs/audit/`, and `docs/specs/`.

Do not add a new standalone local implementation plan here. Add or update the owning document first, then refresh this workspace from that source.

# ADR Docs

**Purpose:** Define the current-tree policy for `docs/adr/`: standalone ADRs hold architectural decisions that still need direct review, while implemented decisions that match current code are compressed into [IMPLEMENTED-DECISIONS.md](./IMPLEMENTED-DECISIONS.md) or the owning design/spec/runbook.

**Last updated:** 2026-06-28

## Scope

1. Use a standalone ADR for a significant architecture decision that still needs direct review, migration discussion, or a durable review record before it is absorbed by stable owner docs.
2. Once a decision is implemented and reflected in current code, gates, and SSOTs, compress the durable result into [IMPLEMENTED-DECISIONS.md](./IMPLEMENTED-DECISIONS.md) or the owning design/spec/runbook.
3. Do not keep one-file-per-decision history in the current tree just to preserve older wording. Git history remains the source for exact historical text.
4. ADRs are not milestone plans, task lists, rollups, or gap ledgers. Use `docs/design/`, `docs/rollups/`, `docs/plan/`, and `docs/review/` for those responsibilities.

## Freshness Rules

1. [IMPLEMENTED-DECISIONS.md](./IMPLEMENTED-DECISIONS.md) may only summarize decisions with current implementation anchors, verification anchors, or active owner docs.
2. If an implementation anchor changes or a decision becomes stale, update or remove the implemented-decision row in the same change.
3. Adjacent open gaps must stay explicit; do not present a partially implemented surface as fully closed.
4. New architecture boundaries must update the owning design doc first and add a standalone ADR only when direct review is still required.

## Naming Rules

1. Standalone ADR files use `ADR-XXXX-<slug>.md`.
2. ADR titles include the ADR number and short title.
3. New standalone ADRs include `Purpose`, `Last updated`, `Status`, and `Date`.
4. `IMPLEMENTED-DECISIONS.md` is intentionally not numbered; it is the compressed current-state index for implemented decisions.

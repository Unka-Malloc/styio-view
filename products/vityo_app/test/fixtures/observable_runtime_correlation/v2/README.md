# Observable runtime-events v2 consumer fixtures

Accepted Styio PLAN-006 `observable-runtime-correlation/v2` fixtures were
copied verbatim from `tests/fixtures/observable-runtime-correlation/v2/` in
the Styio sibling worktree. Vityo-owned negatives and scenarios live under
`vityo/` and cover every decoder subcode, correlation class, aggregation
equivalence, conservation, unmatched waits, and additive-canary case named
by the V3 contract. Bounded eviction is a generated stream in tests, not a
checked-in fixture.

Fold tests inject the fixture's declared `snapshot_id` and site ids as the
retained head. Controller tests substitute those ids with the topology
corpus head identity and node ids.

## Provenance

| Path | Provenance |
| --- | --- |
| `canonical.jsonl` | copied verbatim from styio `tests/fixtures/observable-runtime-correlation/v2/` |
| `additive-fields.jsonl` | copied verbatim from styio |
| `privacy-canaries.styio` | copied verbatim from styio |
| `vityo/*.jsonl` | vityo-authored negatives and scenarios |
| `vityo/additive-canaries.jsonl` | vityo-authored; marker strings `vityo-additive-canary-<n>` only inside unknown additive fields |
| `vityo/disabled-mode.jsonl` | vityo-authored; mirrors the producer's disabled-mode shape (`snapshot_id: null`, empty `active_capabilities`, controller-only records, `partial/disabled` summary) written on every non-observed compile-plan run |

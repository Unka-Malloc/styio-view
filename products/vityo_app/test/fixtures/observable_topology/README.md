# Observable topology consumer fixtures

Accepted Styio PLAN-005 `observable-topology` fixtures were copied verbatim
from `tests/fixtures/observable-topology/` in the Styio sibling worktree.
The `query/` family is excluded: bounded query intake is out of scope for
this Vityo stage.

Vityo-owned negatives live under `vityo/` and cover decoder and apply
rejection subcodes that the producer corpus does not name. Stale, duplicate,
and out-of-order deliveries are window scenarios built in tests from the
accepted corpus; they are not separate fixture files.

## Provenance

| Path | Provenance |
| --- | --- |
| `manifest.json` | copied verbatim from styio `tests/fixtures/observable-topology/` |
| `parent/` | copied verbatim from styio |
| `child/` | copied verbatim from styio |
| `delta/` | copied verbatim from styio |
| `lineage/` | copied verbatim from styio |
| `query/` | excluded; out of scope |
| `vityo/delta/*.json` | vityo-authored negatives |
| `vityo/child/*.json` | vityo-authored negatives |

Every copied parent and child fixture's declared producer identity equals
`s1_` plus the first 32 lowercase hex characters of SHA-256 over the exact
file bytes, including the trailing newline.

# Performance Baseline

**Purpose:** Record Vityo performance baselines for regression detection.

**Last updated:** 2026-08-18

## Rendered editor input (REQ-INPUT-004)

- **Protocol:** req-input-004-v1
- **Platform family:** desktop-macos
- **Status:** failed
- **Viewport:** 1200×800
- **JSON projection:** `docs/review/performance-baseline.json`
## Lane summary

| Fixture | Operation | Substitution | Evidence | Degradation | Median µs | P95 µs | Rendered lines | Status |
| --- | --- | --- | --- | --- | ---: | ---: | ---: | --- |
| 10000 | typing | off | renderedProfile | viewportBounded | 20216 | 30540 | 12 | medianOverBudget |
| 10000 | compositionUpdate | off | renderedProfile | viewportBounded | 3841 | 4722 | 12 | passed |
| 10000 | compositionCommit | off | renderedProfile | viewportBounded | 20375 | 33448 | 12 | medianOverBudget |
| 10000 | multiCursorMovement | off | renderedProfile | viewportBounded | 3304 | 4473 | 12 | passed |
| 10000 | rectangularProjection | off | renderedProfile | viewportBounded | 2835 | 3833 | 12 | passed |
| 10000 | viewportMovement | off | renderedProfile | viewportBounded | 5165 | 7267 | 13 | passed |
| 10000 | typing | on | renderedProfile | viewportBounded | 15726 | 25308 | 12 | medianOverBudget |
| 10000 | compositionUpdate | on | renderedProfile | viewportBounded | 3174 | 4732 | 12 | passed |
| 10000 | compositionCommit | on | renderedProfile | viewportBounded | 16729 | 22940 | 12 | medianOverBudget |
| 10000 | multiCursorMovement | on | renderedProfile | viewportBounded | 1849 | 2511 | 12 | passed |
| 10000 | rectangularProjection | on | renderedProfile | viewportBounded | 1615 | 2263 | 12 | passed |
| 10000 | viewportMovement | on | renderedProfile | viewportBounded | 4537 | 6180 | 13 | passed |
| 100000 | typing | off | renderedProfile | largeFileReducedDecorations | 20829 | 74851 | 12 | medianOverBudget |
| 100000 | compositionUpdate | off | renderedProfile | largeFileReducedDecorations | 4086 | 6544 | 12 | passed |
| 100000 | compositionCommit | off | renderedProfile | largeFileReducedDecorations | 15674 | 19167 | 12 | medianOverBudget |
| 100000 | multiCursorMovement | off | renderedProfile | largeFileReducedDecorations | 1360 | 2564 | 12 | passed |
| 100000 | rectangularProjection | off | renderedProfile | largeFileReducedDecorations | 1332 | 2158 | 12 | passed |
| 100000 | viewportMovement | off | renderedProfile | largeFileReducedDecorations | 3324 | 4156 | 13 | passed |
| 100000 | typing | on | renderedProfile | largeFileReducedDecorations | 13923 | 18692 | 12 | medianOverBudget |
| 100000 | compositionUpdate | on | renderedProfile | largeFileReducedDecorations | 1646 | 2093 | 12 | passed |
| 100000 | compositionCommit | on | renderedProfile | largeFileReducedDecorations | 13893 | 20482 | 12 | medianOverBudget |
| 100000 | multiCursorMovement | on | renderedProfile | largeFileReducedDecorations | 2104 | 3264 | 12 | passed |
| 100000 | rectangularProjection | on | renderedProfile | largeFileReducedDecorations | 1579 | 2342 | 12 | passed |
| 100000 | viewportMovement | on | renderedProfile | largeFileReducedDecorations | 3535 | 4853 | 13 | passed |

## Reproduce

```sh
cd products/vityo_app
flutter test --no-pub test/editor_rendered_input_profile_widget_test.dart
```

Rendered profile evidence requires a declared desktop host. The profile widget test measures real editor frames and writes sanitized baseline evidence.

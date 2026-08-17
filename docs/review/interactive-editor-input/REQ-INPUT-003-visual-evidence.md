# REQ-INPUT-003 Visual Evidence

**Purpose:** Record bounded rendered evidence for the interactive editor input acceptance workflow.

**Last updated:** 2026-08-03

Platform family: Flutter desktop widget harness (macOS host family)
Build mode: flutter test debug
Viewports: 1200×800 and 1600×1200
Tool: Flutter `RepaintBoundary.toImage` via `test/editor_input_visual_evidence_test.dart`

## Captured states

| State | 1200×800 | 1600×1200 |
|---|---|---|
| Multi-selection / reverse range over tab + emoji cluster | `multi-selection-1200x800.png` | `multi-selection-1600x1200.png` |
| Active CJK composition (provisional; revision unchanged) | `composition-active-1200x800.png` | `composition-active-1600x1200.png` |
| Composition committed (one revision) | `composition-committed-1200x800.png` | `composition-committed-1600x1200.png` |
| After undo | `after-undo-1200x800.png` | `after-undo-1600x1200.png` |
| Composition canceled + input status | `composition-canceled-1200x800.png` | `composition-canceled-1600x1200.png` |

## Visual Verifier repairs

- Surrogate-safe TextSpan splitting and painting sanitization in `editor_surface.dart`
- Tokenizer emits complete UTF-16 scalar pairs for non-BMP characters in `styio_syntax_highlighter.dart`
- Regression: `test/editor_emoji_selection_render_test.dart`

## Notes

- Evidence uses generated non-private fixture text only.
- No machine identity, absolute local paths, or source secrets are recorded here.
- Widget/integration channel coverage remains in the frozen focused regression command.

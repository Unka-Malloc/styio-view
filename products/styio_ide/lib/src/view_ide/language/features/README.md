# Language Features

This module contains independently testable IDE-facing language features that
use language facts but do not own Styio semantic truth.

Current feature modules:

| Module | Responsibility |
|---|---|
| `styio_completion_feature.dart` | Builds keyword, type, and resolved-symbol completion items from a `SemanticSnapshot`. |
| `styio_formatting_feature.dart` | Builds deterministic whitespace cleanup edits and formatting code actions for the local fallback service. |
| `styio_hover_feature.dart` | Builds hover payloads from resolved snapshot elements and syntax operator metadata. |
| `styio_inlay_hint_feature.dart` | Builds lightweight literal type hints from local snapshot facts. |
| `styio_navigation_feature.dart` | Builds definition, references, and rename plans from `ResolvedElement` / `ResolvedReference` facts. |
| `styio_parameter_info_feature.dart` | Builds local fallback parameter info from the existing symbol index until StyioService owns signature truth. |
| `styio_refactor_feature.dart` | Builds safe delete, inline variable, introduce variable, extract function, and change signature plans from snapshot facts and selected source ranges. |
| `styio_semantic_token_feature.dart` | Builds semantic token spans from resolved elements and references for local fallback highlighting. |
| `styio_syntax_diagnostic_feature.dart` | Builds local fallback delimiter diagnostics and delimiter quick fixes from token spans. This is responsive UI feedback, not compiler-owned Styio syntax truth. |

Remaining local fallback helpers such as quick fixes and intentions should move
here only when they have direct tests and a stable fact contract.

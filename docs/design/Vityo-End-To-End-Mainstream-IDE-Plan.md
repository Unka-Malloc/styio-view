# Vityo End-To-End Mainstream IDE Plan

**Purpose:** Preserve open-work signals cited by repository-delivery-convergence checkpoints at original line numbers; not a parallel product plan.

**Last updated:** 2026-07-11

**Status:** Restored citation anchor

**Authoritative successors:** Vityo-Mainstream-Architecture-Alignment.md, Vityo-IDE-Capability-Maturity.md, Vityo-Implementation-Gaps.md, docs/plan/vityo-product-delivery/

## Open-work signals (line-stable for checkpoint citations)





5. Three real desktop platform proofs: Linux, Windows, and macOS each build natively, run the same delivery health floor, and expose explicit unsupported/capability-gap states instead of hidden fallback behavior.

**Closure evidence (2026-07-11):** CI lanes `local-ci-gate` (ubuntu + macos jobs) and `windows-native` each run `scripts/delivery-gate.sh` and native desktop release builds. `frontend/vityo_app/test/desktop_platform_matrix_test.dart` proves Linux/Windows/macOS keep local execution/git visible while iOS/Web surface explicit capability gaps.


















































1. Registries must be disposable, scoped, testable, and ordered. VS Code command/contribution registries and OpenCode tool overlays both preserve late registration, removal, and previous registration reveal semantics.
2. Enablement must be expression-backed, not hand-coded per widget. VS Code context keys show that command, menu, quick access, debug, and terminal surfaces need a shared context expression model.
3. Text buffers must own EOL, BOM, Unicode, offset, range, snapshot, and delta semantics. Vityo's piece-tree buffer is the right direction, but final acceptance needs VS Code-level edge-case policy and large-file benchma
4. Language features must be provider-scored, revision-bound, cache-aware, and invalidated by model/workspace changes. A local heuristic symbol index is allowed only as a degraded fallback.
5. Workbench and module contributions must declare lifecycle phase, lazy activation rules, timing evidence, and disposal. Startup cost must be observable.


8. Process execution must expose stable process IDs, duplicate-ID rejection, stdout/stderr deltas, stdin, resize, terminate, output caps, sandbox/permission state, and blocked states.
9. Agent sessions must use typed submissions/events, trace IDs, durable turn/message/tool IDs, listener generation, cancellation, interrupt, rollback, and resume state.
10. Tool execution must validate input/output schemas, reject stale advertised calls, bound provider-facing output centrally, retain full output separately, and keep permission checks inside trusted tools.
11. File mutation must be conditional and locked by canonical target. Edits must fail stale writes instead of silently overwriting external or dirty document changes.
12. Patch application must parse to structured hunks, validate workspace containment and target permissions before reading or writing, report partial application precisely, and add rollback before claiming atomicity.

14. Indexing and semantic services need dumb/smart or ready/degraded modes. Feature callers must not pretend indexes are complete when a project is still indexing.

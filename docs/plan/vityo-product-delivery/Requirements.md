# Vityo Product Delivery — Requirements

**Purpose:** Product delivery contract for Vityo IDE with REQ-001..REQ-009, platform strategy, scope, and acceptance targets.

**Plan:** `vityo-product-delivery`
**Last updated:** 2026-07-11

## User Problem

Vityo is the dedicated IDE and runtime viewport for Styio, but its current build is honest scaffolding
around partial capabilities: navigation and rename run on token heuristics instead of compiler facts,
run/build can terminate in blocked capability states even with a working toolchain, project graphs are
inferred from files rather than package-manager payloads, theme/module/AI surfaces are incomplete, the
shell monolith and analyzer debt slow every change, and the gates that would prove the product loop are
opt-in and silently skippable. Users cannot yet trust the IDE's core promise: a truthful local
edit–compile–run loop with Styio-native runtime visibility.

## Target Users and Workflows

- **Styio developers on desktop (Linux/Windows/macOS)** — open a project, edit with accurate language
  intelligence, compile/run locally, read diagnostics and runtime events, debug via DAP.
- **Package-workflow users** — inspect dependency/toolchain/build state sourced from spio machine payloads.
- **Mobile/web users** — Android local-first when a CLI is present; iOS cloud-only; Web hosted-only
  (execution never pretends to be local where it is not).
- **AI-assisted users** — agent panel against any OpenAI-compatible endpoint.
- **Release operators** — installable desktop artifacts and CI evidence that the product matrix actually ran.

## Relationship to Existing Plans

`repository-delivery-convergence` is the meta-plan (planning-workspace consolidation; its Requirements.md
non-goals exclude product completion). This plan owns product completion. The upstream
`SymPolicy/Vityo` `vityo-product-delivery` draft (REQ-001..009, all 19 checkpoints pending) is the
taxonomy source; every target below is re-grounded in downstream evidence because downstream architecture
(`view_ide`/`view_render` split, hosted control-plane integration, security remediations) is ahead of it.

## Functional Requirements

- **REQ-001 — Desktop minimal IDE loop with real receipts.**
  Edit → save → compile → run over a sample project produces real diagnostics and structured execution
  receipts (exit status, phases, artifacts) through the sandboxed local CLI route
  (`view_ide` execution adapters); project graph and workflow lanes consume spio `project_graph v1` /
  `toolchain_state v1` machine payloads as authoritative source with file inference only as a labeled
  fallback. Without a toolchain, the same flows report structured capability gaps — never fake success.
  *Acceptance target:* integration test with a real `styio` binary covers the loop; payload
  source-confidence transitions are test-covered; unknown payload majors fail closed.

- **REQ-002 — Language intelligence truthfulness.**
  Navigation, rename, and formatting prefer compiler-emitted resolution facts (over the
  `styio-cli-jsonl-v1` stream, revision-bound); heuristic results (`StyioSymbolIndex`) are visibly labeled
  as heuristic; rename refuses unsafe cross-file application in heuristic mode; diagnostics remain
  revision-gated.
  *Acceptance target:* both routes test-covered over `.true.styio`/`.false.styio` fixtures; stale facts
  never apply to newer revisions; residual dependency on styio-side fact emission recorded explicitly.

- **REQ-003 — Runtime visualization from typed events.**
  Runtime surfaces subscribe to a typed, bounded execution event stream (phases, pulses, resource
  activity as payloads permit) defined Flutter-free in `view_ide`; raw console output remains available;
  unsupported event kinds surface as capability gaps.
  *Acceptance target:* widget tests cover event-to-visual mapping; buffers are bounded; performance
  budgets stay green.

- **REQ-004 — AI provider adapter.**
  An OpenAI-compatible provider adapter (configurable base URL/model) with streaming, cancellation,
  structured error taxonomy, and keys in platform secret storage (explicit non-persistent fallback).
  *Acceptance target:* fake-server streaming test; no plaintext keys in settings or logs; security
  baseline gate green.

- **REQ-005 — Theme/profile persistence.**
  Named theme/profile records persist via the DataStore seam, apply at bootstrap, and round-trip through
  validated JSON import/export; corrupted profiles fail soft to defaults with a notice.
  *Acceptance target:* persistence and import/export tests green.

- **REQ-006 — Module staged lifecycle.**
  Modules follow available → downloading → staged → active → retired with atomic activation
  (stage-then-swap), digest verification, rollback on failed activation, restart-surviving state, and
  storage reclaim that never touches the active version.
  *Acceptance target:* state-machine, persistence, and reclaim tests green.

- **REQ-007 — Platform execution matrix and packaging.**
  Desktop packaging definitions complete for Linux/Windows/macOS (installer definition, icons,
  desktop/update metadata; signing configured or recorded as an explicit gap) validated by
  `release-readiness-gate.py`; the platform matrix surface truthfully reports desktop local, Android
  local-when-CLI-present, iOS cloud-only, Web hosted-only; stale benchmark artifacts leave the app root.
  *Acceptance target:* gate green on all three desktop CI runners; platform-state tests green;
  hygiene gate green.

- **REQ-008 — Audit and code-health closure.**
  (a) Plan-source traceability: every convergence checkpoint citation resolves to an existing file;
  `README_zh.md` carries current Vityo naming. (b) Zero analyzer errors across `lib/` and `test/`
  (~69 pre-existing errors cleared). (c) Command dispatch is total — no `UnimplementedError` for any
  `AppCommandId`; unwired commands return structured capability-gap results. (d) `ShellRuntimeModel`
  (~8900 lines) decomposes into per-domain controllers per Architecture.md without behavior change.
  (e) Process lifecycles hardened: DAP shutdown grace with orphan verification, daemon restart races
  yield structured timeouts, terminal PTY implemented or declared a capability gap.
  *Acceptance target:* citation-resolution evidence; `flutter analyze` zero-error; enum-iteration
  dispatch test; line-count budgets met with suite green; lifecycle integration tests green.

- **REQ-009 — CI and product-gate truthfulness.**
  Product gates fail closed in CI (missing siblings/fixtures = failure; local skips print loud recorded
  reasons); a scheduled workflow provisions sibling checkouts, builds `styio`, runs the product matrix
  with `VITYO_PRODUCT_GATE=1`, and publishes per-REQ evidence with pinned sibling refs.
  *Acceptance target:* fail-closed exit-code test; scheduled lane run recorded with artifacts.

## Non-Functional Constraints

1. **Product invariants** (docs/design/Vityo-Product-Spec.md): Source Buffer authority over visual
   substitution; staged module updates; iOS cloud-only; Web hosted-only.
2. **Layer boundaries are gate-enforced:** `view_ide` stays Flutter-import-free
   (`scripts/check_architecture_boundaries.py`, `check_compat_facades.py`).
3. **Honest degradation:** every unavailable capability surfaces as an explicit blocked/capability-gap
   state; fake success anywhere is a defect.
4. **Coverage floors:** Python ≥95%, Flutter ≥85% (project-coverage-gate).
5. **Security baseline:** sandboxed process spawns, no secret leakage, `check_security_baseline.py` green.
6. **External dependencies stay explicit:** Styio resolution facts and execution contract
   (styio-nightly), spio machine payloads (pafio-nightly) are consumed contracts — requirements here
   deliver the consuming side plus honest labeling until upstream emits them.

## Scope

`vityo-nightly` repository: `frontend/vityo_app` (view_ide, view_render, app), `scripts/` gates,
`packaging/`, `.github/workflows/`, `docs/` (plan/design citations), `prototype/` untouched except where
gates reference it.

## Non-Goals

- Reimplementing the Styio compiler, LSP semantics, or spio resolution logic in the IDE.
- Mobile/web packaging beyond truthful capability states (desktop packaging only in REQ-007).
- Rewriting the custom editor engine or replacing the ChangeNotifier state idiom.
- Hosted workspace server-side work (client contracts only).
- Convergence-plan backlog execution (owned by `repository-delivery-convergence`).

## Final Acceptance Target

On one head commit: default delivery floor green (analyze zero-error, tests with coverage floors,
architecture/facade/security/performance gates, prototype selftest); product matrix green with sibling
checkouts and a real `styio` binary (workflow receipts, fixture-backed language gates, platform states);
REQ-001..REQ-009 each individually evidenced in the final-validation node; upstream-blocked residuals
validated on their honest blocked behavior and recorded.

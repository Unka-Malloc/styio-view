# Vityo Product Delivery — Validation Matrix

**Purpose:** Map every REQ-001..REQ-009 label to concrete repository checks before implementation.

**Plan:** `vityo-product-delivery`
**Last updated:** 2026-07-11

Two proof tiers. **Tier D (default):** runs on any checkout, no siblings needed. **Tier P (product):**
requires clean Styio and Pafio checkouts at the immutable commits in
`toolchain/product-matrix.json`, real binaries exported through `VITYO_PRODUCT_STYIO_BIN` and
`VITYO_PAFIO_BIN`, the Pafio repository path in `VITYO_PAFIO_ROOT`, an explicit
`VITYO_PRODUCT_PLATFORM`, and `VITYO_PRODUCT_GATE=1`.

## Standing gates (every implementation node, Tier D)

| Gate | Command |
|---|---|
| Delivery floor | `./scripts/delivery-gate.sh --mode checkpoint` |
| Analyzer zero-error | `cd frontend/vityo_app && flutter analyze` (lib/ **and** test/) |
| Tests + coverage | `cd frontend/vityo_app && flutter test --coverage` + `python3 scripts/project-coverage gate` (Flutter ≥85%, Python ≥95%) |
| Architecture boundaries | `python3 scripts/check_architecture_boundaries.py` + `python3 scripts/check_compat_facades.py` |
| Security baseline | `python3 scripts/check_security_baseline.py` |
| Performance budgets | `python3 scripts/check_performance_budgets.py` |
| Hygiene/docs | `python3 scripts/repo-hygiene-gate.py --mode tracked` + docs gates |
| Plan-state health | `python <better-plan>/scripts/manifest_tool.py validate docs/plan` |

## Per-requirement mapping

### REQ-001 — Desktop loop with real receipts (Tier P + D)
- **P:** sample-workflow gate with real binary: `VITYO_PRODUCT_GATE=1` product workflow tests +
  integration test asserting structured receipts (exit status, phases, artifacts) rendered in the
  runtime surface.
- **D:** toolchain-absent test asserting the structured capability gap (no fake success).
- **D:** project-graph tests asserting machine-payload authority, labeled file-inference fallback,
  source-confidence transitions both directions, and fail-closed unknown payload majors (fixtures from
  spio contract examples).

### REQ-002 — Language truthfulness (Tier P + D)
- **P:** language fixture gate (`language-fixture-gate.sh` with `STYIO`) over `.true.styio` /
  `.false.styio` fixtures; compiler-fact route assertions when facts are emitted.
- **D:** heuristic-route tests: visible heuristic labeling; rename refuses cross-file edits in heuristic
  mode; revision-gate test proving stale facts never apply to newer revisions.
- **D:** residual external dependency recorded in node evidence naming the exact consuming contract.

### REQ-003 — Runtime visualization (Tier D)
- Widget/golden tests for event-to-visual mapping; bounded-buffer test (drop-oldest with counters);
  unsupported-kind capability-gap test; `check_performance_budgets.py` green.

### REQ-004 — AI adapter (Tier D)
- Fake-server streaming test (tokens, cancellation, error taxonomy: auth/quota/network/contract).
- Secret-storage round-trip test (or recorded per-OS manual verification); grep gate: no plaintext keys
  in settings files or logs; `check_security_baseline.py` green.

### REQ-005 — Theme/profile persistence (Tier D)
- Restart-persistence test (store → bootstrap apply); JSON import/export round-trip with schema
  validation; corrupted-profile fail-soft test with visible notice.

### REQ-006 — Module lifecycle (Tier D)
- State-machine tests over available→downloading→staged→active→retired incl. rollback on failed
  activation; atomic-activation test (no partial overwrite observable); digest-verification negative
  test; restart-persistence test; reclaim test proving the active version is never removed.

### REQ-007 — Platform matrix + packaging (Tier D on 3 CI OSes)
- `python3 scripts/release-readiness-gate.py` green on Linux/Windows/macOS runners with complete
  packaging sets (signing configured or recorded explicit gap).
- `python3 scripts/run-native-pty-matrix.py --platform <platform> --output <receipt>` passes on the
  matching real host and records TTY identity, child-observed resize, forced close, environment
  propagation, native provider, fixed PTY dependency, and the Vityo commit.
- Platform-state tests: desktop local, Android local-when-CLI-present, iOS cloud-only, Web hosted-only.
- Hygiene gate green with benchmark artifacts out of the app root.

### REQ-008 — Audit closure (Tier D)
- Citation resolution: script or recorded grep proving every convergence checkpoint source citation
  resolves to an existing file; docs gates green after `README_zh.md` fix
  (`rg "styio_view|Styio View" README_zh.md` → 0).
- `flutter analyze` zero-error across lib/ and test/.
- Dispatch totality: `rg "UnimplementedError" frontend/vityo_app/lib/src/view_render/shell/` → 0 in
  dispatch paths + enum-iteration test asserting non-throwing structured results.
- Decomposition: recorded line counts vs Architecture.md budget; full suite green without test edits
  beyond imports.
- Lifecycle: DAP orphan-PID test; daemon kill-mid-analysis integration test (structured
  timeout/unavailable, no hang, no double-spawn); PTY implemented-or-declared-gap reflected in
  `ide_capability_closure_gate.dart`.

### REQ-009 — Gate truthfulness (Tier D + CI)
- Fail-closed test: run `ecosystem-product-gate.py` in CI mode without siblings → nonzero exit;
  local mode prints loud recorded skip reason in the gate summary.
- Scheduled workflow run recorded: sibling checkouts pinned by immutable commit, real `styio` and
  `spio`/Pafio binaries built, the Vityo desktop product matrix executed, and raw gate plus scoped
  capability receipts published independently for each desktop platform. Receipt issuance must also
  consume the matching-platform, matching-Vityo-commit native PTY report.

## Final end-to-end acceptance target

On one head commit, in order:

1. **Tier D floor:** all standing gates green (delivery-gate checkpoint mode; analyze zero-error; tests
   with coverage floors; architecture/facade/security/performance/hygiene gates; prototype selftest).
2. **Tier P matrix:** with the environment contract satisfied, product workflow receipts, language
   fixture gates, and platform-state verifications green; capability maturity matrix states from
   Evidence.md re-verified and updated.
3. **Per-REQ checks** above executed with outputs archived per REQ label.
4. `manifest_tool.py sync-plan docs/plan` then `validate docs/plan` — clean.
5. Upstream-blocked residuals (compiler facts, spio payload emission) validated on honest blocked/labeled
   behavior and recorded as such — a red Tier P lane caused by upstream breakage is recorded as a real
   result with the pinned refs, never bypassed.

Environment contract note: Tier P is authoritative only when the Vityo, Styio, and Pafio worktrees
are clean, the upstream commits match `toolchain/product-matrix.json`, and
`scripts/ecosystem-product-gate.py --require-real-matrix` emits a successful non-empty scenario
report. `scripts/record-product-matrix-evidence.py` rejects dirty, mismatched, failed, empty,
wrong-platform, wrong-commit, or incomplete native-PTY inputs. The three independent desktop jobs in
`local-ci-gate.yml` are the reference
implementation; a failed platform does not block evidence from another platform.

# Vityo Product Delivery — Evidence

**Purpose:** File-grounded implementation audit and capability maturity matrix for vityo-product-delivery.

**Plan:** `vityo-product-delivery`
**Last updated:** 2026-07-11
**Method:** downstream-tree audit (2026-07-11) with file citations; upstream `SymPolicy/Vityo` used as
reference taxonomy only. Where upstream cites pre-split paths (`frontend/styio_view_app/...`), the
downstream equivalents under `frontend/vityo_app/lib/src/view_ide|view_render` are recorded instead.

## A. Per-requirement findings

| REQ | Finding | Downstream evidence |
|---|---|---|
| REQ-001 | Execution adapter models local CLI + hosted routes but sessions can end in blocked capability states; real JIT execution receipts upstream-blocked | `lib/src/view_ide/.../execution_adapter_io.dart` ~39–90; `docs/design/Vityo-Implementation-Gaps.md` ~85 |
| REQ-001 | Project graph inferred from canonical files (`pafio.toml`, `pafio.lock`, `spio.toml`); machine payloads (`project_graph v1`, `toolchain_state v1`) not yet consumed as authoritative | `Vityo-Implementation-Gaps.md` ~92; `docs/design/Vityo-System-Architecture.md` ~176–177 |
| REQ-002 | Go-to-definition/rename run on token-heuristic index; compiler facts pending | `lib/src/view_ide/language/styio_symbol_index.dart` ~11–48; `diagnostic_revision_gate.dart` ~115 ("local heuristics"); `Vityo-Implementation-Gaps.md` ~37–39 |
| REQ-002 | CLI JSONL contract and capability routing already exist (consume `styio-cli-jsonl-v1`) | `styio_service_connector.dart` ~157, ~287, ~1765–1798; `capability_routed_styio_language_service.dart` |
| REQ-003 | Runtime surfaces exist; no typed bounded event stream contract yet | `view_render` runtime panels; upstream REQ-003 definition |
| REQ-004 | Agent panel + capability routing exist; production provider adapter, OS secret storage are open TODOs | `ide_capability_framework.dart` ~241–673 |
| REQ-005 | Theme override state in memory; profile store missing | `Vityo-Implementation-Gaps.md` ~102–103; gap-ledger item 9 |
| REQ-006 | Module staged-update semantics UI-only; download/staging/reclaim missing | `Vityo-Implementation-Gaps.md` ~104–105 |
| REQ-007 | Packaging: Linux metadata only and incomplete (icons/wrapper/update metadata gaps); no Windows/macOS packaging; CI does build 3-OS release binaries | `packaging/linux/README.md` ~32–40; `.github/workflows/local-ci-gate.yml` |
| REQ-007 | Stale committed benchmark artifact in app root (1126+ lines) | `frontend/vityo_app/benchmark_results.json` |
| REQ-008 | 153 pending convergence checkpoints cite `docs/design/Vityo-End-To-End-Mainstream-IDE-Plan.md`, which does not exist; closest live equivalents are `Vityo-Mainstream-Architecture-Alignment.md`, `Vityo-IDE-Capability-Maturity.md` | `docs/plan/repository-delivery-convergence/Checkpoints.json` goals; `docs/design/` listing |
| REQ-008 | `README_zh.md` still titles the product "Styio View" / `styio_view_app` vs README.md "Vityo" | `README_zh.md` ~1–22; naming policy `docs/README.md` rule 10 |
| REQ-008 | ~69 pre-existing analyzer errors in `test/` | `Vityo-Implementation-Gaps.md` ~151, ~189 |
| REQ-008 | `UnimplementedError` thrown on unhandled `AppCommandId` dispatch | `shell_runtime_model.dart` ~4704–4705, ~7969 |
| REQ-008 | `ShellRuntimeModel` monolith ~8900 lines (commands, lifecycle incl. daemon restart ~1102–1218, multi-domain state) | `lib/src/view_render/shell/shell_runtime_model.dart` |
| REQ-008 | DAP transport kills adapter after 2s grace; orphan risk | `debug_adapter_process_transport_io.dart` ~44–89 |
| REQ-008 | Terminal native PTY placeholder paths | `terminal_surface.dart` ~68, ~83, ~280 |
| REQ-009 | `ecosystem-product-gate.py` returns 0 when sibling `styio-pafio` missing (silent skip) | `scripts/ecosystem-product-gate.py` ~16–26 |
| REQ-009 | Product workflow tests skipped unless `VITYO_PRODUCT_GATE=1`; default CI green ≠ product-matrix coverage (admitted in rollup) | `hosted_product_workflow_test.dart`; `docs/rollups/CURRENT-STATE.md` line 21 |

## B. IDE capability maturity matrix

| Capability | Status | Grounding |
|---|---|---|
| Editor + syntax highlighting | COMPLETE (local) / PARTIAL (semantic tokens need CLI) | custom engine `view_ide/editor` piece-tree + `StyioSyntaxHighlighter`; semantic spans when StyioService available |
| Diagnostics | PARTIAL | CLI JSONL diagnostics + local heuristics; revision-bound (`diagnostic_revision_gate.dart`); 3 local quick-fix patterns |
| Completion | PARTIAL | connector decodes completions; degrades when toolchain blocked (`styio_service_connector.dart` ~135–136) |
| Go-to-definition / rename | PARTIAL | heuristic `StyioSymbolIndex`; cross-file blocked pending compiler facts |
| Build / run | PARTIAL | local CLI + hosted routes + sandbox exist; real receipts upstream-blocked; smoke only under product gate |
| Debugger (DAP) | PARTIAL | full stack (codec/session/transport/console UI); needs device smoke with real `lldb-dap`; 2s kill grace |
| Package management (spio) | PARTIAL | workflow-lane UI + file inference; machine payloads pending |
| Settings | PARTIAL | settings surface + toolchain/agent config; theme profile store missing |
| Runtime visualization | PARTIAL | surfaces exist; no typed event contract |
| AI panel | PARTIAL | routing exists; no production provider adapter/secret storage |
| Module host | PARTIAL | staging semantics UI-only |
| Packaging/distribution | MISSING (formal) | Linux metadata incomplete; no installers/update channel |

## C. Upstream-blocked dependency register

| External dependency | Owner repo | Consuming downstream files | Honest-state behavior required |
|---|---|---|---|
| Stable resolution facts (defs/refs/rename edits/formatting) over `styio-cli-jsonl-v1` | styio-nightly (`docs/external/for-ide` contracts) | `styio_service_connector.dart`, `capability_routed_styio_language_service.dart`, `styio_symbol_index.dart` | heuristic labeling; rename refusal cross-file |
| Execution contract / real JIT receipts | styio-nightly | `execution_adapter_io.dart`, execution controller | structured capability gap, no fake success |
| `project_graph v1` / `toolchain_state v1` machine payloads | pafio-nightly (spio contracts; mirrored REQ-IDE-001 there) | `ProjectGraphAdapter` + io implementation | file-inference fallback labeled with source confidence |

## D. Already remediated (do not re-deliver)

| Area | Evidence |
|---|---|
| Prototype dev-server security (token/cookie auth, mutation off by default) | `prototype/dev_server.py` ~18–40; `docs/audit/external-audit-vityo.md` ~34–36; `prototype/test_dev_server_security.py` |
| Execution sandbox (argv, cwd containment, timeout, output caps) | `execution_sandbox.dart` ~13–89; `check_security_baseline.py` |
| Execution overlay symlink-escape class | `external-audit-vityo.md` ~28; `execution_adapter_test.dart` containment cases |
| view_ide/view_render layer split + facade enforcement | `scripts/check_architecture_boundaries.py`, `check_compat_facades.py` |
| 3-OS desktop release builds in CI | `.github/workflows/local-ci-gate.yml`, `windows-native.yml` |

## E. Upstream reference deltas

- Upstream `vityo-product-delivery` (SymPolicy/Vityo `docs/plan/`): REQ-001..009 defined, 19 checkpoints
  all pending, paths pre-date the downstream rename and layer split. Downstream absorbs the taxonomy;
  the node graph here is downstream-grounded and includes audit closure items upstream does not have
  (missing-source-doc traceability, analyzer debt, dispatch totality, monolith decomposition,
  fail-closed gates).
- Upstream rollups are stale (CURRENT-STATE 2026-04-21 vs downstream 2026-06-25).

## F. Priority ordering justification

1. REQ-008 doc-traceability + analyzer debt + dispatch totality first — they are cheap, independent, and
   every later node cites `flutter analyze`/tests as evidence.
2. ShellRuntimeModel decomposition after those two (same file), before feature nodes that would otherwise
   grow the monolith.
3. Feature nodes (REQ-001/002/003/004/005/006) parallel after architecture sign-off — disjoint modules.
4. REQ-009 gate truthfulness and REQ-007 packaging close the delivery story; final validation last.

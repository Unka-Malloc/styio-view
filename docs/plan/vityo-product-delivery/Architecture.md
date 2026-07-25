# Vityo Product Delivery — Architecture

**Purpose:** Module map, layer boundaries, adapter contracts, and ShellRuntimeModel decomposition targets for product delivery.

**Plan:** `vityo-product-delivery`
**Last updated:** 2026-07-11
**Nature:** brownfield record aligned with the gate-enforced layer split; adds the decomposition target
for the shell monolith and the interface contracts each implementation node consumes.

## 1. Layer map (gate-enforced today)

| Layer | Path | Responsibility | Rule |
|---|---|---|---|
| Domain / contracts | `frontend/vityo_app/lib/src/view_ide/` | editor core, language, workspace, execution, backend_toolchain, module_host, agent, environment, shell_runtime domain models | **No Flutter UI imports** (`check_architecture_boundaries.py`) |
| Presentation | `frontend/vityo_app/lib/src/view_render/` | shell UI, editor surface, runtime/agent/debug/settings/terminal surfaces | consumes view_ide interfaces only |
| Composition | `frontend/vityo_app/lib/src/app/` | `app_bootstrap.dart` DI and adapter wiring | the only place adapters are constructed |

Dependency direction: `view_render` → shell composition → `view_ide` services → adapters → external
processes/HTTP. No reverse imports; legacy one-line export facades stay frozen
(`check_compat_facades.py`).

## 2. External seams (adapter pattern, uniformly)

| Seam | Adapter | Transport | Contract |
|---|---|---|---|
| Styio language service | `StyioServiceConnector` (+ optional daemon adapter) | process spawn, `styio-cli-jsonl-v1` JSONL stdout | `docs/contracts/LanguageServiceAdapter.md`; capability-routed via `capability_routed_styio_language_service.dart` |
| Styio execution | `ExecutionAdapter` (io) | sandboxed process (local) / hosted control-plane HTTP | receipts reuse documented workflow success-payload shapes |
| spio project graph | `ProjectGraphAdapter` | CLI or hosted HTTP | `project_graph v1`, `toolchain_state v1` (versioned; fail closed on unknown majors) |
| Debugging | DAP process transport | process spawn (lldb-dap/codelldb) | DAP; separate from language seam |
| AI provider | provider adapter (new, REQ-004) | HTTPS streaming | OpenAI-compatible; keys via platform secret storage |

Uniform degradation contract: every seam exposes a **capability-state machine**
(available / degraded-heuristic / blocked-with-reason). Implementation nodes must reuse the existing
capability-gap result type — no parallel error shapes.

## 3. ShellRuntimeModel decomposition target (REQ-008d)

Current: `view_ide/shell_runtime/shell_runtime_model.dart` started at ≈ 9100 lines mixing command routing, service
lifecycle (incl. StyioService daemon restart ~1102–1218), and state for unrelated product domains.

Target: `ShellRuntimeModel` becomes a **composition root** (target ≤ 800 lines) delegating to per-domain
controllers, each a `ChangeNotifier` with one responsibility, wired in `app_bootstrap.dart`:

| Controller (new file under `view_ide/shell_runtime/controllers/`) | Owns | Budget |
|---|---|---|
| `execution_controller.dart` | run/build sessions, receipts, runtime event decode | ≤ 1200 lines |
| `language_controller.dart` | StyioService lifecycle, daemon restart policy, analysis scheduling glue | ≤ 1200 |
| `debug_controller.dart` | DAP session lifecycle, debug console state | ≤ 1000 |
| `module_controller.dart` | module staging state machine surface | ≤ 1000 |
| `agent_controller.dart` | AI panel state, provider adapter consumption | ≤ 1000 |
| `settings_controller.dart` | settings/theme profile surface state | ≤ 800 |

Extraction order (each step lands with the full suite green): 1) settings, 2) agent, 3) debug,
4) modules, 5) language, 6) execution, 7) shrink the root to routing + cross-domain coordination.
Controllers never import each other's internals; cross-domain effects go through the composition root.
Notification granularity must match today's rebuild behavior (performance-budget gate guards this).

## 4. Interface contracts consumed/extended per node

| Node | Consumes | Extends/creates |
|---|---|---|
| Doc traceability | docs gates | citation mapping record |
| Analyzer debt | current public contracts | none (test fixes only) |
| Dispatch totality | capability-gap result type | exhaustive `AppCommandId` switch |
| Decomposition | all existing controller state | controller files per table above |
| Process lifecycle | controllers (language/debug), capability framework | shutdown-grace policy, PTY capability state |
| Language facts | `styio-cli-jsonl-v1` decode, revision gate | fact-preference routing, heuristic labeling, rename refusal |
| Execution receipts | sandbox contract, workflow payload shapes | receipt render model in execution controller |
| Project graph payloads | `project_graph v1` / `toolchain_state v1` schemas | source-confidence model |
| Runtime viz | receipts/event payloads | typed bounded event stream (view_ide, Flutter-free) |
| AI adapter | capability framework, secret storage | provider adapter interface + OpenAI-compatible impl |
| Theme store | DataStore seam | versioned profile schema |
| Module lifecycle | DataStore seam, adapter transports | staged-update state machine with atomic swap |
| Gates/packaging | delivery-gate stack, release-readiness gate | fail-closed CI mode, scheduled lane, per-OS packaging sets |

## 5. Deliberate pattern decisions

| Decision | Where | Why it earns its complexity |
|---|---|---|
| Adapter at every external seam | §2 | processes/HTTP fail independently of UI; capability states need one choke point |
| Capability-state machine for degradation | all seams | product invariant "honest missing" requires uniform blocked/heuristic labeling |
| Composition root + per-domain ChangeNotifier controllers | §3 | keeps the existing state idiom (no Riverpod/Bloc migration risk) while restoring one-responsibility files |
| Staged-update state machine with stage-then-swap | module_host | product invariant: updates never mutate the active copy; atomicity is a data-loss guard |
| Versioned payload schemas, fail-closed on unknown majors | project graph, profiles | cross-repo contracts drift; failing closed beats silent misreads |
| Bounded buffers (drop-oldest + counters) | runtime events, AI streaming | long runs must not exhaust memory; counters keep honesty about drops |
| **Pattern-free by choice** | editor piece-tree internals, syntax highlighter, prototype | already single-purpose and performance-sensitive; no indirection added |

## 6. Scaffold status

No scaffold code is created by this node. Every module except the controllers directory and the AI
provider adapter already exists; creating empty controller files ahead of the decomposition node would
violate the one-commit-one-responsibility rule. The decomposition and AI nodes create their files
together with tests.

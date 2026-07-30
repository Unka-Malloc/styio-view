# Vityo — Evidence

**Plan:** `vityo`
**Purpose:** Record current repository facts that determine the remaining Vityo execution order and stop conditions.
**Last updated:** 2026-07-30

## Current repository facts

| Fact | Repository evidence | Execution consequence |
|---|---|---|
| The product split is complete. | `products/vityo_app`, `products/vityo_coding_agent`, and `packages/vityo_agent_protocol` exist; the product-line boundary gate passes. | The atomic cutover Node is historical and must never be replayed. |
| Vityo has a canonical protocol-oriented Agent Client foundation. | `products/vityo_app/lib/src/ide/agent_client/`, `lib/src/ide/workbench/agent_collaboration/`, and `lib/src/presentation/agent_workbench/`. | These are the keep/converge seams for the remaining IDE migration. |
| Legacy IDE-owned Agent runtime behavior still exists. | `lib/src/view_ide/agent_client/`, `app/app_bootstrap.dart`, shell controllers, and current tests still construct provider transport, provider configuration, coding-loop, tool-loop policy, and durable session-controller objects. | Final validation must not start until Node `014e7fb0-3f51-4033-be71-eca130a4a2ea` removes this ownership completely. |
| The first-party companion already owns Agent-runtime domains. | `products/vityo_coding_agent/lib/src/providers/`, `orchestration/`, `sessions/`, `tools/`, `policy/`, and `multi_agent/`. | Do not move these responsibilities back into the IDE and do not reopen the completed Coding Agent plan. |
| The IDE full runner exists and its plan-only mode maps eight requirements exactly once. | `scripts/vityo_quality.py --product ide --suite full --plan-only` and `tests/acceptance/vityo_app/full_runner_acceptance_test.py`. | Plan-only inspection is safe and does not consume final-run authority. |
| The full runner is not yet ready for a simple final executor. | `_run_plan_validation()` assumes an unavailable sibling `better-plan` checkout; early IDE harness failures can exit before a bounded receipt; there is no explicit `--preflight`. | Node `63016713-c527-4428-a87d-2613f8c43ac9` must close these harness gaps without executing `ide/full`. |
| No final IDE receipt exists. | `artifacts/validation/vityo-full.json` is absent and the final-validation Node is pending. | No agent may claim REQ-IDE-001 through REQ-IDE-008 final acceptance yet. |
| The Coding Agent plan is sealed. | All Coding Agent Nodes are completed and its Requirements, Architecture, Validation, Checkpoints, and protocol fingerprint are preserved. | Consume compatible protocol evidence only; never rerun or rewrite that plan during IDE closure. |

## Current blockers before final validation

1. Remove direct IDE model/provider and coding-loop ownership.
2. Remove provider-profile UI and behavior-bearing capability claims from the IDE.
3. Preserve protocol sessions, bounded context export, permission presentation, revision-bound
   proposals, workspace transactions, and verification receipts.
4. Add a side-effect-free full-suite preflight.
5. Make all full-harness failure paths produce a bounded diagnostic receipt.
6. Bind final evidence to the acceptance fixtures and protocol inputs that were actually executed.

## Evidence interpretation rules

1. A passing focused Node receipt proves only that Node's declared capability.
2. Completed Node text is historical evidence, not an instruction to run it again.
3. `--plan-only` and future `--preflight` output prove runner readiness only; they are not product
   acceptance.
4. The final receipt is valid only for its recorded commit and source fingerprint.
5. A missing tool, fixture, compatible Agent, or required path is `blocked` or `failed`, never
   skipped-as-passed.
6. A failed final receipt must be preserved. The unchanged candidate must not be rerun.

## Authoritative execution reference

Use [the Better Plan execution runbook](../EXECUTION-RUNBOOK.md) for exact lifecycle transitions,
remaining Node order, per-Node work phases, failure routing, and final-run semantics.

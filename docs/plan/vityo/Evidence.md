# Vityo — Evidence

**Plan:** `vityo`
**Purpose:** Record current repository facts that determine Vityo's sealed delivery state and stop conditions.
**Last updated:** 2026-08-01

## Current repository facts

| Fact | Repository evidence | Execution consequence |
|---|---|---|
| The product split is complete. | `products/vityo_app`, `products/vityo_coding_agent`, and `packages/vityo_agent_protocol` exist; the product-line boundary gate passes. | The atomic cutover Node is historical and must never be replayed. |
| Vityo collaborates only through the protocol-oriented Agent Client. | `products/vityo_app/lib/src/ide/agent_client/`, `lib/src/ide/workbench/agent_collaboration/`, and `lib/src/presentation/agent_workbench/`; IDE-owned model/provider and coding-loop surfaces are removed. | Do not reintroduce IDE-owned Agent runtime ownership. |
| The first-party companion already owns Agent-runtime domains. | `products/vityo_coding_agent/lib/src/providers/`, `orchestration/`, `sessions/`, `tools/`, `policy/`, and `multi_agent/`. | Do not move these responsibilities back into the IDE and do not reopen the completed Coding Agent plan. |
| The IDE full runner supports plan-only and preflight without consuming final-run authority. | `scripts/vityo_quality.py --product ide --suite full --plan-only` / `--preflight` and `tests/acceptance/vityo_app/full_runner_acceptance_test.py`. | Plan-only and preflight prove harness readiness only. |
| Final IDE validation is recorded. | `artifacts/validation/vityo-full.json` binds commit `7fde72c0fa6f6c0e63e3c616b56ba166839c5ce4` with overall `passed` and REQ-IDE-001 through REQ-IDE-008 each `passed`. | Claim final acceptance only for that commit and source fingerprint; do not rerun the unchanged candidate. |
| The Coding Agent plan is sealed. | All Coding Agent Nodes are completed and its Requirements, Architecture, Validation, Checkpoints, and protocol fingerprint are preserved. | Consume compatible protocol evidence only; never rerun or rewrite that plan during IDE closure. |
| The Vityo plan is sealed. | Every Vityo Node is `completed` / `accepted`, including final validation `c5bfe53f-4094-4771-b323-12a99750c95b`. | No further Vityo implementation or final-validation Node remains advanceable. |

## Current blockers before final validation

None. Final validation has completed for the recorded commit and fingerprint.

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

Use [the Better Plan execution runbook](../EXECUTION-RUNBOOK.md) for current lifecycle transitions,
historical playbooks, failure routing, and the rule that completed Nodes are never replayed.

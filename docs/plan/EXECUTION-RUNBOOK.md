# Vityo Execution Runbook

**Purpose:** Route authorized Vityo work through current product contracts, focused verification, and final delivery without duplicating an installed planning skill's lifecycle.

**Last updated:** 2026-09-08

## Authority And Scope

The current user request and its existing approvals define the work. A request to review or edit a Plan authorizes that planning work only. A pending item, a historical delivery, or the existence of `docs/plan/` does not authorize implementation, regression, or publication.

Use the ordinary repository workflow for a small independently acceptable change. A Plan is not a prerequisite for routine investigation, documentation edits, or an already-authorized bounded fix. Follow [the contributor rules](../specs/CONTRIBUTOR-AND-AGENT-SPEC.md), preserve concurrent changes, and inspect the relevant product and protocol contracts before implementation.

Resolve discoverable facts and ordinary in-scope defects directly. Report material findings without treating every report as an approval request. If the work needs a new product decision, public-contract change, risk allowance, or explicitly required approval, first prepare the concrete proposal using existing authority. Pause only the dependent work and continue independent authorized work. Reuse prior approval only when it covers the same action and risk boundary.

## Planning Skill Boundary

When the authorized task uses Better Plan, read the active installed skill and use its current tool entrypoint, schema, role contracts, and recovery instructions. Do not copy lifecycle commands, role counts, state formats, or sample task identities into this repository runbook. Repository policy and the current user request still bound what the tool may execute.

Treat completed delivery state and evidence as history. Never replay or rewrite them to manufacture authority or a passing result. Do not create a compatibility reader, revive a removed lifecycle command, or recreate cleared planning state merely to perform ordinary repository work. If a tool instruction conflicts with current authorization or final-regression policy, report the specific conflict and continue work that does not depend on that tool transition.

## Implementation And Focused Verification

1. Identify the smallest independently acceptable Vityo capability or scenario and its affected callers, protocol consumers, tests, and owner documents.
2. Inspect actual source and contract paths. If a planned path is missing, determine whether the task creates it, an existing owner already provides it, or the plan needs correction. Do not assume every missing path blocks all work, and do not invent a parallel implementation.
3. Keep product effects within authorized scope. Preserve the IDE's protocol, permission, proposed-change review, and verification boundaries; repository rules also govern permanently retained assets.
4. Select focused checks from [the test catalog](../assets/workflow/TEST-CATALOG.md) and the affected product's documented tooling. A planning or documentation-only change does not require unrelated compiler, Flutter, or release suites.
5. Repair ordinary implementation, documentation, and focused-test issues inside the same closure. Reuse passing evidence while its relevant inputs remain unchanged.
6. Update affected owner documents and generated indexes. Keep evidence privacy-safe and repository-relative; do not publish machine identities, credentials, backend runtime payloads, or raw private logs.

A real missing environment, external dependency, or approval is an unresolved requirement, not a passing check. Investigate it within existing authority, state the unblock condition, and keep independent work moving.

## Final Regression And Handoff

Follow [Post-Commit CI Checks](../specs/POST-COMMIT-CI-CHECKS.md) for final-regression order, developer decisions after a complete-regression failure, authorized publication, CI observation, and completion criteria. Finish source review, in-scope repairs, and focused verification before the one required complete regression. Do not weaken candidate, receipt, security, or platform gates to obtain a pass.

Report the delivered behavior, focused evidence, final-regression result when required, and any unresolved acceptance or decision. An actionable partial handoff is still incomplete verification. A local-only request does not require a commit or push solely to satisfy this runbook.

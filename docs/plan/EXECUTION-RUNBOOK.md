# Better Plan Execution Runbook

**Purpose:** Give a mechanical, fail-closed procedure for planning, implementing, validating, repairing, and auditing Vityo Better Plan Nodes without relying on unrecorded agent judgment.

**Last updated:** 2026-07-31

## 1. Authority Rules

1. A request to inspect or improve the Plan authorizes Plan edits only. It does not authorize
   implementation or final regression.
2. Select exactly one Node whose goal matches the current request. Never execute a Node merely
   because it is pending or eligible.
3. `completed` and `accepted` Nodes are immutable history. Read them for evidence; never replay,
   rewrite, or “finish” them again.
4. Execution authority comes from `prerequisites` plus the current user request. `next`, file order,
   prose, and `status_reason` are not authority.
5. Use the `manifest_tool.py` supplied by the active Better Plan skill. Do not hard-code a home
   directory, sibling checkout, or machine-specific path into repository files.
6. Never hand-edit `Manifest.json`, Node status, acceptance state, evidence references, regression
   receipts, or graph edges. Use `add-node`, `edit-node`, `rewire`, `dispatch`, and `advance`.
7. An implementation Node runs only focused regression. Only a `final_validation` Node may run the
   full suite.

## 2. Mandatory Node Read

Before changing a file, the executing agent must read and write down the following Node fields:

| Field | Required decision |
|---|---|
| `id`, `status`, `role` | Confirm that this is the selected lifecycle and that its role matches the requested work. |
| `prerequisites` | Confirm every prerequisite is `completed`; otherwise stop without editing. |
| `goal`, `description` | Restate the single closure in one sentence. If two independent closures are present, stop and repair the Plan. |
| `requirements` | Identify the observable product requirements affected by the Node. |
| `design.artifact` | Read the named SSOT before implementation. |
| `design.owned_paths` | Establish expected ownership; adjacent changes require an explicit reason. |
| `design.scaffold_paths` | Locate the existing implementation seams. Missing paths are a design blocker, not permission to invent a parallel architecture. |
| `design.acceptance_paths` | Read the tests/contracts that define success before editing production code. |
| `design.symbols`, `interfaces`, `dependencies` | Build an exact keep/modify/remove worklist. |
| `acceptance_criteria` | Convert every criterion into a yes/no check; do not substitute “looks good.” |
| `regression.commands`, `regression.paths` | Run only the declared commands through the lifecycle and do not broaden to a full suite. |

If any required field contradicts the source tree or the current product SSOT, stop implementation
and return a design finding to the native main. Do not resolve a design contradiction with a
compatibility facade.

## 3. Plan-Only Procedure

For a planning request:

1. Inspect workspace status and the selected Node.
2. Compare the Node with Requirements, Evidence, Architecture, Validation, and current repository
   facts.
3. Use one existing Node for one capability. Add a Node only when a genuinely separate future
   capability is missing or a terminal historical Node cannot be revised.
4. Edit Plan documents with normal file editing tools and mutate Node state only through
   `manifest_tool.py`.
5. Run workspace validation and requirement-label checking.
6. Stop. Do not call `dispatch`, `advance ... regression-requested`, or a product full-suite command.

## 4. Implementation Lifecycle Procedure

Use `<tool>` for the active Better Plan `manifest_tool.py` and `<node>` for the selected UUID.

1. Ask for the state-machine action:

   ```text
   python3 <tool> next-action <node> docs/plan
   ```

2. If the result is `main_acceptance_decision`, correct the Node contract with `edit-node`; do not
   dispatch until the contract matches current source facts.
3. If the result is `dispatch_acceptance_designer`, run:

   ```text
   python3 <tool> dispatch <node> docs/plan --role acceptance_designer
   ```

   Record the returned dispatch id, load only the Better Plan acceptance-designer role reference,
   and launch exactly one leaf with the returned prompt. The designer reads design and acceptance
   artifacts, changes no product code, and returns a frozen acceptance decision. After that leaf
   exits, run:

   ```text
   python3 <tool> advance <node> docs/plan \
     --event acceptance-designer-exited \
     --dispatch-id <dispatch-id>
   ```

4. If the result is `dispatch_executor`, run:

   ```text
   python3 <tool> dispatch <node> docs/plan --role executor
   ```

   Record the new dispatch id, load only the Better Plan executor role reference, and launch exactly
   one leaf with the returned prompt. The executor:
   - works through the Node's keep/modify/remove list in dependency order;
   - closes one independently testable slice before the next;
   - fixes ordinary compile, lint, unit, and local-integration defects in the same dispatch;
   - makes no unrelated cleanup;
   - never runs the full suite.
5. When the executor exits, run:

   ```text
   python3 <tool> advance <node> docs/plan \
     --event executor-exited \
     --dispatch-id <dispatch-id>
   ```

   The lifecycle runs the declared focused regression automatically. Do not run the same commands
   manually in parallel.
6. On `correction_required`, classify the evidence:
   - ordinary implementation defect: dispatch the same Node executor again without changing
     acceptance;
   - real design or product-semantics defect: revise the same Node and re-freeze acceptance;
   - missing external authority or dependency: persist the decision; do not fake success:

     ```text
     python3 <tool> block <node> docs/plan --reason "<blocker and unblock condition>"
     python3 <tool> defer <node> docs/plan --reason "<reason and reactivation condition>"
     ```

     Use `block` for a present impasse and `defer` for intentionally scheduled future work.
7. After focused regression passes, dispatch the single read-only auditor:

   ```text
   python3 <tool> dispatch <node> docs/plan --role auditor
   ```

   Load only the Better Plan auditor role reference. The auditor checks only scope, criteria,
   changed paths, and the bound receipt.
8. Advance `audit-passed` with that auditor dispatch id only for a real PASS:

   ```text
   python3 <tool> advance <node> docs/plan \
     --event audit-passed \
     --dispatch-id <dispatch-id>
   ```

   Completion ends the lifecycle; never auto-start the next Node.

After every `dispatch` or `advance`, treat the returned action as the only authorized next lifecycle
operation. If it is absent, contradictory, or not one of the documented actions, stop and return the
tool output to native main; do not guess a transition.

## 5. Evidence and Failure Rules

| Situation | Required action | Forbidden action |
|---|---|---|
| A declared path is missing | Stop as a design blocker. | Create a similarly named parallel implementation. |
| Focused test fails because of this Node | Repair in the same executor lifecycle. | Open an unrelated repair Node. |
| Test exposes a closed lifecycle defect | Return the exact failing seam to native main for a bounded repair Node. | Add a compatibility shim or silently weaken the test. |
| Protocol lacks a required message | Stop and revise the versioned protocol design with both consumers identified. | Import Agent runtime code or add an unversioned callback. |
| Tool, fixture, or host is missing | Record `blocked` or `failed` truthfully. | Report skipped work as passed. |
| Source changes during validation | Fail with source-fingerprint drift. | Reuse a receipt from the earlier source state. |
| A full run fails | Preserve its receipt and route the failed requirement to a repair lifecycle. | Rerun the unchanged candidate until green. |

Evidence may contain command identity, exit code, bounded duration, schema/fixture/content digests,
and repository-relative paths. It must not contain secrets, personal paths, machine identity,
backend runtime data, or unbounded raw logs.

## 6. Completed Vityo Execution Order

These lifecycles are completed immutable history. Their order is retained as provenance and they
must not be replayed:

1. `014e7fb0-3f51-4033-be71-eca130a4a2ea` — remove IDE-owned model/provider and coding-loop runtime
   surfaces, leaving the Agent Workbench backed only by the versioned Agent Client.
2. `63016713-c527-4428-a87d-2613f8c43ac9` — harden the IDE full-validation harness through
   side-effect-free preflight and fail-closed receipts; this Node must not run `ide/full`.
3. `c5bfe53f-4094-4771-b323-12a99750c95b` — run the final platform-independent IDE regression for
   one immutable candidate and record the final receipt.

Future work must use a distinct eligible Node rather than reopening any lifecycle above.

## 7. Historical Protocol-Only Agent Boundary Playbook

Node `014e7fb0-3f51-4033-be71-eca130a4a2ea` used these phases. The removed paths and symbols below
are immutable migration provenance, not current implementation or compatibility surfaces:

1. **Inventory:** enumerate, before editing:
   - every file under `products/vityo_app/lib/src/view_ide/agent_client/`;
   - every `agent_*.dart` controller or facade under
     `products/vityo_app/lib/src/view_ide/shell_runtime/`;
   - every file under `products/vityo_app/lib/src/view_render/agent_workbench/`;
   - every root-level `products/vityo_app/test/agent_*.dart` test and
     `extension_agent_provider_contributions_test.dart`.

   For each item, record `remove`, `replace caller`, or `preserve behavior at <canonical path>`.
   `keep in place` is not a valid disposition for either legacy subtree.
2. **Keep and converge:** keep `products/vityo_app/lib/src/ide/agent_client/`,
   `products/vityo_app/lib/src/ide/workbench/agent_collaboration/`, and
   `products/vityo_app/lib/src/presentation/agent_workbench/` as the canonical client, projection,
   and UI seams.
3. **Compose:** make `app_bootstrap.dart` and shell state construct Agent process/client,
   protocol-session, collaboration-projection, context-export, permission-presentation, and
   workspace-transaction services only.
4. **Remove:** delete IDE model-provider transport/configuration/credential routing, prompt profiles,
   coding-loop orchestration, durable Agent history, provider fallback/retry, Agent tool-loop policy,
   and provider-profile UI. Do not leave exports, aliases, dormant branches, or compatibility tests.
5. **Preserve IDE authority:** keep revisioned context export, capability discovery, permission
   presentation, proposed-change review, conflict detection, apply/reject/revert, and verification
   receipt projection.
6. **Prove:** run the Node's focused Agent Client, Workbench, transaction, boundary, and no-Agent
   tests. A one-time source scan must find no removed production symbols.
7. **Close documentation:** mark the direct-provider gap closed only after code and tests are removed;
   update capability metadata without claiming that Vityo executes models.

If an existing protocol message cannot carry a required plan, permission, proposal, artifact, or
receipt, stop at phase 2 and return a protocol design blocker. Do not preserve the old controller as
a fallback.

### 7.1 Fixed source disposition

This matrix is authoritative for the final source shape. “Preserve behavior” means re-express only
the IDE-owned behavior through an existing canonical seam before deleting the legacy source. It
never means moving an old runtime object intact.

| Current source | Required disposition | Canonical destination or proof |
|---|---|---|
| `lib/src/ide/agent_client/**` | Keep and modify only where the protocol/client contract requires it. | Versioned transport, process supervision, session reducer, context/MCP host, tool security. |
| `lib/src/ide/workbench/agent_collaboration/**` | Keep and modify. | Immutable task, permission, proposal, transaction, and receipt projections. |
| `lib/src/presentation/agent_workbench/**` | Keep and make the shell route here. | Agent Workbench widgets consume projections only. |
| `lib/src/view_ide/agent_client/**` | Delete the entire subtree after behavior disposition. | Provider/coding/session/tool-loop behavior is removed; context, permission, and workspace-effect behavior is covered by the canonical client, MCP host, security policy, or workspace transaction service. |
| `lib/src/view_ide/shell_runtime/**/agent_*.dart` | Remove or replace callers; no legacy Agent controller/facade remains. | Workbench command port, Agent Client registry, MCP host, and workspace transaction APIs. |
| `lib/src/view_render/agent_workbench/**` | Delete the entire subtree after the shell uses `lib/src/presentation/agent_workbench/**`. | No provider profile, API key, endpoint, retry-provider, or local coding-loop UI remains. |
| `lib/src/app/app_bootstrap.dart` | Modify; remove provider factory/configurator, prompt-profile, coding-controller, tool-loop, and durable Agent-history construction. | Construct supervised Agent descriptors/clients, collaboration projections, context/MCP host, and IDE transaction services only. |
| Agent capability/module metadata | Modify; remove behavior-bearing direct-provider or coding-loop claims. | Describe Agent Client and Agent Workbench capabilities only. |
| Legacy provider/coding/session/tool-loop tests | Delete with their production subject. | Do not rewrite them to assert a compatibility shim. |
| IDE-owned context/permission/transaction behavior tests | Preserve or migrate to canonical Agent Client, MCP/security, Workbench, and workspace-transaction tests. | The focused acceptance paths named by the Node remain passing. |

The phase-6 handoff must prove all four source-shape assertions:

1. `products/vityo_app/lib/src/view_ide/agent_client/` is absent.
2. `products/vityo_app/lib/src/view_render/agent_workbench/` is absent.
3. No `agent_*.dart` controller or facade remains under
   `products/vityo_app/lib/src/view_ide/shell_runtime/`.
4. Production Vityo Dart source has no reference to
   `AgentCodingSessionController`, `NetworkAgentProviderTransport`,
   `ConfiguredAgentProviderAdapterFactory`, `AgentCodingToolLoopRuntime`,
   `AgentProviderConfigurator`, `AgentPromptProfile`, or
   `LocalOnlyAgentProviderAdapter`.

Use `rg --files` for path inventory and `rg -n --glob '*.dart'` for the symbol scan. These are
one-time migration observations recorded in the lifecycle handoff, not new permanent repository
gates. Any match is a failure unless it is in immutable archived provenance.

### 7.2 Phase exit checklist

The executor must not move to the next phase until the current row is true:

| Phase | Exit condition |
|---|---|
| Inventory | Every legacy source and test has one disposition and one canonical proof owner. |
| Canonical coverage | The relevant canonical contract/acceptance test is identified before editing; any newly exposed missing behavior is demonstrated as failing before its implementation and passes afterward. |
| Composition | Startup and no-Agent smoke use no legacy provider/controller constructor. |
| UI convergence | The active route renders the canonical Agent Workbench and contains no provider-profile controls. |
| Deletion | Both legacy subtrees and all old exports/callers/tests are gone in the same change. |
| Focused proof | Every declared focused command passes and the one-time scans are empty. |
| Documentation | Implementation Gaps and metadata describe the achieved protocol-only boundary. |

## 8. Full-Harness Readiness Playbook

Node `63016713-c527-4428-a87d-2613f8c43ac9` must:

1. add `ide/full --preflight`, which verifies tools, declared roots, requirement mapping, receipt
   destination, host classification, and immutable-source readiness without running suites or
   writing the final receipt;
2. remove the product runner's hard-coded assumption that Better Plan lives in a sibling checkout;
   Better Plan workspace validation remains owned by the lifecycle tool;
3. make every failure before, during, or after suite iteration emit one bounded receipt with a stable
   failure code and no raw exception or machine data;
4. include IDE acceptance fixtures and protocol schema inputs in the source/evidence digest;
5. keep `--plan-only` deterministic and side-effect free;
6. prove all behavior with injected/synthetic runners only and never invoke the actual full suite.

### 8.1 Fixed preflight order

`ide/full --preflight` evaluates these checks in this order and never calls a suite runner:

1. validate the fixed plan contains each `REQ-IDE-001` through `REQ-IDE-008` once and each suite name
   is unique;
2. verify every fingerprint root, acceptance-fixture root, and protocol-schema input exists;
3. resolve the tools required by all eight suite descriptors without launching them;
4. classify the host as `windows`, `macos`, or `linux`;
5. resolve the current commit and reject an uncommitted or source-dirty candidate;
6. compute the source, protocol-schema, and acceptance-fixture digests;
7. inspect an existing receipt and reject a duplicate commit/source fingerprint;
8. verify the requested receipt destination is structurally usable without creating, truncating, or
   replacing the receipt.

Preflight prints one bounded JSON document with `mode: "preflight"`, `ready`, the canonical
requirement plan, the ordered check results, commit/host/digests when available, and stable failure
codes. It returns nonzero when `ready` is false. It writes no file and must leave process, suite,
Agent, and receipt-runner spies untouched.

### 8.2 Stable failure and receipt contract

Use stable codes rather than raw exceptions. The minimum externally observable set is:

| Code | Meaning |
|---|---|
| `invalid_requirement_mapping` | The eight-entry plan is incomplete, duplicated, or reordered. |
| `source_path_missing` | A declared source, schema, or fixture root is absent. |
| `tool_unavailable` | A required executable cannot be resolved. |
| `unsupported_host` | The host is outside the supported platform-independent classes. |
| `commit_unavailable` | A commit cannot be resolved. |
| `dirty_candidate` | A source-bearing path differs from the candidate commit. |
| `duplicate_candidate_receipt` | The destination already records the same commit/fingerprint. |
| `receipt_destination_unavailable` | The destination cannot safely receive an atomic receipt. |
| `suite_failed` | One or more named suites returned a nonzero result. |
| `source_fingerprint_drift` | Declared sources changed during execution. |
| `validation_harness_failed` | An unexpected bounded harness path failed. |
| `receipt_write_failed` | Atomic receipt replacement itself failed. |

Every formal full receipt uses these top-level fields:

```text
schema_version
product
suite
status
failure_code
commit
platform
source_fingerprint
protocol_schema_sha256
acceptance_fixtures_sha256
requirements
```

`requirements` contains exactly eight canonical entries, each with `status`, `suite`, and
`duration_ms`; a failed entry may add only a stable `failure_code`. If identity or a digest cannot
be resolved during an early failure, its field is `null`; the implementation must not invent a
value. If atomic destination writing itself fails, return `receipt_write_failed`, print only a
bounded machine-neutral failure envelope, and leave no partial file. Preflight must catch normally
detectable destination failures before final-run authority is consumed.

### 8.3 Harness test matrix

The focused tests must inject, and assert without launching a real suite:

| Fixture | Expected result |
|---|---|
| Complete clean candidate | Preflight `ready: true`; no receipt written. |
| Duplicate/missing requirement | `invalid_requirement_mapping`; no runner called. |
| Missing tool/path/schema/fixture | Matching stable code; no runner called. |
| Dirty source or unsupported host | Matching stable code; no runner called. |
| Existing same-candidate receipt | `duplicate_candidate_receipt`; no runner called. |
| First, middle, or last suite failure | Eight receipt slots remain present; overall failed. |
| Exception before suite iteration | Atomic failed receipt with `validation_harness_failed`. |
| Source changes during synthetic iteration | Failed receipt with `source_fingerprint_drift`. |
| Receipt replacement fails | No partial file; bounded `receipt_write_failed` envelope. |

## 9. Historical Final Validation Playbook

Node `c5bfe53f-4094-4771-b323-12a99750c95b` was validation-only and used this procedure:

1. Require explicit user authorization for the final run.
2. Confirm every implementation prerequisite is completed and no source-writing task is active.
3. Require a committed candidate and a clean source tree.
4. Run `--plan-only` and `--preflight`; these do not consume the full-run authority.
5. If a receipt already exists for the same commit and source fingerprint, inspect it and do not
   rerun.
6. Freeze final acceptance through the lifecycle.
7. Trigger the declared full command exactly once through
   `advance ... --event regression-requested`; never run it manually in parallel.
8. Inspect `artifacts/validation/vityo-full.json`. All eight requirements must be present in canonical
   order and passed for acceptance.
9. On failure, preserve the receipt, do not rerun the unchanged fingerprint, and route only the
   failed requirement seams to a repair Node.
10. After a repair changes the source fingerprint, re-freeze acceptance before one run of the new
    candidate.

## 10. Required Leaf Handoff

Every designer, executor, or auditor response must be short and use this exact evidence order:

1. Node UUID and role.
2. One-sentence closure.
3. Repository-relative paths changed, removed, or inspected.
4. Acceptance criteria `0..n`, each marked `PASS`, `FAIL`, or `BLOCKED` with one evidence pointer.
5. Declared commands and exit codes; state explicitly that `ide/full` was not run for an
   implementation Node.
6. One-time scan results, when the Node requires them.
7. Out-of-scope findings, without implementing them.
8. Final lifecycle recommendation: advance, same-Node correction, design revision, blocked, or
   deferred.

Missing evidence is `BLOCKED`, never an implied pass. The native main rejects a handoff that omits a
criterion, widens scope, cites an undeclared full run, or reports only a narrative conclusion.

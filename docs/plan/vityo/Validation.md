# Vityo — Validation

**Plan:** `vityo`
**Purpose:** Map Styio Agent-Native IDE requirements to focused evidence and one final full regression.
**Last updated:** 2026-07-30

## Validation runner contract

The atomic cutover creates `scripts/vityo_quality.py`, a cross-platform runner that invokes commands
from each package's own working directory and records command, exit code, duration, platform, commit,
and artifact paths. It must not turn a missing tool/fixture/platform into success.

Focused suites run inside their owning lifecycle. The platform-independent `ide/full` suite runs
exactly once after every IDE implementation lifecycle closes; it neither aggregates native package
artifacts nor re-executes the companion Coding Agent track's full suite.

Execution follows [the Better Plan execution runbook](../EXECUTION-RUNBOOK.md). No agent may invoke
`ide/full` merely because the final Node is eligible.

## Requirement matrix

| Requirement | Focused proof | Product proof |
|---|---|---|
| REQ-IDE-001 | `python scripts/vityo_quality.py --product ide --suite cutover` and `python scripts/check_product_line_boundaries.py` | Both final packages analyze/smoke; old active roots/imports are absent; IDE starts with Agent disabled |
| REQ-IDE-002 | `--suite workspace-transactions` | Open/edit/save/search plus stale Agent change-set conflict and rollback |
| REQ-IDE-003 | `--suite developer-loop` | A real fixture completes `edit -> analyze -> test -> run -> observe` on one revision with truthful receipts and explicit unavailable states |
| REQ-IDE-004 | `--suite agent-workbench` | Two fake sessions stream concurrently; plan, approval, steering, cancellation, diff review, transaction result, and verification receipt are correctly routed |
| REQ-IDE-005 | `--suite agent-client-protocol` | Fake-Agent conformance, version failure, reconnect, and process shutdown; real integration is also covered by the companion-runtime track |
| REQ-IDE-006 | `--suite mcp-host` | Dynamic tools/resources/roots, root change/revocation, path denial, bounded context export |
| REQ-IDE-007 | `--suite ide-security` | Risk classification, grant scope/expiry, redaction, denial, cancellation, audit receipt, secret audience binding |
| REQ-IDE-008 | `--suite ide-quality` | Performance/accessibility/crash isolation plus packaging contracts and independent release-lane definitions |

## Focused closure rules

1. Run the smallest named suite after the implementation.
2. Analyze the affected package and shared protocol package when their public contract changes.
3. Record an acceptance receipt in the lifecycle; do not run `ide/full`.
4. If a focused failure comes from the current lifecycle, repair it in the same lifecycle.
5. If it reveals a defect in an already closed lifecycle, regress that lifecycle rather than creating
   a compatibility patch.

## Remaining focused validation

### Protocol-only Agent convergence

Node `014e7fb0-3f51-4033-be71-eca130a4a2ea` proves:

1. Vityo production code no longer constructs or owns model-provider transport, provider
   credentials/routes, coding loops, Agent tool-loop policy, durable Agent sessions, or multi-Agent
   scheduling.
2. App composition and Agent Workbench consume protocol client/session projections only.
3. Two concurrent sessions, permission routing, revision-bound proposals, IDE transactions, and
   receipts remain correct.
4. Vityo remains fully usable with no Agent connected.
5. Removed symbols, exports, provider-profile UI, behavior-bearing metadata, and compatibility tests
   are deleted in the same closure.

### Final-harness readiness

Node `63016713-c527-4428-a87d-2613f8c43ac9` may run plan-only, preflight, unit, and synthetic receipt
tests. It must never run the real full suite. It proves:

1. `ide/full --preflight` is side-effect free and checks every prerequisite needed before suite
   execution.
2. The runner has no machine-specific or sibling-checkout Better Plan path.
3. Every harness/suite/fingerprint failure writes a bounded receipt without raw exceptions.
4. The receipt binds the executed acceptance fixtures and protocol schema inputs.

#### Acceptance freeze mapping (criteria 0..3)

Executable oracles live in `tests/acceptance/vityo_app/full_runner_acceptance_test.py` plus injectable
unit seams in `tests/test_vityo_quality.py` and `tests/test_vityo_validation_receipt.py`. Matrix detail
is owned by [EXECUTION-RUNBOOK §8.3](../EXECUTION-RUNBOOK.md).

| Criterion | Observation | Executable case | Oracle |
|---|---|---|---|
| 0 | success, boundary | `--plan-only` / `--preflight` CLI | `mode` set; REQ-IDE-001..008 once; eight unique suites; default receipt unchanged; runners untouched |
| 1 | success, negative, fingerprint | synthetic `build_ide_receipt` / formal full with injected runners | eight slots; `protocol_schema_sha256` + `acceptance_fixtures_sha256`; stable `failure_code`; atomic write; no raw exception text |
| 2 | privacy, boundary | static scan of `scripts/vityo_quality.py` | no sibling/home Better Plan path; `_run_plan_validation` absent; `ide_full` never invokes lifecycle tools |
| 3 | replay | declared focused commands only | unit + acceptance + plan-only + preflight; bare `ide/full` never spawned |

Declared focused regression (never bare `ide/full`):

```text
python3 -m unittest tests.test_vityo_quality tests.test_vityo_validation_receipt
python3 tests/acceptance/vityo_app/full_runner_acceptance_test.py
python3 scripts/vityo_quality.py --product ide --suite full --plan-only
python3 scripts/vityo_quality.py --product ide --suite full --preflight
```

## One-time cutover checks

The cutover suite performs the removal proof once:

- no tracked active source/script/packaging import references `frontend/vityo_app` or
  `package:vityo_app`;
- no duplicate `agent`, `view_ide/agent`, or `view_render/agent` implementation root remains;
- product-line boundary analysis resolves imports, exports, package dependencies, generated code, and
  test-only imports;
- target packages and protocol schemas compile before the old root is removed from the commit;
- active README/product metadata/packaging use Vityo as the sole product identity and identify Vityo
  Coding Agent as the first-party companion runtime.

These removal checks are not retained as long-term compatibility gates. The permanent boundary gate
only validates the final roots and forbidden dependency directions.

## Independent platform release validation

Windows, macOS, and Linux are separate release lanes. Each lane runs only on its matching host and
builds, packages, installs, launches, workspace-smokes, and publishes only that platform's artifact.
Its receipt is bound to the lane's own commit and source fingerprint. A missing host tool, failed
smoke, or unavailable runner blocks only that platform release; no cross-platform collector or
shared native-package gate exists.

## Final validation

### Preconditions

All checks below are mandatory. A failure stops before the full command:

1. Better Plan status shows no `in_progress`, `blocked`, or `deferred` Vityo implementation Node.
2. Nodes `014e7fb0-3f51-4033-be71-eca130a4a2ea` and
   `63016713-c527-4428-a87d-2613f8c43ac9` are `completed`.
3. The candidate is committed and source-bearing paths are clean.
4. `python scripts/vityo_quality.py --product ide --suite full --plan-only` lists each
   `REQ-IDE-001` through `REQ-IDE-008` exactly once.
5. `python scripts/vityo_quality.py --product ide --suite full --preflight` passes without running a
   suite or writing the final receipt.
6. `artifacts/validation/vityo-full.json` does not already contain a receipt for the same commit and
   source fingerprint.
7. The current user has explicitly authorized the final full run.

### Lifecycle action

Do not run the full command manually. Freeze the final Node's acceptance contract and invoke its
`regression-requested` lifecycle event exactly once for the immutable candidate. The declared
command is:

```text
python scripts/vityo_quality.py --product ide --suite full --receipt artifacts/validation/vityo-full.json
```

The full suite must include:

- format/analyze and all IDE unit/widget/integration tests;
- protocol consumer and fake-Agent conformance;
- standalone-without-Agent smoke completing edit, analyze, test, run, and observe;
- real developer-loop fixture with revision-bound receipts;
- two-session collaboration and crash/reconnect isolation;
- Agent plan, permission, change preview, IDE transaction, and verification-receipt projection;
- MCP root/revocation and security tests;
- performance, memory, accessibility, and recovery budgets;
- packaging contract and independent release-lane definition checks;
- Better Plan validation and requirement-label traceability.

### Receipt checks

The final receipt must contain:

1. schema version, product `vityo`, suite `full`, and overall status;
2. exact commit, supported host classification, and one source fingerprint;
3. protocol-schema and acceptance-fixture digests;
4. exactly one canonical outcome for each `REQ-IDE-001` through `REQ-IDE-008`;
5. the named suite and bounded duration for each outcome;
6. no native package artifact, secret, personal path, machine identity, or raw runtime log.

Every requirement outcome must be `passed`. A missing Agent fixture or required
platform-independent tool is a blocked/failing result, not a skip reported as success.

### Failure routing and rerun rule

1. Preserve every failed receipt.
2. Do not rerun an unchanged commit/source fingerprint.
3. Map failed requirement labels to their owning production seams and create or select one bounded
   repair lifecycle.
4. Use focused tests inside the repair; never run `ide/full` there.
5. After a repair changes the source fingerprint, re-freeze final acceptance before one run of the
   new candidate.
6. Better Plan validation and requirement-label checking run after evidence is recorded; they do not
   substitute for product outcomes.

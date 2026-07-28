# Vityo — Validation

**Plan:** `vityo`
**Purpose:** Map IDE requirements to focused evidence and one final full regression.
**Last updated:** 2026-07-26

## Validation runner contract

The atomic cutover creates `scripts/vityo_quality.py`, a cross-platform runner that invokes commands
from each package's own working directory and records command, exit code, duration, platform, commit,
and artifact paths. It must not turn a missing tool/fixture/platform into success.

Focused suites run inside their owning lifecycle. The platform-independent `ide/full` suite runs
exactly once after every IDE implementation lifecycle closes; it neither aggregates native package
artifacts nor re-executes Coding Agent's full suite.

## Requirement matrix

| Requirement | Focused proof | Product proof |
|---|---|---|
| REQ-IDE-001 | `python scripts/vityo_quality.py --product ide --suite cutover` and `python scripts/check_product_line_boundaries.py` | Both final packages analyze/smoke; old active roots/imports are absent; IDE starts with Agent disabled |
| REQ-IDE-002 | `--suite workspace-transactions` | Open/edit/save/search plus stale Agent change-set conflict and rollback |
| REQ-IDE-003 | `--suite developer-loop` | Real fixture emits truthful analyze/test/run receipts and explicit unavailable states |
| REQ-IDE-004 | `--suite agent-workbench` | Two fake sessions stream concurrently; approval, steering, cancellation, diff review are correctly routed |
| REQ-IDE-005 | `--suite agent-client-protocol` | Fake-Agent conformance, version failure, reconnect, process shutdown; real integration is also covered by the Agent line |
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

## One-time cutover checks

The cutover suite performs the removal proof once:

- no tracked active source/script/packaging import references `frontend/vityo_app` or
  `package:vityo_app`;
- no duplicate `agent`, `view_ide/agent`, or `view_render/agent` implementation root remains;
- product-line boundary analysis resolves imports, exports, package dependencies, generated code, and
  test-only imports;
- target packages and protocol schemas compile before the old root is removed from the commit;
- active README/product metadata/packaging use Vityo and Coding Agent naming.

These removal checks are not retained as long-term compatibility gates. The permanent boundary gate
only validates the final roots and forbidden dependency directions.

## Independent platform release validation

Windows, macOS, and Linux are separate release lanes. Each lane runs only on its matching host and
builds, packages, installs, launches, workspace-smokes, and publishes only that platform's artifact.
Its receipt is bound to the lane's own commit and source fingerprint. A missing host tool, failed
smoke, or unavailable runner blocks only that platform release; no cross-platform collector or
shared native-package gate exists.

## Final validation

Run once on one head commit:

```text
python scripts/vityo_quality.py --product ide --suite full
```

The full suite must include:

- format/analyze and all IDE unit/widget/integration tests;
- protocol consumer and fake-Agent conformance;
- standalone-without-Agent smoke;
- real developer-loop fixture;
- two-session collaboration and crash/reconnect isolation;
- MCP root/revocation and security tests;
- performance, memory, accessibility, and recovery budgets;
- packaging contract and independent release-lane definition checks;
- Better Plan validation and requirement-label traceability.

Final evidence records one outcome per `REQ-IDE-*` label and contains no native package evidence. A
missing Agent fixture or required platform-independent tool is a blocked/failing result, not a skip
reported as success.

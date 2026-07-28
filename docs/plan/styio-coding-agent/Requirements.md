# Styio Coding Agent — Requirements

**Plan:** `styio-coding-agent`
**Purpose:** Define an independent, secure, model-neutral Coding Agent runtime.
**Last updated:** 2026-07-26

## Product definition

Styio Coding Agent is a standalone coding runtime. It accepts a user goal, gathers bounded evidence
through a host, plans work, invokes approved tools, proposes reviewable changes, validates them, and
reports durable receipts. It can be launched by Styio IDE or another compatible client and can run
headlessly against a controlled filesystem/worktree host.

The Agent owns reasoning and execution orchestration. It does not own an editor buffer, Flutter UI,
or unchecked access to the user's machine.

## Functional requirements

- **REQ-AGENT-001 — Standalone runtime and product boundary.**
  The runtime lives under `products/styio_coding_agent`, has a headless executable and pure Dart
  library, and imports neither Styio IDE nor Flutter. It runs a complete fake-host session even when
  Styio IDE is absent.
  *Acceptance:* dependency inspection, analyze/test, and a CLI smoke scenario prove independent
  startup, cancellation, completion, and exit codes.

- **REQ-AGENT-002 — Model- and provider-neutral execution.**
  A provider port supports capability discovery, structured messages, streamed output/tool calls,
  cancellation, timeouts, retry classification, context/output budgets, and usage receipts. Routing
  never assumes one vendor's request shape, and provider fallback never replays a mutating action
  without an idempotency decision.
  *Acceptance:* deterministic fake-provider suites cover stream fragmentation, rate limits, auth
  failures, cancellation, budget exhaustion, safe retry, and provider failover.

- **REQ-AGENT-003 — Revisioned context engine.**
  Context selection combines explicit user attachments, host facts, workspace search, diagnostics,
  symbols, changed files, and prior session evidence. Every item carries source, revision,
  sensitivity, score, and truncation metadata. Incremental indexes and bounded caches prevent
  whole-workspace rescans and unbounded prompt growth.
  *Acceptance:* relevance fixtures, stale-revision tests, redaction checks, deterministic compaction,
  cache invalidation, and memory budgets pass.

- **REQ-AGENT-004 — Schema-first tool and MCP runtime.**
  Built-in and MCP tools share a versioned schema registry, result limits, cancellation, dynamic
  discovery, and typed failure taxonomy. Tool availability can change during a session. Only
  task-relevant tools are presented to a model, and tool outputs remain untrusted evidence until
  validated.
  *Acceptance:* schema/conformance tests cover discovery changes, malformed input/output, oversized
  results, timeouts, cancellation, and server loss without corrupting the session.

- **REQ-AGENT-005 — Enforceable permissions and execution policy.**
  The Agent classifies read, write, process, network, credential, destructive, and open-world actions;
  requests permission through the host; applies path/root, environment, network, and secret policies
  at execution time; and records redacted audit receipts. Hooks can approve, deny, transform, or scan
  requests/results. Model text can never self-authorize a tool.
  *Acceptance:* traversal, symlink escape, secret exfiltration, token passthrough, network deny,
  policy revocation, destructive action, and hook-failure tests all fail closed.

- **REQ-AGENT-006 — Evidence-driven coding loop.**
  The runtime executes a bounded understand–plan–act–observe–verify–repair loop. Plans contain
  independently acceptable steps and explicit acceptance criteria. Edits are proposed as revisioned
  change sets through host transactions; diagnostics/tests are re-read after edits; repeated failures
  trip loop guards and surface a blocker instead of continuing indefinitely.
  *Acceptance:* representative bug-fix and refactor fixtures produce reviewable changes, focused
  validation receipts, bounded repair attempts, and no direct file mutation through the IDE host.

- **REQ-AGENT-007 — Durable sessions, recovery, and observability.**
  Append-only session events and compact projections preserve goals, turns, plans, tool calls,
  permissions, changes, validations, budgets, and terminal outcomes. A crash can resume from the last
  committed boundary without replaying an already committed mutation. Logs and user-visible receipts
  are correlated and redacted.
  *Acceptance:* kill/restart and corrupted-tail fixtures recover deterministically, preserve audit
  history, and do not duplicate tool effects.

- **REQ-AGENT-008 — Multi-agent and worktree-safe coordination.**
  A coordinator may delegate scoped tasks to role-specific Agents with isolated context, tools,
  budgets, and worktrees. A dependency DAG, ready queue, concurrency limit, and resource lease
  registry prevent two workers from mutating the same ownership scope. Integration is always a
  reviewed merge/change-set step.
  *Acceptance:* parallel fixtures prove independent progress, bounded scheduling, collision
  prevention, cancellation propagation, deterministic result collection, and conflict review.

- **REQ-AGENT-009 — Protocol interoperability and release evidence.**
  Styio Coding Agent implements the compatible Agent-side session boundary, negotiates capabilities,
  serves concurrent sessions, and interoperates with Styio IDE without private object sharing.
  Conformance, security, task-quality, latency, memory, and cancellation evaluations run in a
  reproducible release suite.
  *Acceptance:* the real IDE/Agent integration fixture and the Coding Agent full suite pass once on
  one head commit; unsupported capabilities or versions fail closed.

## Invariants

1. No Flutter or Styio IDE implementation import exists in the Coding Agent package.
2. All external effects pass through typed host/tool ports and policy enforcement.
3. The model is untrusted input: it cannot widen roots, tools, credentials, network, or permissions.
4. Session and tool histories are bounded in memory and durable through append-only receipts.
5. Mutations use idempotency keys and explicit commit boundaries.
6. Parallel workers use isolated worktrees/contexts and explicit resource ownership.
7. Provider, MCP, and host failures preserve a truthful terminal or recoverable state.

## Scope

Coding Agent runtime/library/CLI, provider ports, context selection, tool/MCP runtime, policy and
hooks, coding-loop orchestration, durable session store, multi-agent scheduler, protocol adapter,
tests, benchmarks, and release evaluation fixtures.

## Non-goals

- Owning Styio IDE widgets, workbench navigation, editor buffers, or desktop packaging.
- Unrestricted shell/network access by default.
- Training or hosting foundation models.
- Replacing compiler/language-service facts with model guesses.
- Silently auto-merging worktree changes or publishing commits/PRs.
- Maintaining the old in-process Vityo Agent API as a compatibility layer.

## Final acceptance

On one head commit, the standalone Agent solves the reference coding fixtures, survives cancellation
and restart, enforces roots/permissions/secrets, coordinates an isolated parallel task, and completes
a reviewed session through Styio IDE while passing its one full regression and release evaluation.

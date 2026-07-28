# Vityo — Requirements

**Plan:** `vityo`
**Purpose:** Define Vityo as an independent developer environment and AI-native Agent Client.
**Last updated:** 2026-07-26

## Product definition

Vityo is the user-facing editor and workbench. It owns source buffers, workspace revisions,
language and execution facts, reviewable workspace transactions, development surfaces, and the
client side of Agent collaboration. It remains useful when no Coding Agent is installed.

AI-native means the IDE can host several long-running Agent sessions as first-class workbench tasks:
users can see plans and tool activity, steer or cancel work, answer permission requests, review every
change set, and attach either Vityo Coding Agent or another compatible Agent. It does not mean adding
another chat tab to a monolithic application.

## Functional requirements

- **REQ-IDE-001 — Product identity and hard repository boundary.**
  The current monolithic application is atomically cut over to `products/vityo_app`,
  `products/vityo_coding_agent`, and the Vityo-owned shared `packages/vityo_agent_protocol`. Active product
  metadata uses Vityo and Coding Agent naming. The old application root, duplicate agent roots,
  one-line compatibility exports, and obsolete gate exceptions are removed in the same closure.
  *Acceptance:* both products analyze and smoke-test from their final roots; the boundary gate proves
  the forbidden dependency directions and a one-time removal check finds no active old import/path.

- **REQ-IDE-002 — Independent IDE and authoritative workspace transactions.**
  Vityo launches, opens a workspace, edits, saves, searches, and reviews changes without an Agent
  process. Source buffers and monotonically increasing document/workspace revisions are authoritative.
  Agent-proposed edits can only enter through previewable, conflict-detecting workspace transactions
  bound to the revision from which they were produced.
  *Acceptance:* standalone IDE and stale-edit integration tests prove that direct Agent file mutation,
  stale edit application, and visual substitution cannot bypass the transaction owner.

- **REQ-IDE-003 — Truthful developer loop and structured IDE facts.**
  Language intelligence, diagnostics, formatting, build, run, test, debug, source control, terminal,
  toolchain, and package workflows expose typed facts and receipts. An unavailable or heuristic
  capability remains visibly degraded or blocked; no surface invents success. Agent consumers receive
  the same revision-bound facts as the user-facing surfaces.
  *Acceptance:* a representative local project completes edit–save–analyze–test–run with structured
  receipts, while unavailable routes produce tested capability-gap states.

- **REQ-IDE-004 — AI-native collaboration workbench.**
  The workbench provides a task/thread list, multiple concurrent sessions, streaming turns, plan and
  step state, tool-call timeline, artifacts, diagnostics, proposed diffs, validation receipts, and
  explicit steer/cancel/retry controls. Permission requests and change review stay visible even when
  the panel is not focused.
  *Acceptance:* widget/integration tests run two fake sessions concurrently, preserve independent
  timelines, route approvals to the correct session, and complete a reviewed change without hidden
  mutation.

- **REQ-IDE-005 — Open Agent Client protocol.**
  Vityo discovers, launches, reconnects to, and terminates Agent processes through an
  ACP-compatible, version-negotiated JSON-RPC session boundary. The boundary supports streamed
  notifications, concurrent sessions, bidirectional requests, cancellation, permission prompts,
  terminal output, artifacts, and capability changes. Styio-specific additions use namespaced,
  negotiated extensions rather than forking standard messages.
  *Acceptance:* protocol conformance and process-lifecycle tests pass against a fake Agent and Styio
  Coding Agent; an unsupported protocol version fails closed with a useful diagnostic.

- **REQ-IDE-006 — Context, tools, and extension export.**
  Deep editor operations are exposed as narrow IDE-owned tools. External tools, resources, prompts,
  and workspace roots are exposed through MCP-compatible servers with dynamic discovery. Roots are
  explicit, user-consented, path-validated, and updateable; context export carries revision,
  provenance, sensitivity, and truncation metadata.
  *Acceptance:* a fake external Agent discovers a root-limited tool/resource set, reacts to root
  changes, and cannot access an unapproved path or a removed capability.

- **REQ-IDE-007 — Human control and security boundaries.**
  Read-only annotations inform policy but never substitute for enforcement. Mutating, network,
  credential, destructive, and open-world actions are independently classified; approval can be
  scoped to once, session, workspace, or policy. Secrets are resolved only at the execution boundary,
  redacted from UI/log/protocol payloads, and never passed through to an unintended audience.
  *Acceptance:* permission, root traversal, secret redaction, cancellation, and audit-receipt tests
  pass, including denial after a previously granted capability is revoked.

- **REQ-IDE-008 — Product quality and desktop delivery.**
  Vityo meets bounded event/context memory budgets, responsive rendering, keyboard and screen
  reader requirements, crash recovery, and truthful Windows/macOS/Linux packaging. IDE and Agent
  failures are isolated so one terminated session cannot take down the editor or another session.
  *Acceptance:* the platform-independent full IDE suite, performance budgets, accessibility checks,
  and crash/reconnect scenarios pass without consuming native package artifacts. Before a platform
  release is published, that platform's package is built, installed, launched, and workspace-smoked
  on its matching host. Each release receipt binds only its own artifact, commit, and source
  fingerprint; Windows, macOS, and Linux release lanes do not block one another.

## Invariants

1. `products/vityo_app` does not import `products/vityo_coding_agent`.
2. Integration is protocol/process based; no shared mutable session objects cross the line.
3. `packages/vityo_agent_protocol` is pure, versioned, presentation-free, and contains no product
   orchestration.
4. IDE workspace revisions and transactions are the authority for edits made through the IDE.
5. Streams, event histories, and context snapshots are bounded and expose dropped/truncated counts.
6. Missing capabilities are explicit states, not placeholders or simulated success.
7. The cutover removes old implementations and compatibility facades; it does not preserve them as a
   long-term migration layer.

## Scope

Vityo application/runtime code, IDE-facing protocol client and MCP host, desktop packaging,
repository gates needed for the new roots, IDE tests/benchmarks, and current product documentation.

## Non-goals

- Implementing model inference, prompt orchestration, Agent tool loops, or multi-agent scheduling.
- Reimplementing Styio compiler truth inside the IDE.
- Building a hosted control plane in this repository.
- Preserving Vityo import paths, source roots, or compatibility facades after cutover.
- Making every extension an Agent or every IDE command externally callable.

## Final acceptance

On one head commit, Vityo operates without an Agent, collaborates with Vityo Coding Agent through
the versioned boundary, hosts two concurrent sessions safely, completes a reviewed coding change, and
passes its platform-independent full regression without importing Agent runtime code. Each desktop
platform is released independently only after its matching-host delivery checks pass.

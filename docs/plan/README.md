# Vityo — Better Plan Workspace

**Purpose:** Coordinate two independently acceptable delivery tracks for one Vityo product.
**Last updated:** 2026-07-30

`docs/plan` is the only current Better Plan root. **Vityo is the agent-native IDE for Styio** and
the sole product identity. The workspace has exactly two delivery tracks:

- `vityo`: the IDE, workbench, developer services, Agent Client, collaboration surfaces, and
  desktop product.
- `vityo-coding-agent`: the independently executable first-party companion runtime, including
  providers, context engine, tools, policy, orchestration, sessions, and multi-Agent execution.

The code target has two implementation roots and one shared contract:

```text
products/vityo_app/
products/vityo_coding_agent/
packages/vityo_agent_protocol/   # Vityo-owned shared wire contract; not a product
```

`products/vityo_app` must never import Coding Agent runtime code.
`products/vityo_coding_agent` must never import Vityo or Flutter code. Both may depend on the
pure, versioned protocol package. IDE-to-Agent integration happens through the process/protocol
boundary, not shared mutable objects.

The first IDE lifecycle was the only cross-track implementation exception: it performed one atomic
repository cutover from the monolithic package to the two roots, created the Vityo-owned shared
protocol package, updated repository tooling, and removed old source roots and compatibility
exports in the same closure. After that barrier, an implementation lifecycle owns one delivery
track only; cross-track changes are limited to versioned protocol contracts and integration
fixtures.

Execution authority comes only from workspace-wide `prerequisites`. Prose, directory order,
`status_reason`, and `next` are explanatory. Every implementation lifecycle has a design contract and
focused regression. Each delivery track has exactly one full final regression after all of its
implementation lifecycles close. Ordinary defects stay in their owning lifecycle; removed source
trees are verified once during the atomic cutover and are not kept as permanent compatibility gates.

Planning requests update these artifacts only. They do not select or dispatch implementation work.
Validate the workspace with the current Better Plan manifest validator and label checker.

## Execution Contract

[EXECUTION-RUNBOOK.md](./EXECUTION-RUNBOOK.md) is the mandatory operating procedure for every future
Node. It defines exact role transitions, evidence rules, failure routing, the remaining Node order,
and the special one-run semantics of final validation.

Current planning state is intentionally explicit:

1. completed Nodes are historical evidence and must not be replayed;
2. the IDE-owned provider/coding-loop surface must be removed before product validation;
3. the final harness must pass side-effect-free readiness checks before the one-time full run;
4. only then may the final-validation Node execute.

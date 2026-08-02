# Vityo — Better Plan Workspace

**Purpose:** Coordinate two independently acceptable delivery tracks for one Vityo product.
**Last updated:** 2026-08-01

`docs/plan` is the repository's only authoritative Better Plan workspace and the only permitted
Better Plan root. Nested or parallel planning workspaces are forbidden. The retired nested
workspace has been consolidated into this root's capability catalog, historical task groups,
and their requirements, architecture, validation, and evidence projections.

**Vityo is the agent-native IDE for Styio** and the sole product identity. The workspace has exactly
two delivery tracks:

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

`Capabilities.json` is the durable repository-capability catalog. It records the observed Vityo
foundation, the two delivery modules, progressively disclosed IDE capabilities, and the known
shared protocol interface separately from historical delivery state. `Manifest.json` binds each completed task group to its stable
capability key; their `Checkpoints.json` files preserve immutable Node histories.

Planning requests update these artifacts only. They do not select or dispatch implementation work.
Validate the workspace with the current Better Plan manifest validator and label checker.

## Execution Contract

[EXECUTION-RUNBOOK.md](./EXECUTION-RUNBOOK.md) is the mandatory operating procedure for every future
task group. It defines the current Designer, Worker, Verifier, and Reviewer transitions, evidence
rules, failure routing, and full-regression boundary.

Current planning state is intentionally explicit:

1. all recorded task groups and delivery Nodes are completed historical evidence;
2. no current Node is eligible or authorized for replay;
3. later delivery must use a distinct, capability-bound task group with one `group_design`, one or
   more `implementation`, and one trailing `final_validation` Node;
4. a planning request may update Plan state but never authorizes implementation or regression.

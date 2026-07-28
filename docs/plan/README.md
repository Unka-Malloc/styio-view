# Styio IDE and Coding Agent — Better Plan Workspace

**Purpose:** Keep the repository's two product lines explicit, independently acceptable, and safe to
execute in parallel.
**Last updated:** 2026-07-26

`docs/plan` is the only current Better Plan root. The product is now **Styio IDE and Coding Agent**,
with exactly two delivery plans:

- `styio-ide`: the IDE, workbench, developer services, Agent Client, collaboration surfaces, and
  desktop product.
- `styio-coding-agent`: the standalone Coding Agent runtime, providers, context engine, tools,
  policy, orchestration, sessions, and multi-agent execution.

The code target has the same two business-line roots:

```text
products/styio_ide/
products/styio_coding_agent/
packages/styio_agent_protocol/   # neutral wire contract; not a third product line
```

`products/styio_ide` must never import Coding Agent runtime code.
`products/styio_coding_agent` must never import Styio IDE or Flutter code. Both may depend on the
pure, versioned protocol package. IDE-to-Agent integration happens through the process/protocol
boundary, not shared mutable objects.

The first IDE lifecycle is the only cross-line implementation exception: it performs one atomic
repository cutover from the current monolithic package to the two roots, creates the neutral protocol
package, updates repository tooling, and removes all old source roots and compatibility exports in the
same closure. After that barrier, an implementation lifecycle owns one product line only; cross-line
changes are limited to versioned protocol contracts and integration fixtures.

Execution authority comes only from workspace-wide `prerequisites`. Prose, directory order,
`status_reason`, and `next` are explanatory. Every implementation lifecycle has a design contract and
focused regression. Each product line has exactly one full final regression after all of its
implementation lifecycles close. Ordinary defects stay in their owning lifecycle; removed source
trees are verified once during the atomic cutover and are not kept as permanent compatibility gates.

Planning requests update these artifacts only. They do not select or dispatch implementation work.
Validate the workspace with the current Better Plan manifest validator and label checker.

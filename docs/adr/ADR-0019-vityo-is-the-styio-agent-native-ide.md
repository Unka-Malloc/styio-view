# ADR-0019: Vityo Is the Styio Agent-Native IDE

**Purpose:** Freeze Vityo's product category, product hierarchy, and protocol-only Agent ownership boundary.

**Last updated:** 2026-07-30

**Status:** Accepted

**Date:** 2026-07-30

## Context

Vityo was previously described through several overlapping frames: a dedicated editor and runtime
window, an IDE with a first-class AI panel, an IDE that directly mounted model providers, and one of
two parallel products beside Vityo Coding Agent.

The repository has since established three hard implementation roots:

1. `products/vityo_app` for the user-facing IDE;
2. `products/vityo_coding_agent` for an independently executable Agent runtime;
3. `packages/vityo_agent_protocol` for their pure, versioned wire contract.

The older positioning no longer explains this boundary. In particular, an IDE-owned
OpenAI-compatible provider path makes the IDE responsible for model routing and coding-loop
orchestration that the companion runtime now owns. Calling the IDE and companion two public products
also conflicts with Vityo's sole product identity.

The product needs one category, one hierarchy, and one launch promise that remain truthful with or
without an Agent.

## Decision

1. **Vityo is the agent-native IDE for Styio.**
2. Vityo is the sole user-facing product and repository identity.
3. Vityo Coding Agent is the first-party, independently executable companion Agent runtime. It may
   be launched by Vityo or another compatible client; it is not a second Vityo product identity.
4. The Vityo Agent Protocol is a shared contract, not a third product.
5. Vityo is an open Agent Client: it may connect to Vityo Coding Agent or another compatible Agent
   through a versioned, capability-negotiated process/protocol boundary.
6. The IDE does not connect directly to model providers. Model/provider routing, context selection,
   tool loops, effect policy, durable Agent sessions, coding orchestration, and multi-Agent
   scheduling belong to Agent runtimes.
7. The IDE owns Source Buffers, revisions, Styio language/compiler/runtime facts, permission
   presentation, change review, and workspace transaction commits.
8. Agent-originated changes are revision-bound proposals. They cannot bypass IDE review or mutate
   IDE-owned files directly.
9. Vityo remains a complete Styio IDE when no Agent is installed or connected.
10. The launch positioning requires both a trustworthy
    `edit -> analyze -> test -> run -> observe` loop and a reviewable Agent loop with visible plans,
    permissions, changes, and validation receipts.
11. `Agent Workbench` is the product capability. `Agent Panel` may name one concrete UI surface but
    does not define product scope or runtime ownership.
12. The two Better Plan directories remain independent engineering delivery tracks. They must not
    be described as two public products.

## Consequences

1. Product, architecture, governance, release, and planning documents use the same product hierarchy
   and Agent ownership boundary.
2. The old embedded/panel-first Agent architecture is removed from the active design tree.
3. Existing IDE direct-provider/controller code is recorded as a migration gap. This ADR does not
   claim that code migration has already happened.
4. Vityo's public Agent protocol remains compatible with first-party and third-party Agents.
5. The completed Vityo Coding Agent plan and its evidence remain valid because the runtime stays
   independently executable and protocol-driven.
6. The IDE's no-Agent developer loop remains a release invariant.
7. Profile sync remains an optional, replaceable IDE service with a local-only fallback; it is not a
   model-provider route.

## Supersession

1. This decision fully supersedes
   [ADR-0006](./ADR-0006-ai-agent-panel-first-class-surface.md) as the active product positioning for
   Agent collaboration.
2. This decision supersedes the IDE-owned `AgentProviderAdapter` and direct
   OpenAI-compatible-provider portions of
   [ADR-0013](./ADR-0013-agent-and-profile-provider-adapters.md).
3. ADR-0013's `ProfileSyncAdapter` and local-only profile behavior remain active.
4. [ADR-0018](./ADR-0018-vityo-is-the-sole-product-identity.md) remains active and is clarified by
   the one-product hierarchy in this decision.

## Alternatives

1. **Keep direct provider calls in the IDE:** preserves the older implementation but duplicates
   Agent runtime ownership and weakens protocol isolation.
2. **Support only Vityo Coding Agent:** simplifies compatibility but closes the Agent Client boundary
   without a product need.
3. **Require an Agent for all IDE workflows:** makes the category narrower but violates the
   independent, trustworthy Styio developer loop.
4. **Market the IDE and Coding Agent as two products:** matches physical package separation but
   conflicts with the accepted Vityo identity model.

## Related Records

1. [Vityo Product Spec](../design/Vityo-Product-Spec.md)
2. [Vityo Agent-Native IDE Architecture](../design/Vityo-Agent-Native-IDE-Architecture.md)
3. [Vityo IDE Requirements](../plan/vityo/Requirements.md)
4. [Vityo Coding Agent Requirements](../plan/vityo-coding-agent/Requirements.md)
5. [Vityo Domain Glossary](../../CONTEXT.md)

# Vityo Coding Agent — Evidence

**Plan:** `vityo-coding-agent`
**Purpose:** Ground the sealed Coding Agent plan in current implementation evidence and first-party sources.
**Last updated:** 2026-08-01

## Current repository findings

| Finding | Repository evidence | Consequence |
|---|---|---|
| The runtime is an independent pure-Dart product. | `products/vityo_coding_agent/bin`, `lib`, `test`, `integration_test`, `benchmark`, and its own `pubspec.yaml` exist; the product boundary gate forbids Flutter and Vityo implementation imports. | The old in-process Agent implementation is historical only and must not return as a compatibility layer. |
| Runtime responsibilities have explicit owners. | `lib/src/providers`, `context`, `tools`, `policy`, `orchestration`, `sessions`, `multi_agent`, `protocol`, and `hosts` contain narrow runtime modules and ports. | Extend the owning module rather than recreating a monolithic session controller. |
| Headless and provider-neutral execution are testable. | `bin/vityo_coding_agent.dart`, `test/headless`, provider tests, and provider-stream benchmarks exercise runtime startup and bounded provider behavior without Flutter. | Deterministic local validation does not require live credentials. |
| Context, tools, and policy are bounded runtime seams. | Context-engine tests, MCP tool-source tests, tool-runtime tests, and policy-runtime tests cover revision-aware selection, schema validation, output bounds, roots, permissions, and denial behavior. | Models and tool metadata remain untrusted inputs; policy is enforced at the effect boundary. |
| Durable recovery is implemented through session stores. | `SessionEventStore`, `JournalSessionEventStore`, session recovery tests, and the recovery integration fixture preserve correlated append-only state and effect receipts. | New effects must retain idempotent commit boundaries and redacted evidence. |
| Multi-Agent execution has concrete isolation. | The worktree coordinator, resource-lease registry, unit tests, and `integration_test/multi_agent_worktree_test.dart` cover DAG scheduling, worktree lifecycle, ownership overlap, and cleanup. | Delegation remains resource-bounded and merge/review oriented. |
| The Agent-side protocol and release corpus are executable. | `AgentSessionEndpoint`, protocol integration tests, `release_evaluation.dart`, and the release-evaluation benchmark use the shared versioned protocol. | Protocol changes must remain negotiated and independently consumable by Vityo and compatible clients. |

## Official architecture research

| Source | First-party signal | Planning conclusion |
|---|---|---|
| [Agent Client Protocol architecture](https://agentclientprotocol.com/get-started/architecture) | Agent and client are separate peers; JSON-RPC supports streaming, permission requests, concurrent sessions, and MCP tool exposure. | The Agent runtime must not know IDE classes; it implements the Agent peer and consumes host capabilities. |
| [MCP specification overview](https://modelcontextprotocol.io/specification/2025-11-25/basic) | Typed schemas define messages for interoperable context and tools. | Use schema-first DTOs and conformance fixtures, not ad hoc maps embedded in provider prompts. |
| [MCP roots](https://modelcontextprotocol.io/specification/2025-06-18/client/roots) | Roots are explicit capabilities with consent and update notifications. | Context and tools must validate every path against current roots, including after revocation. |
| [GitHub custom Agents](https://docs.github.com/en/copilot/how-tos/copilot-sdk/features/custom-agents) | Scoped Agents can have independent prompts/tools/MCP servers; lifecycle events support delegated and parallel work. | Delegation needs isolated policy/context and observable lifecycle events. |
| [GitHub third-party coding Agents](https://docs.github.com/en/copilot/concepts/agents/about-third-party-coding-agents) | Coding Agents can execute asynchronously and remain subject to repository security scanning. | Durable asynchronous tasks and post-change validation/security evidence are product requirements. |
| [GitHub Copilot firewall](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-the-firewall) | Network allow/deny policy exposes blocked requests and treats unrestricted egress as an exfiltration risk. | Network access is a separately enforced tool capability with auditable denials. |
| [OpenAI model guidance](https://developers.openai.com/api/docs/guides/latest-model) | Tool sets should be task-relevant, prompts lean, and reusable prompt prefixes/cache boundaries stable. | Select a bounded tool/context subset per step instead of publishing every IDE operation on every turn. |
| [Zed native Agent](https://zed.dev/docs/ai/zed-agent) | Project, editor, terminal, review, permissions, MCP, profiles, skills, and instructions are separate capabilities around a session. | Decompose runtime ownership; do not rebuild another all-knowing session controller. |

## Resulting design decisions

1. Coding Agent is a pure runtime with host/provider/tool/policy ports and a headless executable.
2. The former monolithic context and controller were decomposed by state ownership, not wrapped.
3. Session events are append-only; compact projections and bounded caches serve hot reads.
4. Context selection is incremental, revision-keyed, scored, deduplicated, and budgeted.
5. Tool discovery is dynamic; policy is enforced outside model output.
6. Multi-agent scheduling uses a dependency DAG, ready queue, concurrency semaphore, and worktree
   resource leases.
7. IDE collaboration uses the shared protocol; headless mode substitutes a controlled host adapter.

## Delivery closure

All Coding Agent Nodes, including the immutable-source final validation, are completed. The
requirements, architecture, validation matrix, checkpoint receipts, and shared-protocol fingerprint
are sealed historical evidence. A later request must create a distinct capability-bound task group;
it must not reopen this plan or infer execution authority from the completed nodes.

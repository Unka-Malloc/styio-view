# Vityo Coding Agent — Evidence

**Plan:** `vityo-coding-agent`
**Purpose:** Ground the Coding Agent plan in current implementation evidence and first-party sources.
**Last updated:** 2026-07-26

## Current repository findings

| Finding | Repository evidence | Consequence |
|---|---|---|
| Agent runtime is an IDE subdirectory. | About 50 Dart files live in `frontend/vityo_app/lib/src/view_ide/agent`; another 28 files in `lib/src/agent` re-export them. | The Agent cannot be built, versioned, or tested as an independent product. |
| Core control state depends on Flutter. | `agent_coding_session_controller.dart` extends `ChangeNotifier` and imports Flutter foundation. | Headless execution still depends on an IDE/UI framework. |
| Context is coupled to concrete IDE modules. | `agent_session_context.dart` imports editor, workspace, language, debugger, testing, toolchain, command, foundation, and execution implementations. | Context collection is not a host port and cannot work with another client. |
| Three files concentrate most behavior. | The current context, provider adapter, and session controller files are roughly 7,600, 2,900, and 2,900 lines. | Provider, orchestration, context, policy, and persistence ownership are mixed, increasing repeated work and memory risk. |
| “Subagent” is presently a registry role. | `agent_registry.dart` exposes primary/subagent metadata, but no production worktree scheduler, resource leases, or parallel execution path is present. | Multi-agent collaboration must be implemented as execution, not naming. |
| Open protocol support is absent from production code. | Current Agent source has no MCP/ACP session implementation or workspace-root protocol. | External tools and IDE clients cannot interoperate through a standard boundary. |
| Useful foundations already exist. | Provider adapters/streaming/retry, tool schemas, permission models, patch preview/apply, snapshots, history, recovery structures, and roughly 68 Agent-prefixed tests exist. | Preserve validated behavior while decomposing it behind independent ports. |

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
2. The current monolithic context and controller are decomposed by state ownership, not wrapped.
3. Session events are append-only; compact projections and bounded caches serve hot reads.
4. Context selection is incremental, revision-keyed, scored, deduplicated, and budgeted.
5. Tool discovery is dynamic; policy is enforced outside model output.
6. Multi-agent scheduling uses a dependency DAG, ready queue, concurrency semaphore, and worktree
   resource leases.
7. IDE collaboration uses the shared protocol; headless mode substitutes a controlled host adapter.

## Evidence gaps to close during delivery

- No independent package/CLI smoke test exists.
- No provider-independent usage/budget contract exists across every path.
- No MCP conformance, roots, auth, or capability-revocation suite exists.
- No durable event-log crash recovery proves exactly-once mutation boundaries.
- No parallel worktree execution or resource-collision fixture exists.
- Current large controllers need one-time decomposition with old implementations deleted.

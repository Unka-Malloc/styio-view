# Vityo — Evidence

**Plan:** `vityo`
**Purpose:** Ground the IDE plan in current repository evidence and official first-party references.
**Last updated:** 2026-07-26

## Current repository findings

The counts below are a planning snapshot, not a permanent metric.

| Finding | Repository evidence | Consequence |
|---|---|---|
| One Flutter package owns both products. | `frontend/vityo_app/pubspec.yaml` and `lib/main.dart` are the only current application package/entrypoint. | IDE and Agent cannot be released, tested, or failed independently. |
| Layer separation is not product-line separation. | `lib/src/view_ide` contains about 557 Dart files, including about 50 Agent files; `lib/src/view_render/agent` owns Agent UI. | The current `view_ide` / `view_render` split is useful inside the IDE but cannot define the IDE / Coding Agent boundary. |
| Compatibility roots keep the old topology alive. | `lib/src/agent` contains 28 one-line exports; similar facades exist for editor, language, backend toolchain, and integration paths. | A second reorganization would otherwise add another compatibility layer and preserve ambiguity. |
| Composition knows concrete Agent runtime types. | `lib/src/app/app_bootstrap.dart` constructs provider, controller, tool, history, snapshot, and extension-tool objects; shell code invokes concrete Agent controllers. | The IDE is not an Agent Client; it is an in-process owner of the Agent runtime. |
| Existing IDE foundations are valuable. | Editor transactions, workspace stores, language/service boundaries, runtime events, debugger, SCM, terminal, module host, capability states, and hundreds of tests already exist. | The plan migrates and sharpens these capabilities rather than replacing the editor stack. |
| The current architecture policy explicitly permits legacy facades. | `docs/adr/ADR-0010-vityo-view-ide-view-render-boundary.md` and current gates describe incremental compatibility. | The new product split must supersede this policy with an atomic cutover and a new product-line gate. |

## Official architecture research

| Source | First-party signal | Planning conclusion |
|---|---|---|
| [VS Code AI extensibility overview](https://code.visualstudio.com/api/extension-guides/ai/ai-extensibility-overview) | Separates deep editor tools, reusable MCP tools, chat participants, and direct language-model features; Agent mode plans and invokes tools. | Vityo should expose narrow native IDE tools and reusable MCP tools as different surfaces, not one global command catalog. |
| [VS Code Language Model API](https://code.visualstudio.com/api/extension-guides/ai/language-model) | Models can be unavailable, and editor APIs are used to build task-specific context. | Model identity cannot be hard-wired into IDE state; context must be revisioned and capability-aware. |
| [VS Code MCP developer guide](https://code.visualstudio.com/api/extension-guides/ai/mcp) | Supports tools, prompts, resources, dynamic discovery, confirmations, roots, and multiple transports. | MCP is the external context/tool boundary; IDE-private operations remain IDE tools. |
| [Zed Agents](https://zed.dev/docs/ai/agents) and [External Agents](https://zed.dev/docs/ai/external-agents) | Native, ACP, and terminal Agent harnesses share a thread-oriented UX while an external Agent owns its runtime and authentication. | The workbench hosts sessions; it does not absorb every Agent implementation. |
| [Agent Client Protocol architecture](https://agentclientprotocol.com/get-started/architecture) | Defines a JSON-RPC Agent/client boundary with streaming notifications, bidirectional permission requests, concurrent sessions, and MCP exposure. | Use ACP-compatible session semantics and namespaced extensions instead of a private monolithic bridge. |
| [MCP roots](https://modelcontextprotocol.io/specification/2025-06-18/client/roots) | Roots require explicit consent, path validation, access controls, and change notification. | Workspace scope is a live security capability, not a path string copied into a prompt. |
| [MCP authorization](https://modelcontextprotocol.io/specification/2025-06-18/basic/authorization) | Requires audience-bound OAuth behavior, PKCE, secure storage, and forbids token passthrough. | IDE credentials must be resolved for the intended server/tool only and never forwarded through Agent payloads. |
| [GitHub Copilot hooks](https://docs.github.com/en/copilot/concepts/agents/hooks) | Session/tool hooks can approve, deny, scan, enforce policy, and create audit trails. | Permission UI needs an enforceable policy/hook layer and durable receipts, not a modal-only implementation. |

## Resulting design decisions

1. The IDE is a client/host. Coding Agent runtime crosses a process and protocol boundary.
2. The repository has two product roots and one Vityo-owned shared protocol package; there is no shared product
   implementation directory.
3. The current editor/workspace transaction model becomes the Agent edit authority.
4. Agent collaboration is a workbench task model with concurrent sessions, not a bottom-panel chat
   singleton.
5. ACP-compatible session semantics carry interaction; MCP carries reusable tools/resources/roots.
6. The one-time migration deletes old roots and updates current design/gates instead of adding new
   facades.

## Evidence gaps to close during delivery

- No current product-line boundary gate exists.
- No current Agent process lifecycle or protocol conformance fixture exists.
- No current root-change/revocation integration test exists.
- No current two-session workbench test demonstrates routing and isolation.
- Current packaging and scripts assume `frontend/vityo_app`.

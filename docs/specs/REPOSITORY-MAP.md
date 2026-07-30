# Vityo Repository Map

**Purpose:** Define the ownership boundary between Vityo, its first-party companion Agent runtime, and the upstream Styio repository; this file does not track implementation progress.

**Last updated:** 2026-07-30

## 1. Product Boundary

**Vityo is the agent-native IDE for Styio.** It is the only user-facing product identity in this
repository. Its launch path is a complete Styio development loop:

- edit;
- analyze;
- test;
- run;
- observe.

An Agent is optional. When attached, the Agent Workbench adds plan, permission, change-preview, and
verification-receipt workflows without becoming a prerequisite for the IDE.

The independently executable Vityo Coding Agent is Vityo's first-party companion runtime. Other
compatible Agents may connect through the same versioned protocol. Neither runtime is a second
Vityo product.

Styio remains the source of truth for language semantics, compiler behavior, parser, analyzer, IR,
code generation, CLI, JIT, and language conformance.

## 2. Repository Responsibilities

| Repository/package | Role | Owns | Does not own |
|---|---|---|---|
| upstream `styio` | Language and compiler source of truth | Language semantics, syntax, AST, type system, IR, CLI, JIT, diagnostics, compiler tests | IDE experience, editor transactions, Agent Workbench |
| `products/vityo_app` | Vityo product | Editor, language-service client, build/test/run routes, runtime observation, workspace revisions and transactions, Agent Client and Agent Workbench | Model/provider routing, Agent tool loop, durable Agent sessions, multi-Agent orchestration, language semantics |
| `products/vityo_coding_agent` | First-party companion runtime | Model/provider integration, context selection, tool loop, Agent policy, durable sessions, multi-Agent orchestration | IDE source buffers, workspace revision truth, direct IDE file mutation, Styio compiler semantics |
| `packages/vityo_agent_protocol` | Vityo-owned interoperability contract | Versioned IDE/Agent messages, capabilities, task events, proposed changes, permissions, receipts | Product UI, model implementation, workspace mutation |

## 3. Documentation Boundary

This repository owns documentation for:

1. Vityo's product goal, user promise, and interaction constraints.
2. The Flutter shell, custom editor, and cross-platform interaction model.
3. Styio toolchain and language-service integration.
4. Local, hosted, and mobile execution strategy.
5. Runtime observation and Agent Workbench design.
6. The IDE/Agent ownership boundary and shared protocol.

Questions about language semantics, accepted programs, compiler-owned AST/IR/diagnostics, JIT, or
code-generation behavior must return to upstream Styio.

## 4. Future Capability Packaging

Cloud workspaces, profile sync, themes, modules, and additional device surfaces remain future Vityo
capabilities. Their eventual package or repository layout must not create a second public product
identity or move Agent runtime ownership into the IDE.

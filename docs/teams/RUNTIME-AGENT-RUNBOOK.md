# Runtime / Agent Runbook

**Purpose:** Define ownership for runtime/debug surfaces and the IDE-side Agent Workbench without assigning Agent-runtime execution to the IDE.

**Last updated:** 2026-09-05

## Mission

Own runtime/debug presentation, the Agent Client projection, and the Agent Workbench. This team
does not own model/provider routing, Agent tool loops, durable Agent sessions, or multi-Agent
orchestration; those belong to the compatible Agent runtime.

## Owned Surface

Primary paths:

1. `products/vityo_app/lib/src/view_ide/runtime/`
2. `products/vityo_app/lib/src/ide/agent_client/`
   - `agent_client_registry.dart` — supervised protocol connections, correlated sessions, permissions, and reconnect
   - `agent_process_supervisor.dart` — bounded stdio process lifecycle and orphan-free shutdown
   - `mcp/` and `tools/` — root-scoped context/tool export, grants, redaction, and audit receipts
3. `products/vityo_app/lib/src/ide/workbench/agent_collaboration/`
4. `products/vityo_app/lib/src/presentation/agent_workbench/`
5. `products/vityo_app/lib/src/view_render/runtime/`
6. `products/vityo_app/lib/src/runtime/`
   - `runtime_event_log.dart` — append-only runtime event log with ring buffer projection
Review dependency, not an owned path:

1. `products/vityo_coding_agent/lib/src/`
2. `packages/vityo_agent_protocol/`

Key SSOTs:

1. `产品规格 -> ../design/Vityo-Product-Spec.md`
2. `系统架构 -> ../design/Vityo-System-Architecture.md`
3. `测试目录 -> ../assets/workflow/TEST-CATALOG.md`

## Daily Workflow

1. 先确认当前变更是 runtime 可视化还是 Agent 协作入口。
2. 若变更依赖新 adapter payload，先转到 Adapter / Contracts owner 文档确认边界。
3. Treat `Agent Workbench` as the formal capability. `Agent Panel` may remain a concrete view name,
   but it must show task plan, permission, changes, and verification state rather than define the
   product as chat.
4. ProfileSync is a future provider-neutral schema owned by Adapter / Contracts, not a current
   runtime surface. Do not add model/provider credentials or Agent-runtime prompt configuration to
   IDE-owned state.
5. Do not add provider routes, provider SDKs, model credentials, tool loops, policy stores,
   durable-session stores, or multi-Agent orchestration to the IDE.
6. runtime replay、debug lane 和 hosted execution 摘要必须消费 `view_ide/backend_toolchain` adapter payload，不得回读已移除入口或上游 human stderr。
7. IDE-side Agent connections belong to `ide/agent_client`, collaboration projections to
   `ide/workbench/agent_collaboration`, and Flutter presentation to
   `presentation/agent_workbench`; durable session and execution state belong to the companion
   Agent runtime.
8. UI surfaces may display only redacted protocol context and receipt summaries. Accepted source
   changes must pass through IDE-owned workspace transactions.
9. Protocol permission/change semantics or IDE MCP/tool-security changes must update
   [../governance/SECURITY-AND-SUPPLY-CHAIN.md](../governance/SECURITY-AND-SUPPLY-CHAIN.md).

10. `runtime_event_log.dart` changes must keep replay output deterministic on Windows and POSIX hosts; avoid path separator, line-ending, or clock assumptions in runtime event summaries and tests.
11. Agent context may compose Pafio metadata, Styio machine facts, and Platform
    hosted facts only through their formal adapters; it must not expose Pafio
    private storage or suggest removed compiler-management commands.

## Change Classes

1. Small: 局部 panel 状态、展示文案或执行态摘要修正。运行 Flutter 最小验证。
2. Medium: runtime summary, Agent Client connection, Agent Workbench behavior,
   hosted execution replay, or disconnected-Agent state. Update the test catalog.
3. High: protocol semantics, workspace change application, or the IDE/Agent ownership boundary.
   Require architecture and security review.

## Required Gates

Minimum:

```bash
cd products/vityo_app && flutter analyze && flutter test
python3 scripts/check_security_baseline.py
python3 scripts/repo-hygiene-gate.py --mode tracked
```

## Cross-Team Dependencies

1. Adapter / Contracts 必须 review 任何 adapter payload、schema 或 handoff 语义变化。
2. Module / Platform 必须 review 会影响 capability gating、平台差异或分发限制的变更。
3. Theme / UX 必须 review 面板层级、窄屏布局或状态可见性变化。
4. Docs / Delivery 必须 review 测试目录、规格或里程碑映射更新。

## Handoff / Recovery

Record:

1. 受影响的 surface 是 runtime、debug 还是 agent。
2. 当前依赖的 adapter 能力快照和 fallback 路径。
3. 已更新的 schema 或测试目录条目。
4. 下一个阻塞点、回滚点与 history 链接。

2026-09-05: Migrated generic runtime-event intake and replay-summary keys to Styio runtime-events v2 (`from_phase`/`to_phase`; retired v1 `message`/`file`/`thread_id` reads). Runtime surface still degrades unknown v2 kinds. No `prototype/` change.

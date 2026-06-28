# Runtime / Agent Runbook

**Purpose:** 提供 runtime surface、debug/agent 面板、prompt/profile 入口与执行态 UI 的日常维护入口。

**Last updated:** 2026-06-28

## Mission

负责运行态 summary、runtime/debug/agent surface、prompt profile 与 local bridge 入口。该团队不拥有 adapter schema 本身，也不定义模块分发策略。

## Owned Surface

Primary paths:

1. `frontend/vityo_app/lib/src/view_ide/runtime/`
2. `frontend/vityo_app/lib/src/view_ide/agent/`
   - `agent_execution_mode.dart` — agent execution mode (plan-only, build-capable)
   - `agent_provider_access_control.dart` — provider allowlist/denylist
   - `agent_tool_sandbox_router.dart` — sandboxed tool execution router
   - `agent_permission_model.dart` — governed permission model for agent tools, provider routes, and approval journals
3. `frontend/vityo_app/lib/src/view_render/runtime/`
4. `frontend/vityo_app/lib/src/view_render/agent/`
5. `frontend/vityo_app/lib/src/runtime/`
   - `runtime_event_log.dart` — append-only runtime event log with ring buffer projection
6. `frontend/vityo_app/lib/src/agent/` — `agent_session.dart` 保持 façade 再导出到 `view_ide/agent/agent_session.dart`
7. `docs/specs/AGENT-PROVIDER-ADAPTER-SCHEMA.md`
8. `docs/specs/PROFILE-SYNC-ADAPTER-SCHEMA.md`

Key SSOTs:

1. `产品规格 -> ../design/Vityo-Product-Spec.md`
2. `系统架构 -> ../design/Vityo-System-Architecture.md`
3. `测试目录 -> ../assets/workflow/TEST-CATALOG.md`

## Daily Workflow

1. 先确认当前变更是 runtime 可视化、agent 协作入口，还是 profile/prompt 持久化。
2. 若变更依赖新 adapter payload，先转到 Adapter / Contracts owner 文档确认边界。
3. 变更 agent panel 时，避免把它退化成外挂聊天框；保持 IDE 内建能力定位。
4. 变更 profile/prompt 流程时，同步检查本地持久化和 sync adapter 语义。
5. `agent_profile.dart` 只冻结 provider route、默认 endpoint、profile JSON 和 local-bridge eligibility；本轮不新增真实 AI provider 调用、账号策略或云端 secret 管理。
6. runtime replay、debug lane 和 hosted execution 摘要必须消费 `backend_toolchain` adapter payload，不得回读 legacy integration façade 或上游 human stderr。
7. runtime/agent 的纯状态归 `view_ide`，Flutter surface 和 debug/agent panel 呈现归 `view_render`；legacy `src/runtime/` 与 `src/agent/` 只能保留 façade。
8. agent tool execution must route through the sandbox/permission model; UI surfaces may display only redacted context and journal summaries.
9. Permission, provider route, or sandbox changes must update [../governance/SECURITY-AND-SUPPLY-CHAIN.md](../governance/SECURITY-AND-SUPPLY-CHAIN.md) when the policy changes.

10. `runtime_event_log.dart` changes must keep replay output deterministic on Windows and POSIX hosts; avoid path separator, line-ending, or clock assumptions in runtime event summaries and tests.

## Change Classes

1. Small: 局部 panel 状态、展示文案或执行态摘要修正。运行 Flutter 最小验证。
2. Medium: runtime summary、prompt/profile flow、agent provider route、agent panel 行为、hosted execution replay 或 local-only 模式变化。补测试目录映射。
3. High: 执行态主入口、agent provider 适配路径、profile sync 生命周期或平台执行提示变化。走协调 review。

## Required Gates

Minimum:

```bash
cd frontend/vityo_app && flutter analyze && flutter test
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

<!-- codex merge: agent provider/tool/session runtime assets imported -->

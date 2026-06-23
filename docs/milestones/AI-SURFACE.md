# AI Surface

**Purpose:** 把 AI 协作面板做成 IDE 一等能力，支持自定义 prompt、上下文注入、provider adapter 和外接组件接入。

**Last updated:** 2026-04-12

**Status:** In Progress

## 1. 目标

1. 用户无需离开 IDE 即可与 coding agent 交互。
2. prompt profile、文件上下文、诊断和运行态上下文可注入。
3. 在没有本地 agent 和没有云 sync 组件的情况下，基础 AI 面板仍可工作。

## 2. 任务

| Workstream | Deliverable | Dependency | Exit |
|------------|-------------|------------|------|
| Agent session contract | 定义 `AgentSession` 与 provider 抽象 | Foundation and desktop shell | 本地/云端接口统一 |
| AI panel shell | 实现底部或侧边 AI 面板骨架 | Shell layout | 面板可用 |
| Prompt profile model | 设计 prompt profile 数据模型 | Agent session contract | prompt 可持久化 |
| Editor context injection | 注入当前文件、选区、诊断上下文 | Diagnostic feedback route | agent 收到 IDE 上下文 |
| Runtime context injection | 注入运行态上下文 | Runtime surface | agent 可读执行信息 |
| Provider selection | 设计本地 provider 与云 provider 选择逻辑 | Agent session contract | provider 可切换 |
| Suggested edit application | 为后续补丁/代码建议预留应用接口 | Editor context injection | UI 能承载建议结果 |
| Cloud provider adapter | 定义 OpenAI-compatible cloud provider adapter | Agent session contract | 可接通标准兼容端点 |
| Local agent bridge | 预留本地外接 agent bridge | Agent session contract | 本地 agent 可后接入 |
| Profile sync adapter | 定义 `ProfileSyncAdapter` 与 local-only fallback | Prompt profile model | 无 sync 时也可用 |
| Prelaunch provider configuration | 准备预上线 OpenRouter 类 provider 配置位 | Cloud provider adapter | 预上线可直接接云 provider |
| AI viewport family | 让 AI surface 跟随统一视窗族切换桌面/移动排版 | Viewport families and AI panel shell | AI 面板不再与主壳布局脱节 |

## 3. 门禁

1. AI 面板不再是外部链接，而是 IDE 内建面板。
2. 用户可编辑和保存预输入 prompt。
3. agent 至少能读取当前工作上下文。
4. 无本地 agent 和无 sync 组件时，基础 AI 面板仍不失效。

## 4. Current implementation anchor

当前代码入口：

1. `frontend/vityo_app/lib/src/agent/agent_surface.dart`
2. `frontend/vityo_app/lib/src/app/layout/vityo_shell_scaffold.dart`

当前已落地：

1. `AgentSurface` 已按 `ViewportProfile` 切换桌面/移动两套排版
2. agent 相关模块过滤已切到 `ModuleSlot.agentSurface / cloudRuntime`
3. iOS cloud-first 合规路径和 desktop local-bridge 预留已经进入 UI 占位结构

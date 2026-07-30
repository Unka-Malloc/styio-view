# ADR-0013: AI And Profile Integrations Use Provider Adapters

**Purpose:** Preserve the provider/profile adapter decision and identify the Agent-provider portions superseded by [ADR-0019](./ADR-0019-vityo-is-the-styio-agent-native-ide.md); `ProfileSyncAdapter` remains active.

**Last updated:** 2026-07-30

**Status:** Partially superseded by ADR-0019

**Date:** 2026-04-12

## Context

产品明确要求：

1. AI 面板是一等能力
2. 本地 agent 未来可支持，但当前不要求内建
3. prompt / profile 同步需要可选接入
4. 云端 provider 需要可替换，不能绑死单一服务

## Decision

采用：

1. `AgentProviderAdapter` 作为统一 provider 抽象
2. `ProfileSyncAdapter` 作为独立的同步组件抽象
3. 本地 agent 首发只预留外接组件接口，不把模型 runtime 内建到主壳
4. 云端 agent provider 至少支持 OpenAI-compatible endpoint adapter
5. 预上线阶段可先通过同一 adapter 接入 OpenRouter 类 provider
6. 若未挂载 `ProfileSyncAdapter`，prompt / profile 保持 local-only 模式

## Alternatives

1. 把本地模型直接内建进主壳：体积、授权和分发边界过早锁死
2. 把某一家云 provider 写死：后续迁移成本高
3. 把 profile sync 和推理 provider 混成一个组件：边界不清

## Consequences

1. 基础壳在没有本地 agent 和没有云 sync 的情况下也必须可用
2. 本地 agent、云推理和 profile sync 都可以独立迭代
3. 需要定义 provider 配置、密钥存储和故障退化路径

## Current Interpretation

1. `ProfileSyncAdapter` remains an optional IDE service and local-only profiles remain valid when it
   is absent.
2. Model/provider adapters, including OpenAI-compatible endpoints, belong to compatible Agent
   runtimes rather than the Vityo IDE.
3. The IDE connects to those runtimes only through the versioned Agent protocol.
4. The original IDE-owned `AgentProviderAdapter` decision is historical and is not an active target
   architecture.

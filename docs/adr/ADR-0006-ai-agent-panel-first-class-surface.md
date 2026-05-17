# ADR-0006: AI Agent Panel Is A First-Class IDE Surface

**Purpose:** 记录 `Vityo` 如何定位 AI 协作层，以及为什么它不能只是一个外挂聊天窗口。

**Last updated:** 2026-04-12

**Status:** Accepted

**Date:** 2026-04-12

## Context

产品明确要求 AI 协助编程、可编辑 prompt、后续支持 profile、本地或云端 agent。

## Decision

AI agent 作为 IDE 内建一等交互面板，直接接入文件、选区、诊断、运行态和用户 profile。

## Alternatives

1. 只做外链或独立聊天框：无法形成真正的 IDE 内工作流。
2. 只支持云端 agent：与移动端本地可选要求不一致。

## Consequences

1. 需要统一 `AgentSession`、provider 和上下文注入协议。
2. 需要主题、布局和工作区状态与 agent 面板联动。

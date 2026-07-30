# ADR-0006: AI Agent Panel Is A First-Class IDE Surface

**Purpose:** Preserve the superseded panel-first Agent decision for provenance; current product positioning is defined by [ADR-0019](./ADR-0019-vityo-is-the-styio-agent-native-ide.md).

**Last updated:** 2026-07-30

**Status:** Superseded by ADR-0019

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

## Supersession

ADR-0019 replaces the panel-first framing with an Agent Workbench and an open, protocol-only Agent
Client boundary. This record is historical and must not be used as the current product or
architecture owner.

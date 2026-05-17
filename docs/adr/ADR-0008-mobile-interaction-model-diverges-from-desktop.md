# ADR-0008: Mobile Interaction Model May Diverge From Desktop

**Purpose:** 记录 `Vityo` 明确允许移动端交互模型与桌面端分化的决定。

**Last updated:** 2026-04-12

**Status:** Accepted

**Date:** 2026-04-12

## Context

产品明确要求：

1. 移动端本地支持
2. 移动端具备独立操作逻辑
3. pipeline selector 采用长按滚动等不同手势
4. 移动端内建输入预测 agent

## Decision

移动端不追求完全复制桌面编辑体验，而是在共享产品语义的前提下，独立设计输入、滚动、选择和运行交互。

## Alternatives

1. 直接缩放桌面 UI：在手机上可用性差。
2. 完全独立做另一套产品：会损失共享架构与语义。

## Consequences

1. 需要共享数据模型但分平台实现交互层。
2. 里程碑、测试和主题系统都要考虑移动端分支。

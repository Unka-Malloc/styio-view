# ADR-0003: Build A Custom Editor Engine

**Purpose:** 记录 `Vityo` 不复用传统 IDE 编辑控件、而是自研编辑器引擎的决定。

**Last updated:** 2026-04-12

**Status:** Accepted

**Date:** 2026-04-12

## Context

产品需要：

1. token 级图形替换
2. 语义驱动块表面
3. 桌面与移动端不同交互
4. 高度可定制的运行视图与 AI 交互

## Decision

采用自研文档模型、渲染层和交互层，不以传统 IDE 组件或现成代码编辑器控件为基础。

## Alternatives

1. 复用传统 IDE 编辑器组件：难以实现深度视觉语义重写。
2. 只扩展普通文本控件：后续会在语义和交互能力上受限。

## Consequences

1. 获得完整的显示与交互自由度。
2. 需要承担文本输入、光标、选择、撤销/重做、输入法和性能的工程复杂度。

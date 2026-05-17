# ADR-0005: Runtime Visualization Is Driven By Event Stream

**Purpose:** 记录 `Vityo` 的运行可视图如何从执行层接收数据，而不是从 UI 侧猜测程序结构。

**Last updated:** 2026-04-12

**Status:** Accepted

**Date:** 2026-04-12

## Context

底部运行视图需要展示线程轨、状态机或简化图，但 Styio 语义不应由 UI 层伪造。

## Decision

运行视图以 `RuntimeEvent` 和中间图模型为基础，由执行层显式提供可视化输入。

## Alternatives

1. UI 直接从源码文本猜测图结构：不可靠。
2. 一开始追求全语义图：成本过高且容易造假。

## Consequences

1. 运行图只能覆盖已定义事件协议的语义子集。
2. 需要先冻结事件协议，再扩展可视化。
3. 不支持的语义必须显式退化。

# ADR-0012: Runtime Visualization Uses An Ordered RuntimeEvent Protocol

**Purpose:** 记录 `Vityo` 为什么要先冻结执行层到 UI 的最小事件协议，以及该协议的排序与退化原则。

**Last updated:** 2026-04-12

**Status:** Accepted

**Date:** 2026-04-12

## Context

运行视图需要从执行层获取稳定输入，用于驱动：

1. 线程轨
2. 简化状态图
3. 日志与诊断

如果没有统一协议，UI 很容易直接从源码或临时回调拼图，最终导致线程轨、图视图和控制台彼此不一致。

## Decision

执行层向 UI 暴露统一的有序 `RuntimeEvent` 协议。

最小 envelope：

1. `schemaVersion`
2. `sessionId`
3. `sequence`
4. `timestamp`
5. `origin`
6. `eventKind`
7. `threadId?`
8. `unitId?`
9. `span?`
10. `tags[]`
11. `payload`

最小事件种类：

1. `compile.started`
2. `compile.finished`
3. `compile.failed`
4. `run.started`
5. `run.finished`
6. `thread.spawned`
7. `thread.exited`
8. `unit.entered`
9. `unit.exited`
10. `state.entered`
11. `state.exited`
12. `transition.fired`
13. `log.emitted`
14. `diagnostic.emitted`

协议原则：

1. 同一 `RunSession` 内使用 `sequence` 保证稳定顺序
2. 未识别事件必须退化而不是崩溃
3. 图视图、线程轨和控制台都从同一事件流派生

## Alternatives

1. UI 直接猜运行结构：不可靠
2. 每个视图各自订阅不同回调：容易产生状态分叉
3. 等全部语义完成后再定协议：会阻塞实现

## Consequences

1. 必须为 `RuntimeEvent` 提供 schema versioning
2. 可视化覆盖范围将与事件种类和特性注册表一起渐进扩张
3. 执行层与 UI 的集成会更稳定，也更适合跨平台复用

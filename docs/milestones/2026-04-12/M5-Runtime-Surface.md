# M5 — Runtime Surface

**Purpose:** 建立底部运行视图区、事件流协议和线程轨/简化图模型的最小闭环。

**Last updated:** 2026-04-12

**Status:** In Progress

## 1. 目标

1. 用户运行程序后可以在底部看到结构化运行视图。
2. 运行视图只覆盖当前已能明确表达的语义子集。

## 2. 任务

| Task ID | Deliverable | Dependency | Exit |
|---------|-------------|------------|------|
| M5-T01 | 定义 `RuntimeEvent` 最小协议 | M4 | 事件模型冻结 |
| M5-T02 | 定义 `RuntimeSurfaceFeatureEntry` 与 registry schema | M5-T01 / M9-T01 | 可声明已支持的可视化子集 |
| M5-T03 | 定义线程轨 `ThreadLaneState` 数据模型 | M5-T01 | 可表达并行执行轨迹 |
| M5-T04 | 定义简化图 `RuntimeGraphNode/Edge` 模型 | M5-T01 | 可表达状态或流程 |
| M5-T05 | 实现底部运行面板骨架 | M1-T03 | 面板可承载视图 |
| M5-T06 | 实现线程轨 UI | M5-T03 | 可显示多条并行线 |
| M5-T07 | 实现最小图视图 UI | M5-T04 | 可显示简化节点/边 |
| M5-T08 | 启动时按已装模块加载 runtime surface feature registry | M5-T02 / M9-T05 | 入口列表与已装模块一致 |
| M5-T09 | 建立“仅对支持子集可视化”的显式提示 | M5-T02 / M5-T07 | 不伪造语义 |
| M5-T10 | 让 runtime surface 跟随统一视窗族切换桌面/移动排版 | M1-T10 / M5-T05 | 底部运行面板不再脱离主壳布局语义 |

## 3. 门禁

1. 运行一个最小程序后，底部面板有结构化可视反馈。
2. 不支持的语义必须明确退化，而不是假装已覆盖。
3. 启动后的可视化入口列表必须与已装模块和 capability matrix 一致。

## 4. Current implementation anchor

当前代码入口：

1. `frontend/vityo_app/lib/src/runtime/runtime_surface.dart`
2. `frontend/vityo_app/lib/src/runtime/debug_console_surface.dart`
3. `frontend/vityo_app/lib/src/app/layout/vityo_shell_scaffold.dart`

当前已落地：

1. `RuntimeSurface` 已按 `ViewportProfile` 切换桌面/移动两套占位排版
2. runtime 相关模块过滤已经从字符串匹配切到 `ModuleSlot` 显式判定
3. `DebugConsoleSurface` 已接入桌面/移动两套 header 和摘要结构
4. 底部 tab 切换仍由统一 `ShellModel.activeBottomTab` 驱动

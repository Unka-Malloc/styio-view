# Runtime Surface

**Purpose:** 建立底部运行视图区、事件流协议和线程轨/简化图模型的最小闭环。

**Last updated:** 2026-04-12

**Status:** In Progress

## 1. 目标

1. 用户运行程序后可以在底部看到结构化运行视图。
2. 运行视图只覆盖当前已能明确表达的语义子集。

## 2. 任务

| Workstream | Deliverable | Dependency | Exit |
|------------|-------------|------------|------|
| Runtime event protocol | 定义 `RuntimeEvent` 最小协议 | Desktop compile and run | 事件模型冻结 |
| Runtime surface registry | 定义 `RuntimeSurfaceFeatureEntry` 与 registry schema | Runtime event protocol and module manifest | 可声明已支持的可视化子集 |
| Thread lane model | 定义线程轨 `ThreadLaneState` 数据模型 | Runtime event protocol | 可表达并行执行轨迹 |
| Runtime graph model | 定义简化图 `RuntimeGraphNode/Edge` 模型 | Runtime event protocol | 可表达状态或流程 |
| Runtime panel shell | 实现底部运行面板骨架 | Shell layout | 面板可承载视图 |
| Thread lane UI | 实现线程轨 UI | Thread lane model | 可显示多条并行线 |
| Runtime graph UI | 实现最小图视图 UI | Runtime graph model | 可显示简化节点/边 |
| Runtime feature loading | 启动时按已装模块加载 runtime surface feature registry | Runtime surface registry and module lifecycle | 入口列表与已装模块一致 |
| Visualization coverage notice | 建立“仅对支持子集可视化”的显式提示 | Runtime surface registry and runtime graph UI | 不伪造语义 |
| Runtime viewport family | 让 runtime surface 跟随统一视窗族切换桌面/移动排版 | Viewport families and runtime panel shell | 底部运行面板不再脱离主壳布局语义 |

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

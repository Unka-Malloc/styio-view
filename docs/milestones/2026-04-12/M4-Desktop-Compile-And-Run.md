# M4 — Desktop Compile And Run

**Purpose:** 在桌面端交付保存编译、快捷键运行、诊断回指和最小运行闭环。

**Last updated:** 2026-04-12

**Status:** In Progress

## 1. 目标

1. 用户保存或显式运行时，可编译并执行最小合法单元。
2. 编译和运行结果能回流到编辑器与底部面板。

## 2. 任务

| Task ID | Deliverable | Dependency | Exit |
|---------|-------------|------------|------|
| M4-T01 | 定义保存后自动编译策略与配置项 | M3-T07 | 行为可配置 |
| M4-T02 | 接入 `Ctrl + Enter` 或平台等效运行命令 | M1-T04 | 快捷键能触发运行 |
| M4-T03 | 打通桌面本地 compile API | M3 | 能返回编译成功/失败 |
| M4-T04 | 打通桌面本地 run API | M4-T03 | 能运行最小示例 |
| M4-T05 | 把 diagnostics 显示回编辑器与底部面板 | M3-T02 | 错误可定位 |
| M4-T06 | 定义 compile / run session 状态模型 | M4-T03 | UI 能跟踪执行状态 |
| M4-T07 | 建立日志与 stdout/stderr 面板 | M4-T04 | 运行输出可见 |
| M4-T08 | 建立 scratch single-file route 与 project preview-only route 分流 | M3 | capability gap 清晰可见 |
| M4-T09 | 在工作区与 runtime 面板展示 workflow / compiler handshake / route summary | M4-T06 | 用户能直接看到当前路由与限制 |

## 3. 门禁

1. 用户可从桌面端编辑、保存、运行一个 Styio 最小单元。
2. 编译失败时，诊断能回指到当前代码位置。
3. 运行状态可反馈给 UI。
4. project-backed route 在 compile-plan live consumer 发布前必须明确显示 preview-only，而不是伪装成可运行。

## 4. Current implementation anchor

当前代码入口：

1. `frontend/vityo_app/lib/src/integration/execution_adapter.dart`
2. `frontend/vityo_app/lib/src/integration/execution_adapter_io.dart`
3. `frontend/vityo_app/lib/src/integration/execution_route_summary.dart`
4. `frontend/vityo_app/lib/src/runtime/runtime_surface.dart`
5. `frontend/vityo_app/lib/src/app/layout/vityo_shell_scaffold.dart`

当前已落地：

1. scratch single-file CLI route
2. iOS cloud-only blocked route
3. project-backed preview-only route
4. `ExecutionSession` 状态模型与 runtime/debug 回流
5. workspace 侧栏里的 `Project Workflow` 和 `Compiler Handshake` 卡片
6. workspace 侧栏里的 `Required Handoffs` 卡片，用产品语言明确 `styio` / `spio` 尚未交付的 machine contract

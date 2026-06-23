# Foundation And Desktop Shell

**Purpose:** 冻结仓库骨架、Flutter 桌面应用壳、模块宿主基础、导航结构和最小开发循环，为后续自研编辑器与桥接层提供稳定落点。

**Last updated:** 2026-04-12

**Status:** In Progress

## 1. 目标

1. 让仓库具备明确模块边界。
2. 建立 Flutter 桌面应用骨架。
3. 建立主窗口、底部面板、侧栏和工作区导航的基本布局。

## 2. 任务

| Workstream | Deliverable | Dependency | Exit |
|------------|-------------|------------|------|
| Flutter project scaffold | 建立 Flutter 工程骨架与模块目录 | none | 能在桌面启动空应用 |
| Functional module boundaries | 定义 `app/`, `editor/`, `runtime/`, `agent/`, `theme/` 模块边界 | Flutter project scaffold | 目录与入口冻结 |
| Shell layout | 建立主窗口布局：编辑区、底部区、侧栏、状态栏 | Flutter project scaffold | UI 壳可见 |
| Command routing | 建立全局快捷键与命令路由骨架 | Shell layout | 可注册命令但行为可为空 |
| Workspace state route | 建立基础状态管理和工作区路由骨架 | Functional module boundaries | 允许打开单工作区 |
| Debug panel | 建立桌面开发模式的日志与调试面板骨架 | Shell layout | 调试输出可见 |
| Native bridge boundary | 为后续 `dart:ffi` 预留原生模块加载层 | Functional module boundaries | 入口与目录固定 |
| Module host | 建立 module host、module slot 和 manifest 加载骨架 | Functional module boundaries | 模块宿主存在 |
| Platform capability matrix | 建立平台 capability matrix 基础配置 | Module host | 不同平台可决定模块可见性 |
| Viewport families | 冻结统一视窗族：桌面端与 Web 桌面布局对齐，移动端与 Web 手机布局对齐 | Shell layout | 各平台不再各自发散布局语义 |

## 3. 门禁

1. 应用能在 macOS / Windows / Linux 中至少一个桌面平台启动。
2. 主布局可承载后续编辑器、运行视图和 AI 面板。
3. 模块边界与文档一致。
4. 基础模块宿主已存在，后续功能可按模块接入。

## 4. Current implementation anchor

当前代码入口：

1. `frontend/vityo_app/`
2. `lib/src/app/`
3. `lib/src/editor/`
4. `lib/src/runtime/`
5. `lib/src/agent/`
6. `lib/src/theme/`
7. `lib/src/module_host/`
8. `lib/src/platform/`

当前已落地：

1. 六端共享 Flutter 工程骨架与 bootstrap 脚本
2. 主壳布局：工作区侧栏、编辑区、模块侧栏、底部 surface、状态栏
3. 全局命令路由与快捷键骨架
4. `ModuleManifest` 资产与平台 capability matrix 基线
5. 原生 bridge 保留层与 smoke test
6. 本机 Flutter `3.41.6` / Dart `3.11.4` 已安装并完成 runner bootstrap
7. `flutter test`、`flutter analyze`、`flutter build web`、`flutter build macos --debug` 已通过
8. `ViewportProfile` 已接入主壳，`Windows/Linux/macOS` 与宽屏 `Web` 统一到 `Desktop` 布局族，`Android/iOS` 与窄屏 `Web` 统一到 `Mobile` 布局族

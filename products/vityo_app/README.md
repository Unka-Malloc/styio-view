# Vityo — Styio Agent-Native IDE

这是 Vityo IDE 的 Flutter 主实现入口。Vityo 是面向 Styio 的 Agent-Native IDE；即使没有
安装或连接 Agent，也必须保持完整的编辑、语言服务、构建、测试、运行和观察能力。

本目录负责承载：

当前 Flutter package 与主实现目录已统一为 `products/vityo_app` / `vityo_app`，平台 runner 与 bundle id 也使用 Vityo 命名。

1. `web / windows / linux / android / macos / ios` 六端共享 GUI 壳
2. `app / editor / runtime / agent_client / agent_workbench / theme / module_host / platform` 模块边界
3. 模块 manifest、platform capability matrix 与启动时装载骨架
4. `ProjectGraphAdapter / ExecutionAdapter / RuntimeEventAdapter` 的产品级消费面
5. `CLI / FFI / Cloud` 三类 adapter route 的统一能力快照
6. Agent Client、Agent Workbench 与版本化协议的 IDE 侧能力

仓库级 bootstrap、共享工具链和常用构建命令见 [../../docs/BUILD-AND-DEV-ENV.md](../../docs/BUILD-AND-DEV-ENV.md)；本页只负责 Flutter 主壳自身的实现和平台 runner 细节。

当前标准 Flutter 基线固定为 `3.41.7`，配套 Dart SDK 固定为 `3.11.5`。

## Release readiness gate

正式发布前需要从仓库根目录执行：

```bash
./scripts/delivery-gate.sh --mode checkpoint
python3 scripts/release-readiness-gate.py
```

`delivery-gate` 负责仓库卫生、文档、完整 Flutter 测试、语言 fixture、prototype governance 和 editor selftest。`release-readiness-gate.py` 负责发布级证据：

1. 检查 `products/vityo_app/pubspec.yaml` 的 Vityo editor 元数据。
2. 检查关键 IDE 能力是否都有测试入口，包括 editor binding、language service、runtime/toolchain、environment/data persistence。
3. 检查本 README 是否记录正式发布命令。
4. 检查 `toolchain/maintenance-tools.json` 中的维护工具和技能均为 current，且每条交付轨道至少有一个可用维护工具。
5. 执行 `flutter build web --release`，确认 Web release artifact 可生成。

如果只需要快速检查发布元数据和测试入口，可以执行：

```bash
python3 scripts/release-readiness-gate.py --skip-build
```

## Frontend vs Backend Boundary

前端拥有：

1. `lib/src/view_render/` 作为用户壳层和 Flutter 呈现的显式入口边界
2. `lib/src/view_render/shell/` 作为用户壳层、底部面板和 scaffold 的外观边界
3. `lib/src/view_render/editor/` 作为编辑器 Flutter surface、源码预览、language inspector 和交互展示边界
4. `lib/src/view_render/runtime/` 作为 runtime/debug surface 的外观边界
5. `lib/src/view_render/agent_workbench/` 作为 Agent 任务、权限、变更和回执投影的外观边界
6. `lib/src/view_render/theme/` 与 `lib/src/view_render/platform/` 作为主题和 viewport 响应式外观边界
7. 桌面、移动端与 Web 的壳层和页面编排
8. 面向人的工作区、运行视图、Agent Workbench 和主题体验

后端拥有：

1. `lib/src/view_ide/language/` 作为 IDE 语言智能、语法、高亮、symbol/refactor 预检的第一核心功能边界
2. `lib/src/view_ide/editor/` 作为文档状态、选择状态和 editor controller 的功能边界
3. `lib/src/view_ide/workspace/` 作为 workspace/project selection 与 document store 的功能边界
4. `lib/src/view_ide/module_host/` 作为 module manifest、capability matrix 和 lifecycle policy 的功能边界
5. `lib/src/view_ide/shell_runtime/` 作为 shell runtime、命令执行、阻塞原因、日志、运行会话和 workflow state 的功能边界
6. `lib/src/view_ide/backend_toolchain/` 作为工具链后端与 adapter 实现的显式入口边界
7. local CLI / FFI / hosted control plane 的能力提供
8. `pafio` / `styio` 的 project graph、toolchain、dependency、execution、deployment、runtime-event 合同

产品边界：

1. Vityo 是唯一对外产品；Coding Agent 是第一方配套运行时，不是第二个产品身份。
2. IDE 实现只落在 `products/vityo_app`，Coding Agent 实现只落在 `products/vityo_coding_agent`。
3. IDE 通过 `lib/src/view_ide/agent_client/` 消费版本化协议，不导入 Coding Agent 实现。
4. Agent Workbench 呈现只落在 `lib/src/view_render/agent_workbench/`。
5. IDE 不直接连接模型 provider；provider、工具循环、策略、持久会话和 multi-Agent 编排归 Agent 运行时。
6. 跨边界 DTO、能力协商与会话信封只落在 `packages/vityo_agent_protocol`。
7. 已移除的旧产品根、旧包身份和旧 Agent 根目录不得重新创建。

规则：

1. Flutter 主壳不重新实现编译器、包管理器或 registry/cloud 语义。
2. UI 只能消费 adapter 合同和 machine payload，不能依赖上游私有目录结构。
3. Web 与 iOS 的 hosted/cloud 路线仍然属于后端工具链面，不属于前端业务逻辑。
4. 新的 IDE 工具链实现默认落在 `view_ide/backend_toolchain/`；跨产品调用只能经过共享协议和 Agent Client。

## 当前状态

当前目录已经具备可运行的 Flutter 工程，当前本机验证状态：

1. `lib/` 共享壳代码
2. `assets/` 模块 manifest 与 capability matrix
3. `scripts/bootstrap_flutter_platforms.sh` 平台 runner 生成脚本
4. 六端 runner 已生成
5. `flutter test`、`flutter analyze`、`flutter build web`、`flutter build macos --debug` 已通过
6. 编辑器已具备桌面键盘输入、基础光标移动、inline glyph 预览与函数 block surface
7. 当前 `Save` 已接入 `WorkspaceDocumentStore`：本地端优先落文件系统，`web` 端走 `shared_preferences`
8. 编辑器已具备鼠标拖拽选区和基础选区高亮
9. 统一视窗族已经接入：`Windows/Linux/macOS` 与宽屏 `Web` 对齐桌面布局，`Android/iOS` 与窄屏 `Web` 对齐移动布局
10. 底部 `runtime / agent / debug` surface 已接入桌面/移动两套排版，并由同一状态模型驱动
11. 编辑器内部的 language inspector 也已接入统一视窗族；即使是宽屏 `iOS/Android` 也保持 mobile 交互和面板布局
12. language inspector 现已分化为 `desktop card stack / mobile section tabs` 两种形态，diagnostics、blocks、hover、completion、formatting 不再在窄屏里硬塞
13. active line 现在会在源码流里直接显示 inline language feedback，展示 diagnostics、hover、completion、formatting 或 caret context
14. inline language feedback 与 language inspector 都已支持直接应用 completion / formatting action，不再只是只读预览
15. diagnostics 已接入最小 quick-fix 回路，当前可直接修复 `missing assignment / stray brace / unclosed block`
16. 光标所在 token 现在会在正文中高亮，inline feedback 与 language inspector 也会显示该 token 的 lexeme / kind / semantic 上下文
17. 工作区已从 seed workspace 切到 owner-contract 模型：Pafio metadata 描述项目、Styio machine-info 描述编译器、Platform hosted API 描述远程工作区
18. 主线已消费 `ProjectGraphAdapter` 与 `ExecutionAdapter`，并把 `CLI / FFI / Cloud` route 统一折叠为 `AdapterCapabilitySnapshot`
19. 工作区侧栏现在会显式展示 `Project Workflow` 与 `Compiler Handshake`，把 project preview 限制、toolchain 来源、compiler contracts 和当前主路由直接做成卡片
20. `Runtime Surface` 已复用同一份 execution route summary，并能显示最近一次执行的 `unit range / stdout / stderr / diagnostics` 统计
21. 工作区侧栏新增 `Required Handoffs` 卡，只表达 `Vityo` 还需要 `styio` / `pafio` 提供哪些 machine contract，不替上游做内部实现规划
22. 项目视图细化到 `workspace members / packages / dependencies / targets` 四层展示，缺少 metadata 时稳定阻塞，不再从 canonical files 推断 package facts
23. `lib/src/view_ide/` 已承载 language、editor core、workspace、module host、runtime model、shell runtime、Agent Client、commands、platform target 与 backend toolchain
24. `lib/src/view_render/` 已承载 shell、editor surface、runtime/debug surface、Agent Workbench、theme 和 viewport profile

## 生成六端 runner

在一台新的 Debian/Ubuntu 容器或虚拟机上，可先从仓库根目录运行：

```bash
./scripts/bootstrap-dev-env.sh
```

在安装 Flutter SDK 之后执行：

```bash
cd products/vityo_app
./scripts/bootstrap_flutter_platforms.sh
flutter pub get
flutter run -d macos
```

脚本会为以下平台生成 runner：

1. `web`
2. `windows`
3. `linux`
4. `android`
5. `macos`
6. `ios`

## 当前目录结构

```text
lib/src/view_render
lib/src/view_render/agent_workbench
lib/src/view_render/editor
lib/src/view_render/platform
lib/src/view_render/runtime
lib/src/view_render/shell
lib/src/view_render/theme
lib/src/view_ide
lib/src/view_ide/language
lib/src/view_ide/language/contract
lib/src/view_ide/language/syntax
lib/src/view_ide/language/semantic
lib/src/view_ide/language/service
lib/src/view_ide/language/features
lib/src/view_ide/editor
lib/src/view_ide/editor/document
lib/src/view_ide/editor/selection
lib/src/view_ide/editor/controller
lib/src/view_ide/editor/transactions
lib/src/view_ide/editor/render_plan
lib/src/view_ide/editor/actions
lib/src/view_ide/workspace
lib/src/view_ide/module_host
lib/src/view_ide/runtime
lib/src/view_ide/shell_runtime
lib/src/view_ide/agent
lib/src/view_ide/commands
lib/src/view_ide/platform
lib/src/view_ide/backend_toolchain
lib/src/app
lib/src/editor
lib/src/language          # compatibility exports only
lib/src/backend_toolchain  # compatibility exports only
lib/src/integration        # compatibility exports only
lib/src/language
lib/src/runtime
lib/src/agent
lib/src/theme
lib/src/module_host
lib/src/platform
assets/module_manifests
assets/capability_matrices
```

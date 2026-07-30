# Vityo

**Vityo 是面向 Styio 的 Agent-Native IDE。**

Vityo 把源码编辑、权威语言/编译/运行事实，以及可审查的 Agent 协作统一到一个可信工作台。
即使没有安装或连接 Agent，用户仍可完成 `edit -> analyze -> test -> run -> observe` 的完整
Styio 开发闭环；连接 Agent 后，计划、工具活动、权限、变更预览与验证回执都保持可见、可控。

本仓库是 Vityo 的 downstream nightly 仓库；Flutter package 与主实现目录已统一为 `vityo_app`。

Downstream nightly repository: <https://github.com/Unka-Malloc/vityo-nightly>

Vityo 是本仓唯一对外产品。Vityo Coding Agent 是可独立运行、也可被其他兼容客户端调用的
第一方配套运行时；二者只通过版本化 Agent 协议协作。Styio 是 Vityo 消费的外部语言、编译器
与工具链生态，不是本仓产品名称。

当前仓库阶段为 `product-led integration bootstrap`：

1. `Vityo` 先冻结产品合同与 adapter 边界
2. Flutter 主壳与编辑器核心继续独立推进
3. 上游 `styio` / `pafio` 按 `Vityo` 的合同补齐机器接口
4. Flutter 应用（`products/vityo_app`）是默认打开的客户端；手写的 `prototype/` JavaScript 原型已归档为 Draft，仅作历史参考，不再维护

文档入口见 [docs/README.md](docs/README.md)。

仓库级构建与新环境入口见 [docs/BUILD-AND-DEV-ENV.md](docs/BUILD-AND-DEV-ENV.md)。

贡献流程见 [CONTRIBUTING.md](CONTRIBUTING.md)。

安全报告与安全基线见 [SECURITY.md](SECURITY.md) 和 [docs/governance/SECURITY-AND-SUPPLY-CHAIN.md](docs/governance/SECURITY-AND-SUPPLY-CHAIN.md)。

发布与 checkpoint 规则见 [docs/governance/RELEASE-CHECKLIST.md](docs/governance/RELEASE-CHECKLIST.md)。

默认客户端入口见 [products/vityo_app/README.md](products/vityo_app/README.md)（Flutter，跨平台，可用浏览器打开）。

已归档的 Draft 原型入口见 [prototype/index.html](prototype/index.html) 与 [prototype/editor.html](prototype/editor.html)（不再维护，仅作参考）。

## Product And Runtime Boundary

- `products/vityo_app/` 是 Vityo IDE：拥有源码、workspace revision、Styio
  语言/编译/运行事实、Agent Workbench、权限呈现、变更审查和 workspace transaction。
- `products/vityo_coding_agent/` 是第一方配套 Agent 运行时：拥有模型/provider、上下文选择、
  工具与策略、coding loop、持久会话和 multi-Agent 编排。
- `packages/vityo_agent_protocol/` 是双方及其它兼容 Agent 使用的纯版本化协议，不是第三个产品。
- IDE 不直接连接模型 provider，也不导入 Agent 运行时实现；无 Agent 时仍保持完整 IDE 能力。

## Frontend / Backend Split

- 前端是面向用户的编辑器、运行视窗、Agent Workbench 和产品交互界面；默认客户端入口在 `products/vityo_app/`（Flutter），`prototype/` 为已归档的 Draft 原型。
- 后端不是单一服务，而是 `Vityo` 背后的整条工具链面：adapter layer、local CLI/FFI、hosted control plane，以及上游 `pafio` / `styio` 合同。
- 前端只编排和展示 machine contract；工具链解析、依赖/发布/执行语义、仓库与云平台行为都留在后端。模型/provider 与 Agent 执行编排留在兼容 Agent 运行时。

系统级边界定义见 [docs/design/Vityo-System-Architecture.md](docs/design/Vityo-System-Architecture.md)。

## Fresh Dev Environment

容器 / 虚拟机：

```bash
./scripts/bootstrap-dev-container.sh
```

Linux 本机：

```bash
./scripts/bootstrap-dev-env.sh
./scripts/bootstrap-dev-env.sh --with-android
```

macOS 本机：

```bash
./scripts/bootstrap-dev-env-macos.sh
./scripts/bootstrap-dev-env-macos.sh --with-ios
./scripts/bootstrap-dev-env-macos.sh --with-android
```

Windows 本机：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-dev-env-windows.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-dev-env-windows.ps1 -WithAndroid
```

Windows native desktop validation:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-workspace.ps1 -Platforms web,windows
Set-Location products\vityo_app
flutter pub get
flutter analyze
flutter test
flutter build windows --debug
```

The PowerShell workspace bootstrap prepares Flutter Windows plugin junctions when needed, so a normal non-admin PowerShell host can build the native Windows target without WSL or Docker.

这套脚本会把 `Vityo` 的桌面 / Web 主线环境拉起，并按需附加 `linux+android`、`macos+ios`、`macos+android`、`windows+android` 组合开发工具链。共享 workspace 初始化入口是：

```bash
./scripts/bootstrap-workspace.sh --platforms web,linux
```

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-workspace.ps1 -Platforms web,windows
```

更完整的构建、测试、profile 切换和真实设备验证入口见 [docs/BUILD-AND-DEV-ENV.md](docs/BUILD-AND-DEV-ENV.md)。

## Repository Hygiene Gate

1. GitHub Actions workflow `Repository Hygiene Gate` 会在每次 `push` 和 `pull_request` 时执行 `python3 scripts/repo-hygiene-gate.py`
2. `python3 scripts/repo-hygiene-gate.py` 是仓库级权威入口
3. 这道门禁会阻断生成目录、依赖目录、打包产物后缀，以及未被明确允许的二进制文件进入仓库
4. 合法的图片类资产需要放在当前允许的前端资源路径下；若确实需要新增二进制资产，应在脚本里补一条窄范围 allowlist，而不是放宽通用规则

## Architecture And Release Gates

本仓当前 IDE 主线以 `view_ide/` 承载 domain/application/contracts，以 `view_render/` 承载
Flutter presentation；第一方配套 Coding Agent 与共享协议分别位于独立实现包和中立协议包。
日常结构性变更至少运行：

```bash
python3 scripts/check_architecture_boundaries.py
python3 scripts/check_product_line_boundaries.py
python3 scripts/check_security_baseline.py
python3 scripts/check_performance_budgets.py
git diff --check
```

文档树变更后运行：

```bash
python3 scripts/docs-index.py --write
python3 -m pytest tests/test_docs_tooling_coverage.py
```

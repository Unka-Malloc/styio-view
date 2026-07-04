# Vityo

Vityo 是面向 `styio` 生态的专属 IDE、编辑器与运行视窗项目。

本仓库是 Vityo 的 downstream nightly 仓库；Flutter package 与主实现目录已统一为 `vityo_app`。

Canonical upstream repository: <https://github.com/eBioRing/Vityo>

Downstream nightly repository: <https://github.com/Unka-Malloc/vityo-nightly>

当前仓库阶段为 `product-led integration bootstrap`：

1. `Vityo` 先冻结产品合同与 adapter 边界
2. Flutter 主壳与编辑器核心继续独立推进
3. 上游 `styio` / `pafio` 按 `Vityo` 的合同补齐机器接口
4. 面向人维护的网页入口只保留手写的 `editor.html` 线；`frontend/vityo_app/build/web` 这类 Flutter 生成物只用于构建验证，不作为人工维护页面

文档入口见 [docs/README.md](docs/README.md)。

仓库级构建与新环境入口见 [docs/BUILD-AND-DEV-ENV.md](docs/BUILD-AND-DEV-ENV.md)。

贡献流程见 [CONTRIBUTING.md](CONTRIBUTING.md)。

安全报告与安全基线见 [SECURITY.md](SECURITY.md) 和 [docs/governance/SECURITY-AND-SUPPLY-CHAIN.md](docs/governance/SECURITY-AND-SUPPLY-CHAIN.md)。

发布与 checkpoint 规则见 [docs/governance/RELEASE-CHECKLIST.md](docs/governance/RELEASE-CHECKLIST.md)。

可直接查看的高保真原型入口见 [prototype/index.html](prototype/index.html)。

人工维护的 Web Editor 入口见 [prototype/editor.html](prototype/editor.html)。

实际实现入口见 [frontend/vityo_app/README.md](frontend/vityo_app/README.md)。

## Frontend / Backend Split

- 前端是面向用户的编辑器、运行视窗和产品交互界面，入口在 `frontend/vityo_app/` 与 `prototype/`。
- 后端不是单一服务，而是 `Vityo` 背后的整条工具链面：adapter layer、local CLI/FFI、hosted control plane，以及上游 `pafio` / `styio` 合同。
- 前端只编排和展示 machine contract；工具链解析、依赖/发布/执行语义、仓库与云平台行为都留在后端。

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
Set-Location frontend\vityo_app
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

本仓当前 IDE 主线以 `view_ide/` 承载 domain/application/contracts，以 `view_render/` 承载 Flutter presentation，以 legacy roots 保留一行 compatibility façade。日常结构性变更至少运行：

```bash
python3 scripts/check_architecture_boundaries.py
python3 scripts/check_compat_facades.py
python3 scripts/check_security_baseline.py
python3 scripts/check_performance_budgets.py
git diff --check
```

文档树变更后运行：

```bash
python3 scripts/docs-index.py --write
python3 -m pytest tests/test_docs_tooling_coverage.py
```

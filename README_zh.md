# Styio View

Styio View 是面向 `styio` 生态的专属编辑器与运行视窗项目。

当前仓库阶段为 `product-led integration bootstrap`：

1. `styio-view` 先冻结产品合同与 adapter 边界
2. Flutter 主壳与编辑器核心继续独立推进
3. 上游 `styio` / `pafio` 按 `styio-view` 的合同补齐机器接口
4. 面向人维护的网页入口只保留手写的 `editor.html` 线；`frontend/styio_view_app/build/web` 这类 Flutter 生成物只用于构建验证，不作为人工维护页面

[English](README.md) | [文档入口](docs/README.md) | [构建指南](docs/BUILD-AND-DEV-ENV.md)

---

## 前端 / 后端分界

- 前端是面向用户的编辑器、运行视窗和产品交互界面，入口在 `frontend/styio_view_app/` 与 `prototype/`。
- 后端不是单一服务，而是 `styio-view` 背后的整条工具链面：adapter layer、local CLI/FFI、hosted control plane，以及上游 `pafio` / `styio` 合同。
- 前端只编排和展示 machine contract；工具链解析、依赖/发布/执行语义、仓库与云平台行为都留在后端。

系统级边界定义见 [Styio-View-System-Architecture.md](docs/design/Styio-View-System-Architecture.md)。

## 开发环境

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

共享 workspace 初始化入口：

```bash
./scripts/bootstrap-workspace.sh --platforms web,linux
```

更完整的构建、测试、profile 切换和真实设备验证入口见 [docs/BUILD-AND-DEV-ENV.md](docs/BUILD-AND-DEV-ENV.md)。

## 仓库门禁

1. GitHub Actions workflow `Repository Hygiene Gate` 会在每次 `push` 和 `pull_request` 时执行 `python3 scripts/repo-hygiene-gate.py`
2. `python3 scripts/repo-hygiene-gate.py` 是仓库级权威入口
3. 这道门禁会阻断生成目录、依赖目录、打包产物后缀，以及未被明确允许的二进制文件进入仓库
4. 合法的图片类资产需要放在当前允许的前端资源路径下；若确实需要新增二进制资产，应在脚本里补一条窄范围 allowlist，而不是放宽通用规则

## 许可证

Apache-2.0。见 [LICENSE](LICENSE)。

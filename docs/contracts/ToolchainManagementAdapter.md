# ToolchainManagementAdapter

**Purpose:** 冻结 managed compiler 安装、切换与项目 pin 操作，让前端与后端能围绕统一 toolchain 管控语义独立演进。

**Last updated:** 2026-04-21

## 1. Result Contract

### `ToolchainCommandResult`

1. `command`
2. `status = blocked | succeeded | failed`
3. `statusMessage`
4. `stdout`
5. `stderr`
6. `payload`
7. `errorPayload`

## 2. Operations

1. `installManagedCompiler(projectGraph, styioBinaryPath)`
2. `useManagedCompiler(projectGraph, compilerVersion, channel)`
3. `pinManagedCompiler(projectGraph, compilerVersion, channel)`
4. `clearPinnedCompiler(projectGraph)`

## 3. Hosted Route Mapping

当 adapter 走 cloud/hosted route 时，固定对接：

1. `POST /api/styio-hosted/v1/workspaces/{workspace_id}/tool/install`
2. `POST /api/styio-hosted/v1/workspaces/{workspace_id}/tool/use`
3. `POST /api/styio-hosted/v1/workspaces/{workspace_id}/tool/pin`
4. `POST /api/styio-hosted/v1/workspaces/{workspace_id}/tool/clear-pin`

## 4. Required Behaviors

1. managed toolchain 的 install/use/pin/clear-pin 必须是正式 API，不允许前端直接改 `.pafio/tools`、`current` 符号链接或 pin 文件。
2. `clear-pin` 是独立 hosted operation；即使本地 CLI 实现复用 `tool pin --clear`，接口合同也不能折叠掉这个动作。
3. 成功 payload 至少要允许承载 `compiler_version`、`channel`、`install_root`、`install_binary_path` 一类字段，便于 UI 更新 toolchain 状态。
4. 缺少 hosted workspace identity 或 manifest 时必须返回结构化 `blocked`，而不是静默回退到其他 route。

# DependencySourceAdapter

**Purpose:** 冻结依赖源物化接口，让 `Vityo` 可以在不关心 `spio` 内部缓存布局的前提下完成 fetch/vendor 工作流。

**Last updated:** 2026-04-21

## 1. Result Contract

### `DependencySourceCommandResult`

1. `command`
2. `status = blocked | succeeded | failed`
3. `statusMessage`
4. `stdout`
5. `stderr`
6. `payload`
7. `errorPayload`

## 2. Operations

1. `fetchDependencies(projectGraph, locked, offline)`
2. `vendorDependencies(projectGraph, outputPath, locked, offline)`

## 3. Hosted Route Mapping

当 adapter 走 cloud/hosted route 时，固定对接：

1. `POST /api/styio-hosted/v1/workspaces/{workspace_id}/dependencies/fetch`
2. `POST /api/styio-hosted/v1/workspaces/{workspace_id}/dependencies/vendor`

## 4. Required Behaviors

1. 依赖物化必须通过正式命令或正式 hosted API 返回结果，前端不能直接读取 `.spio` 私有缓存目录来推断是否成功。
2. `blocked` 必须明确指出是缺少 hosted workspace identity、manifest，还是平台本身不暴露本地命令。
3. `payload` 至少要允许承载 `packages`、`git_packages`、`registry_packages`、`locked`、`offline`、`output_path` 一类机器字段，UI 不依赖 stderr 文本猜测结果。
4. `vendor` 与 `fetch` 共享同一组失败语义：失败时保留 `errorPayload`，回归测试必须验证结构化错误不会被文本消息吞掉。

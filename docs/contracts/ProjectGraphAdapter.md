# ProjectGraphAdapter

**Purpose:** 冻结 `Vityo` 需要的项目图与包管理状态；前端围绕 canonical project files 和 machine payload 工作，而不是读私有缓存目录。

**Last updated:** 2026-04-21

## 1. Snapshot Contract

### 1.1 `ProjectGraphSnapshot`

1. `id`
2. `title`
3. `kind`
4. `workspaceRoot`
5. `workspaceMembers[]`
6. `manifestPath`
7. `lockfilePath`
8. `toolchainPinPath`
9. `styioConfigPath`
10. `vendorRoot`
11. `buildRoot`
12. `packages[]`
13. `dependencies[]`
14. `targets[]`
15. `editorFiles[]`
16. `toolchain`
17. `lockState`
18. `vendorState`
19. `activeCompiler`
20. `notes[]`

### 1.2 Required Nested Types

1. `ProjectPackageSnapshot`
2. `ProjectDependencySnapshot`
3. `ProjectTargetDescriptor`
4. `ToolchainStatusSnapshot`
5. `CompilerHandshakeSnapshot`
6. `HostedWorkspaceRecordSnapshot`

### 1.3 Hosted Workspace Surface

当 adapter 运行在 hosted/cloud 路由时，`ProjectGraphSnapshot.hostedWorkspace` 也是正式消费面，不是可忽略附带字段。前端依赖：

1. `workspaceId`
2. `schemaVersion`
3. `ownerRef`
4. `status`
5. `entryUrl`
6. `createdAt`
7. `lastActiveAt`
8. `retentionDays`
9. `exportState`
10. `closedAt`
11. `retentionDeadline`
12. `coreFileExportUrl`
13. `coreFileExportExpiresAt`

## 2. Canonical Files

`Vityo` 允许直接围绕这些 canonical files 和目录做 UI：

1. `spio.toml`
2. `spio.lock`
3. `spio-toolchain.toml`
4. `.spio/vendor/`
5. `.spio/build/`
6. `styio.toml`
7. `.styio.toml`

## 3. Non-Negotiable Rules

1. `Vityo` 不通过读 `SPIO_HOME` 私有结构来猜测项目状态。
2. workspace members、targets、toolchain、vendor、lock freshness 最终都必须来自 machine payload 或正式命令。
3. 缺少正式 payload 时，前端可以用 canonical files 做临时推断，但该模式必须清楚标记为 partial。
4. 如果 shell 设置了 `VITYO_STYIO_BIN`，manifest-mode 的 `spio project-graph` / `spio tool status` 读取必须消费同一个 override；前端不能展示一个 `styio` 来源而让 `spio` 实际使用另一个。
5. hosted 模式下，workspace 生命周期与导出状态必须来自 `hostedWorkspace` 记录，不能靠 URL、缓存目录或本地时间推断。

## 4. Adapter Modes

1. `CLI Adapter`
2. `FFI Adapter`
3. `Cloud Adapter`

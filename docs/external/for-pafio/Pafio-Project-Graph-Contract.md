# Pafio Project Graph Contract

**Purpose:** 冻结 `styio-view` 对 `pafio` 项目图 published payload 的 handoff 要求。

**Last updated:** 2026-04-17

## 1. Canonical CLI Form

正式 project graph machine path 使用：

```text
pafio project-graph --json
pafio project-graph --manifest-path <path> --json [--styio-bin <path>]
```

其中基线 spelling 也固定为 `pafio project-graph --manifest-path <path> --json`。

当前 published payload family：

1. `project_graph v1`

## 2. Required Published Keys

`styio-view` 需要 `pafio project-graph --manifest-path <path> --json [--styio-bin <path>]` 至少提供这些 published keys：

1. `workspace_root`
2. `manifest_path`
3. `lockfile_path`
4. `toolchain_pin_path`
5. `workspace_members`
6. `packages`
7. `dependencies`
8. `targets`
9. `lock_state`
10. `vendor_state`
11. `build_root`
12. `toolchain`
13. `active_compiler`
14. `managed_toolchains`
15. `notes`
16. `package_distribution`
17. `source_state`

前端内部投影名可继续保持 camelCase，例如：

1. `workspaceRoot`
2. `manifestPath`
3. `lockfilePath`
4. `toolchainPinPath`
5. `workspaceMembers`
6. `packageDistribution`
7. `sourceState`

但对接真相源仍然是 `pafio` 发布的 snake_case payload。

## 3. Required Behaviors

1. combined root、workspace root、single package 必须能区分。
2. `[lib] / [[bin]] / [[test]]` targets 必须结构化给出。
3. `lock_state` 和 `vendor_state` 必须机器可读，而不是让前端靠文件存在性猜状态。
4. `toolchain`、`active_compiler`、`managed_toolchains` 必须来自 published payload，而不是前端私扫目录。
5. package records 必须带 `publish_enabled`。
6. dependency records 必须带 `source_kind / package / path / git / rev / registry / version / publish_blocking`。
7. `package_distribution` 必须给出 per-package `publish_ready`、`blocking_reasons` 和 aggregated `registry_sources`。
8. `source_state` 必须给出 `pafio_home`、git cache roots、registry cache roots、vendor metadata presence。
9. 项目 pin 指向未安装 compiler 时，必须通过 published payload 返回，而不是让前端把 `active_compiler = null` 当成“没配置”。
10. 如果 shell 设置了 `STYIO_VIEW_STYIO_BIN`，manifest-mode 的 `project-graph` 读取必须消费同一个 `--styio-bin` override，让 `toolchain` / `active_compiler` 和后续执行路径保持一致。

## 4. Frontend Consumption Rules

1. `styio-view` 主线优先消费 `project_graph v1`。
2. canonical files inference 只允许作为 fallback，不再是 project route 的真相源。
3. 一旦 published payload 可用，前端不得继续通过 `pafio.toml`、`pafio.lock`、`pafio-toolchain.toml`、`.pafio/vendor/`、`.pafio/build/` 重建 project graph 真相。
4. 如果 `pafio` 已广告 `project_graph v1` 但 `project-graph --json` 退出失败、返回非法 JSON 或 payload 解析失败，`styio-view` 必须把它显示为 published contract failure，并把 adapter capability 降到 `partial`；不能静默表现得像合同正常。

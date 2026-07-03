# Pafio Toolchain And Registry State

**Purpose:** 冻结 `styio-view` 对 `pafio` toolchain、registry 和 package 状态的 handoff 要求。

**Last updated:** 2026-04-17

## 1. Toolchain State

当前已发布的上游入口：

1. `pafio machine-info --json`
2. `pafio project-graph --json`
3. `pafio project-graph --manifest-path <path> --json`
4. `pafio project-graph --json [--manifest-path <path>] [--styio-bin <path>]`
5. `pafio tool status --json [--manifest-path <path>] [--styio-bin <path>]`

当前 `toolchain_state v1` 至少包含：

1. `toolchain`
2. `project_pin`
3. `active_compiler`
4. `current_compiler`
5. `managed_toolchains`
6. `notes`

当前 `styio-view` 集成规则：

1. 优先消费 `pafio tool status --json` 的 published payload
2. `project-graph` 可继续提供 `toolchain`、`active_compiler`、`managed_toolchains` 的冗余镜像，但 `tool status` 是环境真相源
3. 即使 compiler 不在当前 compile-plan execution path 上，只要 `machine-info` 可探测，`view` 也应显示该 compiler，并由 feature flags / supported contracts 决定是否 blocked
4. 项目 pin 缺失安装时，必须通过 published payload 返回，而不是让前端自己扫目录猜测
5. 如果 shell 设置了 `STYIO_VIEW_STYIO_BIN` 且当前是 manifest-mode project route，`styio-view` 必须把同一个 `--styio-bin` override 传给 `project-graph` 和 `tool status`，避免 UI 展示的 compiler 来源与 `pafio` 实际消费路径分裂

当前本地环境操作基础也已经落地：

1. `styio-view` 本地 adapter 通过 `pafio --json tool install --styio-bin <path>`、`pafio --json tool use --version <compiler-version> [--channel <channel>]`、`pafio --json tool pin (--version <compiler-version> [--channel <channel>] | --clear) [--manifest-path <path>]` 执行 toolchain lifecycle
2. toolchain 命令成功后，shell 必须立即 reload `project-graph` 与 `tool status` 衍生状态
3. 页面层之后只负责触发这些 adapter，不再自己拼命令或重建刷新逻辑

## 2. Registry And Package State

至少需要：

1. package metadata
2. registry source status
3. publish preflight result
4. fetch/vendor result
5. pack/publish result summary

当前 `project_graph v1` 已发布的最小 deployment handoff：

1. package records 上的 `publish_enabled`
2. dependency records 上的 `source_kind / package / path / git / rev / registry / version / publish_blocking`
3. `package_distribution`：
   - per-package `publish_ready`
   - `blocking_reasons`
   - runtime/dev dependency source breakdown
   - aggregated `registry_sources`
4. `source_state`：
   - `pafio_home`
   - declared git / registry dependency counts
   - git cache `repos_root / checkouts_root`
   - registry cache `cache_root / index_root / blob_root / checkout_root`
   - project-local vendor `metadata_path / metadata_present / git_snapshots`

当前本地部署基础也已经落地：

1. `styio-view` 本地 adapter 通过 `pafio --json pack --manifest-path <path>` 执行本地 source archive 打包
2. `styio-view` 本地 adapter 通过 `pafio --json publish --manifest-path <path> --dry-run` 执行 publish preflight
3. 本地 registry publish 通过 `pafio --json publish --manifest-path <path> --registry <path-or-url>` 执行，页面层只消费结果与阻塞原因
4. shell 必须保留最近一次 deployment command 的 payload，用于后续页面显示 `package`、`archive_path` 和 publish 阻塞信息

当前本地 source materialization 基础也已经落地：

1. `styio-view` 本地 adapter 通过 `pafio --json fetch --manifest-path <path>` 执行依赖源 materialization
2. `styio-view` 本地 adapter 通过 `pafio --json vendor --manifest-path <path>` 执行项目级 vendoring
3. `fetch/vendor` 成功后，shell 必须立即 reload `project-graph`，让 `source_state`、`vendor_state` 和 package graph 同步刷新

## 3. Rules

1. `styio-view` 不通过私有目录推断 toolchain 或 registry 状态。
2. publish preflight 必须可单独消费，用于在 UI 中提前显示阻塞项。
3. package/registry contract 最终也必须能落到 `CLI / FFI / Cloud` 三类 adapter 之一。
4. 如果 `pafio` 已广告 `toolchain_state v1` 但 `tool status --json` 退出失败、返回非法 JSON 或 payload 解析失败，`styio-view` 必须把它显示为 published contract failure，并把 project/toolchain 能力降到 `partial`；不能静默回退得像状态合同正常。

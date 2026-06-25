# Current State

**Purpose:** 提供 `Vityo` 当前治理和产品主线的压缩入口；优先给出当前文件治理状态、主线推进状态和下一个治理 checkpoint。

**Last updated:** 2026-06-25

## Summary

1. `Vityo` 已补齐 `archive/rollups`、docs index/audit/lifecycle，并把它们接进了现有 hygiene gate。
2. 根 `.gitignore` 与 `scripts/repo-hygiene-gate.py` 现在已经对齐 shared file-governance baseline，`docs/**` 与 `frontend/vityo_app/test/**` 的 temp/build 风格 tracked fixture 也有显式 negate 规则。
3. 当前活跃治理 checkpoint 是 `FG4`：维持这套 baseline，不让 `view` 再退回人工维护或 repo-specific 例外。
4. 产品主线仍以 adapter、project/execution/environment shell 和上游 contract 消费为先，页面润色继续后置。
5. `runtime_events` published family 已从 compile-plan artifact 贯通到 `view` 的 runtime surface、debug console 和 shell debug log；surface / console 现在共享同一套 replay family、payload、route trace、graph 和 debug lane 派生摘要，surface 侧已有 family-based lane summary、最小 execution graph / route checkpoint / node-detail / node-relation / node-timeline / edge-timeline summary、以及 `thread / unit.test / log` debug lanes 的 lane trace / filter token / focused timeline detail，当前已稳定消费 `compile.* / run.* / thread.* / unit.* / unit.test.* / state.* / transition.fired / log.emitted / diagnostic.emitted`。
6. 主线 shell 现在已把 `run / fetch-vendor / environment / deploy` 四条项目 workflow 收到同一块 shell-owned 状态面里：`Execution / Dependencies / Environment / Deployment` 共用统一命令流、blocked 判定和最近结果摘要，workspace sidebar 的 `Project Workflow` 卡会直接显示这四条 lane 的状态、阻塞项和动作入口。
7. `Vityo` 现在已有一条真正的 sample workflow smoke 路径：`Use Compiler -> Fetch -> Vendor -> Run -> Preflight` 可在桌面 fixture 里完整走通，并验证四条 workflow lane 会一起收口成成功态，而不只是各自零散单测通过。
8. 三仓现在还有一条黑盒 cross-repo sample workflow gate：`styio-spio/scripts/ecosystem-sample-workflow-gate.py` 已经覆盖 managed toolchain switch、vendored offline、registry-hosted source，以及多包 workspace 的显式 `--package` 选择与歧义保护；`Vityo` 侧则通过本仓 wrapper 直接指向同一条权威 gate。
9. `Vityo` 已经接入 repository-local hosted control plane，`project graph / toolchain / dependency / execution / deployment` 不再停留在 preview stub；权威 `ecosystem-product-gate.py` 现已同时证明 desktop local CLI-owned lane 与 `iOS cloud-only`、`Web hosted-only`、`Android cloud fallback` 三条 hosted/cloud lane 都能完成 `install/use/pin/fetch/vendor/pack/run/test/preflight`，且 managed toolchain 能在 local 和 hosted 两条路线上完成“安装 alternate -> 切换 -> 回切 -> 再执行 workflow”的真实环境切换闭环；同一条 gate 也已经覆盖 desktop local 与 hosted 多包 workspace 下的 package 选择、执行路由和 publish 歧义保护。desktop local 产品线现在还额外证明了 filesystem registry 分发闭环：发布者 library 工作区在 reopen 后会先通过 `Execution` lane 完成真实 build，再通过 `Deployment` lane 真实 publish 到本地 registry、在 republish 同一 package identity 时得到结构化冲突失败；消费者工作区则通过同一条本地产品路由分别验证已发布 registry 包的 `fetch -> run` 成功路径和缺失 registry package identity 的结构化 `fetch` 失败。hosted/cloud 产品线也已经具备同构的 registry 分发能力，在三条 hosted route 上先 build library package，再完成 publish/consume/republish conflict/missing-package fetch failure。
10. 产品 lane 现在不只验证 happy path：desktop local 与 hosted 两条路线都已经把编译失败、依赖获取失败、publish preflight 失败收进真实 product gate。编译失败会把结构化 diagnostics 和 `compile.failed` runtime events 回流到 `Execution` lane；依赖获取失败会把结构化 error payload 回流到 `Dependencies` lane；publish preflight 失败会把结构化 error payload 回流到 `Deployment` lane，不再退化成笼统的 blocked/opaque 失败。成功态的 `pack` 与 `publish --dry-run` 也都要求保留真实 `archive_path`，并在产品 gate 中验证 archive 文件仍然存在；desktop local 还额外证明了 vendored/offline 恢复路径，在清空临时 `SPIO_HOME` 之后重新安装并 re-pin managed compiler，仍然可以通过 `fetch --offline` 和 CLI-owned execution lane 继续运行。 
11. `guard-repository-hygiene` 当前已修复 UTF-8 文本采样误判，不再因为多字节字符恰好落在 8 KiB 采样边界上，把合法 Markdown 文档错误归类成 binary；这条门禁现在可以作为受保护分支和上游主仓的真实提交检查继续使用。
12. 仓库级开发环境入口现在已经把容器、Linux/macOS/Windows 宿主机安装、Android profile、多 Apple profile 和真实设备验证收敛到同一份 `BUILD-AND-DEV-ENV.md`，根 README 只保留一跳入口，不再维护第二套平行说明。
13. 上述 product gate (points 7-10) 均需要设置 `VITYO_PRODUCT_GATE=1` 和对应的外部 fixture（Styio/Spio 可执行文件、hosted control plane endpoint）才会执行；默认 CI 不会运行这些 product workflow gate，仅验证本地可运行的单元测试和 widget 测试。
14. 已知文档偏差（2026-06-25 审计确认）：`Vityo-Implementation-Gaps.md` 中 Remote/browser/virtual providers 与 Cache Contract 此前标记为 Closed，但实际上 `HostedWorkspaceFileSystemProvider` 未实现、`CacheStore<K,V>` 通用接口未发布、缓存 Level 2 持久化未实现——已降级为 Partially implemented。

## Read Order

1. `NEXT-STAGE-GAP-LEDGER.md`
2. `../specs/DOCUMENTATION-POLICY.md`
3. `../design/Vityo-Implementation-Gaps.md`
4. `../contracts/RuntimeEventAdapter.md`
5. `../specs/DOCUMENTATION-POLICY.md`
6. `../teams/DOCS-DELIVERY-RUNBOOK.md`

## Recovery Baseline

```bash
python3 scripts/docs-lifecycle.py refresh
python3 scripts/docs-index.py --write
python3 scripts/docs-audit.py
python3 scripts/repo-hygiene-gate.py --mode tracked
```

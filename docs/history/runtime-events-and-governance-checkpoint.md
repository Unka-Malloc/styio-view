# Runtime Events And Governance Checkpoint

**Purpose:** 记录 2026-04-17 在 `Vityo` 侧确认的主线缺陷、维护风险与 `FG2` 文件治理补齐 checkpoint，作为执行层和文档治理的共同恢复入口。

**Last updated:** 2026-04-17

**Date:** 2026-04-17

## 摘要

1. 本轮三仓同步后，`Vityo` 的主要问题集中在执行适配层和 published payload 消费层。
2. 这些问题不会推翻已完成的 adapter 接线，但它们已经进入主线路径，需要在页面工作之前先修复基础语义。

## 当前风险

1. `ExecutionAdapter` 现在会把未保存文档直接写回真实文件，再在执行结束后恢复旧文本；如果 IDE 崩溃、进程被中断，或者执行期间外部工具改了同一文件，恢复逻辑可能覆盖真实新变更。
2. 非当前文件的结构化 diagnostics 仍会在 IDE 里退化成当前文档内的 `0..0` 伪位置，只是把真实文件路径拼进 message；多文件项目错误仍然不能正确定位。
3. `pafio` 已发布的 `project-graph` / `tool status` payload 若解析失败，shell 会静默回退到本地 canonical file inference；这会把真实的跨仓 contract 回归伪装成“部分可用”。
4. 根 `.gitignore` 现已统一忽略 `tmp/`、`build-*`、`*.tmp`、`*.log` 与常见 cache 目录；这有利于清理，但未来若要追踪 temp/build 风格的 repro 资产，需要显式反忽略。

## 当前证据

1. 实际文件 staging / restore 路径位于 [../frontend/vityo_app/lib/src/integration/execution_adapter_io.dart](../frontend/vityo_app/lib/src/integration/execution_adapter_io.dart)。
2. 多文件 diagnostics range 丢失仍位于同一文件的 payload 解析路径中。
3. published payload 失败后回退到 canonical inference 的逻辑位于 [../frontend/vityo_app/lib/src/integration/project_graph_adapter_io.dart](../frontend/vityo_app/lib/src/integration/project_graph_adapter_io.dart)。

## 下一步

1. 先修 `ExecutionAdapter` 的真实文件 staging 语义，避免主线路径继续覆盖磁盘内容。
2. 再修跨文件 diagnostics 的 range / file identity 承载方式，保证 IDE 不再把其它文件的问题压到当前文档。
3. 把 published payload 解析失败从“静默 fallback”收紧成可见的 blocked/partial contract 状态。
4. 后续若要提交 temp/build 风格的 repro 工件，同批增加显式 negate rule。

## FG2 文件治理 Checkpoint

### 当前状态

1. `Vityo` 已补齐 `docs/archive/` 与 `docs/rollups/` 最小骨架。
2. 新增了 `scripts/docs-index.py`、`scripts/docs-lifecycle.py`、`scripts/docs-audit.py`，并把它们接入 `scripts/check_repo_hygiene.py`。
3. `DOCUMENTATION-POLICY.md` 和 Docs / Delivery runbook 已开始把 docs 自动化视为正式门禁，而不是人工约定。

### 恢复命令

```bash
python3 scripts/docs-lifecycle.py refresh
python3 scripts/docs-index.py --write
python3 scripts/docs-audit.py
python3 scripts/check_repo_hygiene.py
```

### 风险

1. 这轮建立的是治理骨架，不是一次性重写所有旧文档。
2. 如果后续又回到手工维护 `INDEX.md` 而不跑脚本，`check_repo_hygiene.py` 现在会直接把它拦下。

## FG3 文件治理 Checkpoint

### 当前状态

1. 根 `.gitignore` 已冻结 shared baseline pattern，并补齐 `docs/**` 与 `frontend/vityo_app/test/**` 的 temp/build 风格 fixture negate 规则。
2. `scripts/check_repo_hygiene.py` 已升级为正式 file-governance gate：除了构建垃圾和意外二进制，还会检查 required `.gitignore` pattern 与关键治理文档接线。
3. `DOCUMENTATION-POLICY.md` 和 Docs / Delivery runbook 已把这套 baseline 写成显式规则，不再靠口头约定。

### 恢复命令

```bash
python3 scripts/docs-audit.py
python3 scripts/check_repo_hygiene.py
```

### 风险

1. 目前冻结的显式 negate 只覆盖 `docs/**` 与 `frontend/vityo_app/test/**`；未来若新增其它 tracked repro 根，还需要继续扩 gate。
2. 这轮仍然只收文件治理，不替代前端页面与产品交互层的后续收口。

## Runtime Events Surface Checkpoint

### 当前状态

1. `runtime_events` published family 已从 `styio-pafio` workflow payload 进入 `Vityo` 的 `ExecutionSession` 生命周期。
2. shell state 现在会保留最近一次运行会话的 runtime event replay，并把 session-level 摘要写进 debug log。
3. runtime surface 与 debug console 已不再只显示占位文案，而是会消费并展示已发布的 runtime replay。

### 当前证据

1. runtime event replay 注册与回放位于 [../frontend/vityo_app/lib/src/integration/runtime_event_adapter.dart](../frontend/vityo_app/lib/src/integration/runtime_event_adapter.dart)。
2. workflow payload 到 runtime replay 的解析与登记位于 [../frontend/vityo_app/lib/src/integration/execution_adapter_io.dart](../frontend/vityo_app/lib/src/integration/execution_adapter_io.dart)。
3. surface 消费路径位于 [../frontend/vityo_app/lib/src/runtime/runtime_surface.dart](../frontend/vityo_app/lib/src/runtime/runtime_surface.dart) 与 [../frontend/vityo_app/lib/src/runtime/debug_console_surface.dart](../frontend/vityo_app/lib/src/runtime/debug_console_surface.dart)。

### 下一步

1. 当前 replay 已升级成 family-based runtime lanes、replay window 和带时间戳的 debug console 摘要。
2. 当前已稳定消费 `compile.* / run.* / thread.* / unit.* / unit.test.* / state.* / transition.fired / log.emitted / diagnostic.emitted`。
3. runtime surface 现已新增最小 execution graph summary，可从现有 runtime replay 派生 route nodes、transition edges 和 observed nodes。
4. runtime surface 与 debug console 现已共用同一套 replay family、payload 和 graph 派生逻辑，不再各自维护一套摘要规则。
5. runtime surface 现已进一步发布 route trace 与 route checkpoint 摘要，debug console 也能显示同一条执行路径。
6. runtime surface 现已把 `thread / unit.test / log` 三组事件提升成 shared debug lanes，debug console 也会显示同一套 debug digest。
7. shared debug lanes 现已进一步携带 lane trace 与 checkpoint detail，不再只有 lane title 和 digest。
8. shared debug lanes 现已进一步携带 lane filter token 与 focused timeline detail，runtime surface 和 debug console 不再只给 digest，而是可以明确表达 lane-focused filter 语义。
9. shared execution graph 现已进一步携带 node-detail filter 语义，runtime surface 与 debug console 会直接消费同一套 node label / source event / detail token，而不是各自拼 graph 细节。
10. shared execution graph 现已进一步携带 node timeline 语义，runtime surface 与 debug console 会同时显示 node-focused timeline，而不是只有 node filter 摘要。
11. shared execution graph 现已进一步携带 edge timeline 语义，runtime surface 与 debug console 会直接消费同一套 `transition.fired` edge filter / timeline，而不只是显示边字符串。
12. shared execution graph 现已进一步携带 node relation 语义，phase node 会明确暴露 inbound/outbound edge 关系，runtime surface 与 debug console 不再各自猜邻接关系。
13. `Vityo` shell 现已把 `Use Compiler / Pin Compiler / Clear Pin / Pack / Preflight` 接回统一命令流和 sidebar 主操作面，不再只停留在 adapter API。
14. workspace sidebar 的主线操作面现已升级成统一的 `Project Workflow`：`Execution / Dependencies / Environment / Deployment` 四条 lane 共用同一套 shell state、blocked 判定和最近结果摘要，不再把执行、依赖、环境、部署结果散落在 command strip、debug log 和 adapter 返回值里。
15. `Vityo` smoke test 现已新增 live mainline fixture，可从 sidebar 直接完成 `Use Compiler -> Fetch -> Vendor -> Run -> Preflight`，并验证 `Execution / Dependencies / Environment / Deployment` 四条 workflow lane 一起收口成成功态。
16. 三仓现已新增权威 `ecosystem-sample-workflow-gate.py`：它会对真实 `styio + pafio` 二进制执行 `check/fetch/vendor/run/test/publish --dry-run`，`view` 侧通过本仓 wrapper 直接复用同一条 gate。
17. 权威 `ecosystem-sample-workflow-gate.py` 现已从单包 happy path 扩成双场景矩阵：除了原来的 `check/fetch/vendor/run/test/publish --dry-run`，还会覆盖多包 workspace 下 `run/test/publish` 的显式 `--package` 选择与歧义保护；`view` 侧继续只通过 wrapper 复用这条权威 gate。
18. 三仓权威 `ecosystem-sample-workflow-gate.py` 现已进一步覆盖 managed toolchain switch：真实 `styio` 安装后可切到第二个 managed compiler 身份，再切回真实 compiler，并继续完成 workflow。
19. 三仓权威 `ecosystem-sample-workflow-gate.py` 现已进一步覆盖 registry-hosted source：本地 filesystem registry 可完成 `publish -> republish conflict -> fetch -> project-graph -> check -> run`。
20. 当前主线下一步不再是继续细抠 runtime graph，而是沿这条 sample workflow matrix 扩到真正的 IDE 端到端产品验收和更远端的 toolchain/distribution 交付。

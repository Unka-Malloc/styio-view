# Vityo Documentation Policy

**Purpose:** 定义 `Vityo` 的文档目录、单一事实来源、联动更新规则与最小维护要求；产品行为与系统边界分别以 `docs/design/` 中的权威文档为准。

**Last updated:** 2026-05-16

## 0. 文档维护准则

### 0.1 Top-Level `Purpose`

每个 `docs/**/*.md` 文件必须在标题附近给出顶层 `Purpose:` 行，说明该文档何时使用、拥有何种边界。

### 0.2 最小重复原则

1. 同一主题的长篇事实解释只保留一个 SSOT。
2. 其它文档只保留摘要和链接，不复写完整规则。
3. 如同一主题在三处及以上文档出现实质性重复，必须指定唯一权威并删改重复内容。

### 0.3 常见 SSOT 速查

| 主题 | 权威文档 | 其它文档应 |
|------|----------|------------|
| 产品定位、术语、不变量、功能域 | `../design/Vityo-Product-Spec.md` | 链接或一段摘要 |
| 系统层次、数据流、执行后端 | `../design/Vityo-System-Architecture.md` | 链接 |
| 已完成实施成果的设计沉淀 | `../design/Vityo-Delivered-Design-Baseline.md` | 链接 |
| 活跃实现、集成、验证和上游合同缺口 | `../design/Vityo-Implementation-Gaps.md` | 链接 |
| 仓库职责边界 | `REPOSITORY-MAP.md` | 链接 |
| 文档目录与更新规则 | `DOCUMENTATION-POLICY.md` | 链接 |
| 人机协作、变更批处理要求 | `CONTRIBUTOR-AND-AGENT-SPEC.md` | 链接 |
| 团队 ownership、review routing、handoff | `../teams/COORDINATION-RUNBOOK.md` | 链接 |
| 三仓统一交付总纲 | 上游 `styio-nightly` canonical plan | 本仓不再保留本地 plan 镜像 |
| 三仓文件治理对齐 | 上游 `styio-nightly` canonical governance plan | 本仓不再保留本地 plan 镜像 |
| 第三方依赖清单 | `THIRD-PARTY.md` | 与实现同步更新 |
| `styio` 对接边界与接口合同 | `../external/for-styio/` | 链接 |
| `spio` 对接边界与接口合同 | `../external/for-spio/` | 链接 |
| 冻结里程碑与任务清单 | `../milestones/INITIAL-IMPLEMENTATION-MILESTONES.md` | 链接 |
| 测试与验收映射 | `../assets/workflow/TEST-CATALOG.md` | 链接 |
| 架构裁决 | `../adr/` | 只保留决策摘要 |
| 未决风险与冲突 | `../review/Logic-Conflicts.md` | 链接 |

### 0.4 文档状态

1. `docs/design/` 是产品、系统、已交付设计基线和活跃缺口登记的 SSOT。
2. `docs/plans/` 已退役；本仓不再用本地计划文档承载 Vityo 实施跟踪。
3. `docs/rollups/` 负责压缩当前状态和活跃缺口，不替代 owner 文档。
4. `docs/history/` 负责活跃恢复记录；原始历史一旦退役，应迁入 `docs/archive/`。
5. `docs/archive/` 负责归档 provenance 与 lifecycle 元数据，不用来隐藏仍活跃的 owner 文档。
6. `docs/milestones/` 按功能主题保存冻结目标和任务清单；日期和版本号只能作为状态字段出现在正文，不能作为目录、入口或任务身份。
7. `docs/review/` 中的未决问题一旦裁决，应迁入 ADR 并在 review 文档中回填链接。

## 1. 目录职责

| 路径 | 存放内容 |
|------|----------|
| `docs/design/` | 产品规格、系统架构、核心术语、不变量、已交付设计基线、活跃缺口登记 |
| `docs/specs/` | 文档策略、仓库边界、协作规范、依赖清单 |
| `docs/milestones/` | 冻结的阶段目标、任务表与门禁 |
| `docs/adr/` | 架构决策记录 |
| `docs/review/` | 风险、冲突、待裁决问题 |
| `docs/assets/` | 测试目录、复用交付资产 |
| `docs/rollups/` | 当前状态摘要与活跃 gap ledger |
| `docs/history/` | 按主题命名的恢复记录与历史信息 |
| `docs/archive/` | 已归档 provenance 与 lifecycle 元数据 |
| `docs/external/for-styio/` | 与上游 `styio` 的接口、责任边界与对接清单 |
| `docs/external/for-spio/` | 与上游 `spio` 的接口、责任边界与对接清单 |
| `docs/teams/` | 团队 runbook、ownership 路由与 handoff 入口 |

## 2. 联动更新规则

1. 变更产品语义或交互规则时，至少检查：
   - `design/Vityo-Product-Spec.md`
   - `design/Vityo-System-Architecture.md`
   - `design/Vityo-Delivered-Design-Baseline.md`
   - `design/Vityo-Implementation-Gaps.md`
   - 相关 ADR
   - 对应里程碑文件
   - `assets/workflow/TEST-CATALOG.md`
2. 新增或替换依赖时，必须同步更新 `THIRD-PARTY.md`。
3. 新增一个长期架构边界时，必须新增或更新设计文档，必要时新增 ADR，不能只写在缺口登记里。
4. 新增一个重要风险但尚未裁决时，先写入 `review/Logic-Conflicts.md`。
5. 若一次变更改变了维护责任、review 触发条件或恢复路径，必须同步更新受影响的 `../teams/*.md` 与 `../teams/COORDINATION-RUNBOOK.md`。
6. 若一次变更改动了三仓共同里程碑、repo exit、checkpoint ID 或跨仓 cutover 条件，本仓只更新相关 external handoff、设计基线或缺口登记；跨仓计划的权威副本留在上游 canonical 仓库。
7. 若一次变更改动了 docs tree、索引生成规则、archive/rollup lifecycle、ignore-policy 或 fixture 反忽略规则，更新本文件、`../teams/COORDINATION-RUNBOOK.md` 和受影响目录入口。
8. docs tree 变化后，必须运行 `python3 scripts/docs-lifecycle.py refresh`、`python3 scripts/docs-index.py --write`、`python3 scripts/docs-audit.py`。
9. 根 `.gitignore` 若扩展 temp/build/log/cache 忽略规则，必须同批补 `docs/**` 与 `frontend/vityo_app/test/**` 的显式 negate 规则，并让 `python3 scripts/repo-hygiene-gate.py --mode tracked` 通过。

## 3. 文件命名规则

1. 设计级文档使用稳定主题名，优先 `Vityo-*.md`。
2. 规范文件使用稳定全大写或描述性短横线命名。
3. 不再新增本地 `docs/plans/` 计划文件；未完成项进入 `docs/design/Vityo-Implementation-Gaps.md`。
4. 历史、审计和 rollup 文件使用稳定主题名；日期只能写入 `Date`、`Last updated` 或正文状态说明。
5. ADR 文件严格使用 `ADR-XXXX-<slug>.md`。
6. 里程碑文件使用稳定功能主题名；不得使用日期目录、版本号目录、阶段编号前缀或 `00-` 入口文件组织里程碑。

## 4. 当前最低维护门禁

1. 新文档必须带 `Purpose` 与 `Last updated`。
2. 每次结构变更必须更新对应目录的 `INDEX.md`。
3. 产品语义变化必须能在设计基线、缺口登记、里程碑和测试目录中找到映射。
4. 任何实现如果违反已接受 ADR，必须先新增替代 ADR 或回滚计划。
5. 维护边界变化必须能在 `docs/teams/` 中找到对应更新。
6. `archive/rollups` 和 docs 自动化脚本必须保持可执行，不能退回人工维护模式。
7. `scripts/repo-hygiene-gate.py` 必须持续校验 shared `.gitignore` baseline、fixture negate 规则和关键治理文档接线，不能退回“只查构建垃圾”的弱模式。

# Vityo Contributor And Agent Spec

**Purpose:** 定义人类贡献者与代码 agent 在 `Vityo` 仓库中的协作规则、联动更新要求与交付边界。

**Last updated:** 2026-06-28

## 1. 基本原则

1. `Vityo` 是产品仓，不是临时实验笔记仓。
2. 任何长期保留的交互、架构或平台策略，都必须有对应文档落点。
3. 源码文本始终是编辑器中的 canonical source；视觉替换不能静默改写用户源代码。
4. 任何内部 UI 组件都不得超过外部容器；若空间不足，必须通过 `min-width: 0`、局部滚动、换行或重排解决，不能让子组件溢出父容器。
5. Documentation is English by default. Chinese prose is allowed only in documents explicitly scoped as Chinese localization, Chinese translation, or Chinese user-facing product/marketing copy, such as a localized `README.md` or product landing page.

## 2. 变更分级

| 变更类型 | 必须同步更新 |
|----------|--------------|
| 产品交互变化 | 产品规格、相关里程碑、测试目录 |
| 系统边界变化 | 系统架构、ADR、相关计划 |
| 平台执行策略变化 | 产品规格、系统架构、ADR、风险文档 |
| 模块 manifest / lifecycle 变化 | 系统架构、ADR、里程碑、测试目录 |
| adapter / schema 合同变化 | `docs/specs/` 对应 schema、系统架构、测试目录 |
| 新依赖引入 | 第三方依赖清单、计划、必要 ADR |
| 新里程碑或阶段目标 | 里程碑索引、计划、测试目录 |

## 3. Agent 工作规则

1. Agent 不得把“显示层替换”误写成“源码层替换”。
2. Agent 修改移动端执行路径前，必须核对平台约束，尤其是 iOS 代码执行限制。
3. Agent 新增架构边界时，必须写 ADR，不得只更新 README。
4. Agent 若发现既有计划与产品规格冲突，应先指出冲突，再修改文档，而不是只写代码。
5. Agent 若新增模块，必须同时声明 manifest、capability matrix 和卸载/更新语义。
6. Agent 若修改 adapter 或 hosted workspace 合同，必须同步更新对应 schema 文档。
7. Agent 新增或调整 UI 面板、卡片、下拉或工具条后，必须检查内部组件是否超出外部容器，尤其是侧边栏、弹窗和移动端窄视口。
8. Agent 调整默认字体、主题、调色盘或图标系统前，必须优先确认默认方案来自开源、低争议来源；不得把专有商业字体作为默认值，也不得直接把第三方产品品牌名作为默认主题标签。
9. Agent 修改 `prototype/editor.html` 这条手写 Web IDE 主线前，应先遵守 [HANDWRITTEN-WEB-IDE-ENGINEERING-HANDBOOK.md](./HANDWRITTEN-WEB-IDE-ENGINEERING-HANDBOOK.md) 中的分层、渲染与工作流约束。
10. Agent 若调整团队 owned surface、review 路由或 handoff 路径，必须同步更新受影响的 `docs/teams/*.md` 与 `docs/teams/COORDINATION-RUNBOOK.md`。
11. Agent 开始修改前必须查看 `git status --short`，把无关 dirty files 视为并发改动，不得回滚、覆盖或重排他人工作。
12. Agent 若修改 `view_ide` / `view_render` 边界、legacy compatibility façade、sandbox/security、performance gate 或 release gate，必须同步更新 `docs/governance/` 和本地开发入口。
13. Agent must write new documentation prose in English unless the target file's `Purpose` explicitly declares a Chinese-localized or Chinese user-facing product/marketing scope. When materially editing legacy Chinese prose in non-localized owner docs, convert the touched passage to English instead of extending it.

## 4. 人类审阅重点

1. 交互语义是否与 `styio` 语言本体冲突。
2. 是否错误假设了 iOS 可直接支持任意本地 JIT。
3. 是否把桌面交互直接照搬到移动端。
4. 是否把 AI 面板做成“外挂聊天框”，而不是 IDE 内建能力。
5. 是否错误地在 iOS 上暴露了本地编译模块入口。
6. Whether new or materially edited documentation follows the English-by-default rule and has an explicit localization reason for any Chinese prose.

## 5. 批处理交付要求

一批结构性变更完成时，应至少包含：

1. 对应的设计或规格更新
2. 必要的 ADR
3. 对应的里程碑任务状态调整
4. 至少一条测试或验收映射
5. 若维护边界发生变化，对应 team runbook 更新
6. 若属于 docs tree 变化，刷新 generated `INDEX.md`
7. 若属于 release、security、compatibility 或 performance gate 变化，更新 PR checklist 或 release checklist

## 6. 团队协作入口

1. `docs/teams/COORDINATION-RUNBOOK.md` 负责团队 ownership、review routing 和 cutover 路径。
2. 各 `docs/teams/*-RUNBOOK.md` 只提供 daily-work 入口，不重写产品规格、合同或上游对接 SSOT。

## 7. 当前明确禁止项

1. 把 `Vityo` 退化为纯 Web 壳或传统 IDE 皮肤层。
2. 假设所有平台共享完全一致的交互模型。
3. 在未写平台策略文档前承诺 iOS 任意本地 JIT。
4. 在没有类型系统或语言服务支撑时，把 pipeline 选择做成纯字符串菜单。
5. 在未定义 manifest 和 lifecycle 前宣称模块支持热更新。

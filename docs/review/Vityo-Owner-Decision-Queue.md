# Vityo Owner Decision Queue

**Purpose:** 集中记录 `vityo-nightly` 中真正需要产品所有者裁决的高杠杆问题；一次回答应同时约束多个需求、实现节点和验收口径。

**Last updated:** 2026-07-20

**Status:** Resolved — 3/3 个所有者问题已裁决

## 1. 使用规则

1. 只有跨越至少三个功能节点、难以低成本反转、或需要产品/发布授权的问题才进入本清单。
2. 每个问题给出一个完整的推荐策略包。回复“采用推荐方案”即可，不再拆问包内细节。
3. 可逆的工程细节由实现者依据现有架构、测试和安全约束自行决定，不向产品所有者逐项请示。
4. 一个问题裁决后，先记录答案和影响范围，再询问下一个问题。
5. 已接受且具有长期架构意义的结论应迁入 `docs/adr/`；本文件保留简短结果和链接。

## 2. 决策总览

| 顺序 | ID | 决策 | 当前状态 | 一次覆盖的主要范围 |
|---|---|---|---|---|
| 1 | VOD-001 | 下一可验收里程碑的边界 | **已裁决：A** | REQ-001..009 的阻塞关系、11 个待实现节点的优先级、桌面/移动/Web 范围、PTY 是否属于桌面核心 |
| 2 | VOD-002 | 上游 Styio/Pafio 未就绪时怎样定义“完成” | **已裁决：A** | 编译器事实、真实执行 receipts、项目图 payload、产品门禁、最终验收声明 |
| 3 | VOD-003 | Nightly 的分发可信度等级 | **已裁决：A + 平台独立发布** | 三桌面平台安装包、签名/公证、更新通道、CI 发布证据与凭据需求 |

除以上三项外，当前没有发现必须由产品所有者逐条裁决、才能继续推进的产品问题。

## 3. VOD-001 — 下一可验收里程碑的边界

### 问题

是否把下一里程碑定义为“可信桌面 IDE 闭环”，而不是要求当前
`vityo-product-delivery` 的 REQ-001..REQ-009 全部在同一个里程碑内完成？

### A. 可信桌面 IDE 闭环（推荐）

本里程碑必须完成：

- Linux、Windows、macOS 上真实的编辑 → 保存 → 编译 → 运行 → 诊断/receipt 闭环；
- 编译器事实优先的语言能力，以及事实缺失时明确标注且不做危险跨文件修改的降级路径；
- 权威项目图 payload、带来源可信度的回退、类型化且有界的运行事件；
- `ShellRuntimeModel` 拆分、进程生命周期加固，以及三桌面平台真实 PTY；
- fail-closed 产品门禁和可安装的 Nightly 桌面产物；
- Android、iOS、Web 只需显示真实能力状态，不作为本里程碑的设备级交付目标。

以下能力不阻塞该里程碑，分别作为后续独立闭环：生产级 AI provider、主题/profile
持久化、模块包下载/激活/回滚/回收。其现有骨架可以保留，但不得被描述为已交付。

这会把 REQ-001、REQ-002、REQ-003、REQ-008、REQ-009 和 REQ-007 的桌面子集设为当前
阻塞路径；REQ-004、REQ-005、REQ-006 退出当前最终验收的阻塞路径。

### B. 全量产品交付

保持现有计划含义：桌面核心、生产级 AI、主题持久化、完整模块生命周期、三平台包装和
全量产品门禁全部完成后，才产生下一次可验收里程碑。

代价是一个里程碑同时跨越语言服务、执行、运行时、AI、设置、模块、平台包装和 CI，
验收周期更长，并持续受多个上游合同和发布基础设施共同阻塞。

### 推荐理由

当前证据显示，用户信任的最短闭环仍被真实执行 receipts、编译器事实、项目图 payload、
进程生命周期和产品门禁共同约束。先完成可信桌面闭环，可以产生一个独立可验收产品，
同时符合 `Vityo-Product-Spec.md` 的“桌面优先”范围；AI、主题和模块再按能力分别闭环，
避免一次改动横跨多个不同场景。

### 裁决记录

- **Decision:** Accepted A — 下一里程碑采用“可信桌面 IDE 闭环”。
- **Answered at:** 2026-07-20
- **Rationale:** 先形成独立可验收的桌面核心；生产级 AI、主题持久化和完整模块生命周期分别后续闭环，不共同阻塞当前里程碑。
- **Plan impact applied:** Decision recorded; product-plan graph will be reconciled after the owner-decision round.

## 4. VOD-002 — 上游未就绪时怎样定义“完成”

> 仅在 VOD-001 裁决后询问。

### 推荐策略包：双层完成语义

- **Vityo 实现完成：** adapter、版本校验、确定性 fixture、能力缺口 UX 和失败关闭行为已完成并通过本仓库测试。
- **产品闭环完成：** 只有固定版本的 `styio-nightly` 与 `pafio-nightly` 在 Tier P 真机/真实二进制矩阵通过后，才能声明对应产品能力完成。
- 上游未发出合同期间可以继续完成 Vityo 侧工作，但不能把 heuristic、文件推断或 blocked state 宣称为完整产品能力。

此答案一次决定语言事实、执行 receipts、项目图 payload、跨仓 CI 与最终验收的共同完成口径。

### 备选方向

- 允许 Nightly 以永久降级能力作为产品完成；交付更快，但会削弱“真实、不伪造”的核心承诺。
- 上游就绪前完全暂停 Vityo 对应实现；边界最严格，但会延迟 adapter、UX 和门禁的可并行工作。

### 裁决记录

- **Decision:** Accepted A — 采用“双层完成语义”。
- **Answered at:** 2026-07-20
- **Rationale:** 允许 Vityo 侧 adapter、确定性测试和诚实降级 UX 与上游并行推进；只有固定版本的真实 Styio/Pafio 产品矩阵通过后，才声明对应产品能力完成。
- **Plan impact applied:** Decision recorded; product-plan graph will be reconciled after the owner-decision round.

## 5. VOD-003 — Nightly 的分发可信度等级

> 仅在 VOD-002 裁决后询问。

### 推荐策略包：Nightly 预览与公开稳定版分层

- Nightly 必须生成 Linux、Windows、macOS 可安装/可启动产物，并明确展示未签名或未公证状态。
- Nightly 在没有发布凭据时不启用自动更新；更新只接受签名 manifest 和完整性验证。
- 对外稳定版才要求 Windows 代码签名、macOS 签名与公证、Linux 完整性/仓库元数据，以及正式更新通道。
- 具体安装包格式、CI 缓存和发布脚本作为工程选择处理，不再逐项询问。

### 补充裁决：核心与平台适配独立版本

- 共享核心使用独立的 `coreVersion`；每个平台适配层使用自己的 `adapterVersion`，平台安装包再使用该平台原生可接受的 package version。
- 每个平台固定一个兼容的核心版本，执行自己的构建、适配、安装、签名、公证和更新门禁，并独立决定是否发布。
- 某个平台失败只阻断该平台；其他平台不等待、不降级，也不需要共享相同的版本号或发布日期。
- 某个平台可以停留在上一个兼容核心版本，其他平台可以先升级；release manifest 必须同时声明核心版本和平台适配版本。
- 只有共享核心自身的通用合同或安全门禁失败时，采用该核心候选版本的平台才共同受阻；这不回溯阻断仍使用旧核心版本的平台。
- 产品发布状态以“核心 + 平台”的矩阵表达，不再用一个全局 `released/not released` 状态掩盖平台差异。

此答案一次决定签名是否阻塞 Nightly、自动更新能否开启、三平台包装门禁和是否需要立即提供发布凭据。

### 备选方向

- 下一里程碑直接按公开稳定版标准交付；需要立即准备三平台签名、公证和发布基础设施。
- 仅保留 CI 原始构建产物，不提供可安装 Nightly；工作量较小，但不能验收真实安装/启动路径。

### 裁决记录

- **Decision:** Accepted A with independent platform releases and independently versioned core/platform adapters.
- **Answered at:** 2026-07-20
- **Rationale:** Nightly 与公开稳定版采用不同可信度门槛；平台特有失败不得形成全局发布锁，核心兼容性通过显式版本组合表达。
- **Architecture record:** `docs/adr/ADR-0017-core-and-platform-releases-are-versioned-independently.md`
- **Plan impact applied:** Decision recorded; implementation-plan reconciliation remains a separate scoped change.

## 6. 不再询问的工程默认值

以下项目在现有产品约束下有明确、安全且可逆的默认答案，由实现者直接处理：

| 项目 | 默认结论 |
|---|---|
| File System Prober 归属 | 属于 Platform Detector，只产出事实；File System Manager 消费事实并执行操作。现有细化文档已经给出该结论。 |
| `canX` preflight API | 只暴露便宜、确定、无副作用的能力/权限/边界检查；可能发生竞态的资源状态采用 execute-and-classify。 |
| OS 全局环境变量写入 | 不提供默认写入；运行时使用进程级 overlay。未来只有明确的安装/设置工具需求才新增受确认的写入动作。 |
| 密钥持久化 | 只进入操作系统安全存储；不可用时采用明确的 session-only、非持久化回退，严禁明文设置文件和日志。 |
| Shell 状态拆分 | 保留现有 ChangeNotifier 习惯，以领域 controller 拆分；文件行数预算是维护门槛，不是公共 API。 |
| 远程/虚拟文件系统 | 继续走既有 provider 接口；不阻塞桌面本地闭环，也不复制一套领域模型。 |
| 未知外部 payload 主版本 | fail closed，并显示结构化能力缺口；不做宽松猜测解析。 |
| 模块回收安全线 | 永不删除 active 版本；至少保留 last-known-good 以供回滚，具体保留数量可配置。 |

## 7. 依据

- `docs/design/Vityo-Product-Spec.md`：产品不变量、桌面优先范围、平台策略。
- `docs/design/Vityo-Implementation-Gaps.md`：未完成能力、上游阻塞和三个陈旧的低层“Decision needed”条目。
- `docs/plan/vityo-product-delivery/Requirements.md`：REQ-001..REQ-009 当前全量交付合同。
- `docs/plan/vityo-product-delivery/Evidence.md`：能力成熟度和上游依赖证据。
- `docs/plan/vityo-product-delivery/Checkpoints.json`：当前待实现节点及依赖关系。
- `docs/review/Logic-Conflicts.md` 与 `docs/adr/`：此前产品冲突均已裁决，不重复提问。

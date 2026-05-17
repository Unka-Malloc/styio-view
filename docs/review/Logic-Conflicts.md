# Vityo Logic Conflicts

**Purpose:** 记录 `Vityo` 当前尚未关闭的产品与架构冲突、风险和待裁决问题；已接受的结论应迁移到 ADR。

**Last updated:** 2026-04-12

## 1. 平台执行限制

| ID | Topic | Status | Risk | Next Step |
|----|-------|--------|------|-----------|
| LC-001 | iOS 无法按桌面同等方式承诺 unrestricted 本地 JIT | Resolved | 已通过“iOS 仅提供云执行入口、不挂载本地编译模块”解决产品承诺冲突 | 由 ADR-0004 和 M8 执行，不再作为开放冲突。 |
| LC-002 | Android 本地运行的打包尺寸与性能预算未定 | Resolved | 当前接受“Android 本地运行模块预算目标 `<= 50 MB`”作为产品约束 | 在实现期把该预算转成构建与分发门禁。 |

## 2. 编辑器复杂度

| ID | Topic | Status | Risk | Next Step |
|----|-------|--------|------|-----------|
| LC-003 | 自研文本引擎的复杂度高于普通 Flutter 文本控件 | Resolved | 已接受“共享核心框架，分端只在展示/交互/调优层优化”的架构路线 | 由 ADR-0010、M2、M8 执行。 |
| LC-004 | visual substitution 可能破坏源码与显示的一致性认知 | Resolved | 已接受“substitution 可由用户开关，并纳入 source fidelity 与性能基线测试”，避免用户把显示层箭头/图标误认为真实源码内容，进而影响复制、搜索、定位和 diff 认知 | 由产品规格、M3 和测试目录执行。 |

## 3. 运行可视化范围

| ID | Topic | Status | Risk | Next Step |
|----|-------|--------|------|-----------|
| LC-005 | 并非所有 Styio 语义都能自然映射到状态机或有向图 | Resolved | 已接受“运行可视化采用特性入口注册表，仅加载已声明支持的可视化能力；新支持以模块形式在启动时发现并按 staged update 更新” | 由 ADR-0011、M5、M9 执行。 |
| LC-006 | 事件流协议尚未定义 | Resolved | 已接受“执行层向 UI 暴露有序 `RuntimeEvent` 协议，UI 只消费协议，不从源码臆测运行图” | 由 ADR-0012、系统架构和 M5 执行。 |

## 4. AI 与 Profile

| ID | Topic | Status | Risk | Next Step |
|----|-------|--------|------|-----------|
| LC-007 | 本地 agent 的模型体积和许可边界未定 | Resolved | 已接受“只冻结 provider 抽象；本地 agent 首发不内建，后续以外接组件或模块接入” | 由 ADR-0013、M6 执行。 |
| LC-008 | 云端 profile 与 prompt 同步的隐私与合规要求未定 | Resolved | 已接受“profile / prompt sync 采用可插拔组件；未挂载时保持 local-only；云 agent 走 OpenAI-compatible endpoint adapter，预上线可接 OpenRouter 类 provider” | 由 ADR-0013、M6、M7 执行。 |
| LC-009 | 模块热更新的分发与平台合规边界未定 | Resolved | 已接受“iOS 为唯一受 App Store 审核限制且最后上线的平台；其它平台自分发；任何不满足 iOS 边界的模块通过 capability matrix 排除在 iOS 外” | 由 ADR-0014、M8、M9 执行。 |
| LC-010 | 模块卸载后的工作区配置、菜单和依赖回收未定 | Resolved | 已接受“移动端卸载全量回收、桌面端卸载由用户选保留或清除、Web 托管工作区关闭前警告并提供核心文件导出、默认保留 7 天后删除” | 由 ADR-0015、M8、M9 执行。 |

## 5. 当前裁决优先级

1. 当前无开放的 `LC-*` 条目。
2. 新冲突出现时先补 ADR 候选，再回填里程碑与测试目录。

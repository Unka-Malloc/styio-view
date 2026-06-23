# Initial Documentation And Architecture Freeze

**Purpose:** 记录 `Vityo` 初始化文档树、首批产品边界、实现计划和 ADR 冻结过程。

**Last updated:** 2026-04-12

**Date:** 2026-04-12

## 摘要

1. 将 `Vityo` 从空仓库状态提升为有完整 `docs/` 树的项目仓。
2. 冻结了 Flutter 作为主前端运行时的方向。
3. 明确 `styio` 主仓库仍是语言与编译器 SSOT，本仓负责 IDE、视窗、运行可视化和 AI 面板。
4. 明确桌面本地执行、Android 本地优先、iOS 云执行主路径的产品策略。
5. 明确功能模块必须支持按设备挂载、卸载和 staged update。
6. 明确运行可视化采用特性入口注册表，并冻结最小事件流协议。
7. 明确 AI / profile 采用 provider adapter 与外接组件路线。
8. 明确 iOS 为唯一商店受限平台，Web 采用 hosted workspace 路径。
9. 明确卸载回收与 7 天 hosted workspace 保留策略。
10. 冻结 `AgentProviderAdapter`、`ProfileSyncAdapter`、`DistributionChannelPolicy`、`HostedWorkspaceRecord` 四份 schema 基线。

## 当日完成

1. 新建 `docs/README.md` 与一级索引。
2. 新建 `design/`、`specs/`、`plans/`、`milestones/`、`adr/`、`review/`、`assets/`、`history/`。
3. 写入产品规格、系统架构、实施计划、测试目录和风险清单。
4. 准备首批 ADR 与里程碑批次。
5. 新增模块宿主与 staged update 的架构决策。
6. 新增运行可视化特性注册表与 `RuntimeEvent` 协议决策。
7. 新增 AI / profile provider adapter、iOS 合规下限和卸载回收 ADR。
8. 新增四份 adapter / distribution / hosted workspace schema 合同文档。
9. 冻结语言服务分层：token highlighting、semantic highlighting、diagnostics、formatting 分离，并采用 LSP-like 数据合同。

## 当前风险

1. 编辑器自研文本引擎复杂度高。
2. hosted workspace 的导出格式和删除作业仍需在实现期细化。
3. provider adapter 与密钥管理需要在实现期补安全细节。
4. 语言服务协议与 `FFI Adapter` 的映射细节仍需在实现期细化。

## 下一步

1. 冻结初始实施里程碑主题集合。
2. 冻结模块 manifest、distribution policy 与 capability matrix。
3. 开始桌面优先的工程脚手架设计。
4. 为 `RuntimeEvent` 协议与 provider adapter 补充实际 schema。
5. 为语言服务补充 token / semantic / diagnostic / formatting 协议草案。

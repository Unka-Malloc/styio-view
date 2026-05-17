# ADR-0011: Runtime Surface Uses A Feature Entry Registry

**Purpose:** 记录 `Vityo` 为什么不把运行可视化能力写死在 UI 中，而是通过可发现、可挂载、可 staged update 的特性入口列表来组织。

**Last updated:** 2026-04-12

**Status:** Accepted

**Date:** 2026-04-12

## Context

产品明确要求：

1. 运行可视化只覆盖当前真正支持的 Styio 语义子集
2. 新语义支持可以一点一点增加
3. 新增支持应当可以通过模块更新下发，而不是每次都改主壳逻辑

## Decision

采用 `RuntimeSurfaceFeatureEntry` 注册表：

1. 每个可视化能力通过 entry 声明自己支持的事件种类、语义标签和 surface 类型
2. 客户端启动时由 `Module Host Runtime` 扫描已装模块，生成当前会话的 feature registry
3. 运行视图只加载 registry 中存在的能力
4. 新特性通过模块 staged update 下载，重启后激活
5. 未命中 entry 的语义仅退化为日志、诊断或“当前未支持可视化”的提示

## Alternatives

1. 在 UI 中写死所有可视化入口：扩展性差，且难以按设备裁剪
2. 强行要求所有语义都映射到统一图：容易伪造语义
3. 会话内强切运行中的可视化模块：兼容性与状态迁移风险高

## Consequences

1. 运行可视化覆盖范围会以 registry 为准，而不是以营销叙述为准
2. 特性安装、卸载和 staged update 都必须联动更新入口列表
3. 每个新可视化能力都需要声明支持边界与退化策略

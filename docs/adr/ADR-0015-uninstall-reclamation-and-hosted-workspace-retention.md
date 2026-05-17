# ADR-0015: Uninstall Reclamation And Hosted Workspace Retention Are Explicit

**Purpose:** 记录 `Vityo` 如何处理不同平台的模块卸载、数据回收，以及 Web 托管工作区的关闭与保留窗口。

**Last updated:** 2026-04-12

**Status:** Accepted

**Date:** 2026-04-12

## Context

产品明确要求：

1. 手机端卸载模块后应默认全部回收
2. 桌面端卸载时应由用户选择保留或清除数据
3. Web 端全托管到云环境
4. 关闭云环境前要提示清空后果，并提供核心文件导出入口
5. 默认保留 7 天后删除

## Decision

采用：

1. Mobile optional module 卸载默认删除模块包、缓存和模块作用域数据
2. Desktop optional module 卸载弹出保留/清除数据选项
3. Web 端只连接 hosted workspace，不承诺本地执行或本地持久化
4. 用户关闭 hosted workspace 前必须看到清空提示与核心文件导出链接
5. Hosted workspace 关闭后进入 pending-deletion 状态，默认保留 7 天再删除

## Alternatives

1. 所有平台统一立即删除：桌面端对用户不友好
2. 所有平台统一永久保留：回收与成本不可控
3. Web 不给导出入口：用户数据退出路径过弱

## Consequences

1. 需要定义 `DataReclaimPolicy` 与 hosted workspace retention state
2. 卸载和关闭云环境都必须有清晰 UI 提示
3. 测试目录必须覆盖移动端回收、桌面端选择和 7 天删除窗口

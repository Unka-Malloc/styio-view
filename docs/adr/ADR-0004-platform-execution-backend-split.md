# ADR-0004: Split Execution Backends By Platform

**Purpose:** 记录 `Vityo` 不把所有平台的编译与运行策略强制统一，而按平台拆分执行后端。

**Last updated:** 2026-04-12

**Status:** Accepted

**Date:** 2026-04-12

## Context

桌面、Android、iOS 在本地执行、JIT、打包、系统限制和产品预期上并不相同。

## Decision

采用：

1. 桌面本地执行主路径
2. Android 本地优先路径
3. iOS 云执行主路径
4. 云端作为所有平台的补充能力
5. iOS 客户端不挂载本地编译模块，也不暴露本地编译入口

## Alternatives

1. 强制所有平台都走本地执行：iOS 风险过高。
2. 强制所有平台都走云执行：违背桌面和 Android 的本地能力目标。

## Consequences

1. 产品可在不同平台上选择现实可行的执行模式。
2. 需要维护多后端状态模型与用户提示。
3. 文档与测试必须按平台区分承诺。
4. iOS 的执行入口与模块矩阵必须保持一致。

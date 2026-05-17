# ADR-0014: iOS Defines The Compliance Floor For Distribution

**Purpose:** 记录 `Vityo` 为什么以 iOS 作为唯一商店受限平台和共享合规下限，同时允许其它平台采用自分发和自更新路径。

**Last updated:** 2026-04-12

**Status:** Accepted

**Date:** 2026-04-12

## Context

产品明确要求：

1. 只有 iOS 客户端必须接入 App Store
2. 其它平台不以应用商店分发为前提
3. iOS 客户端最后上线
4. 平台审核与分发规则以 iOS 为唯一强约束

## Decision

采用：

1. iOS 作为唯一受商店审核限制的平台与共享合规下限
2. iOS 客户端最后上线
3. Desktop / Android 采用自分发与自更新路径
4. 任何不满足 iOS 边界的模块都必须通过 capability matrix 在 iOS 上明确排除
5. 共享壳、manifest、module slot 和 provider adapter 仍保持统一

## Alternatives

1. 所有平台都按 App Store 同等级限制设计：会压缩非 iOS 平台能力
2. 完全忽略 iOS 审核边界：后续 iOS 上线时会被迫重构共享架构
3. 为 iOS 另做一套产品：维护成本过高

## Consequences

1. 模块 manifest 需要携带分发与平台兼容声明
2. 非 iOS 平台可以保留更灵活的模块交付方式
3. iOS-safe 与 non-iOS-only 能力必须在测试和发布链路中可判定

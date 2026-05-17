# Rollups Docs

**Purpose:** 提供 `Vityo` 的压缩活跃摘要与默认阅读入口，让当前状态和活跃缺口能在不先通读 raw history 的前提下被快速定位。

**Last updated:** 2026-04-17

## Scope

1. 当前状态摘要。
2. 活跃 gap ledger。
3. 跨多个 checkpoint 仍然有效的短摘要。

## Maintenance Rule

`rollups/` 只压缩活跃真相，不能替代 `design/`、`specs/`、`plans/`、`review/` 或 `history/` 的 owner 文档。

# ADR-0007: Theme System Is Layered

**Purpose:** 记录 `Vityo` 的主题系统为何按多个视觉层分离，而不是单套全局配色。

**Last updated:** 2026-04-12

**Status:** Accepted

**Date:** 2026-04-12

## Context

产品要求支持 IDE 主题预设、精细自定义，并覆盖编辑器、语义块、运行图区和 AI 面板。

## Decision

主题系统至少分为：

1. token 层
2. semantic block surface 层
3. surface / panel 层
4. runtime visualization 层
5. agent 层

## Alternatives

1. 单一全局主题对象：后续定制能力不足。
2. 每个面板各自定义配置：难以统一管理和同步 profile。

## Consequences

1. 主题数据模型会更复杂，但可扩展性更强。
2. 后续云 profile 同步可基于统一 schema。

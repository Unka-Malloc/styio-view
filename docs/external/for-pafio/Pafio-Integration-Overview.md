# Pafio Integration Overview

**Purpose:** 说明 `styio-view` 与上游 `pafio` 的总体责任边界，避免把前端项目模型和包管理器内部实现绑死。

**Last updated:** 2026-04-17

## 1. 总体判断

`pafio` 是项目、workspace、toolchain、lock/vendor、registry/package orchestration 的 canonical owner。

`styio-view` 不应该通过读取 `pafio` 私有缓存目录或内部源码结构来推断这些状态。

## 2. `styio-view` 负责

1. project graph、target selector、toolchain badge 的 UI
2. lock/vendor/build 状态的展示
3. `build/run/test` 项目执行路由与结果展示
4. package tree、publish preflight、registry 状态的前端表达

## 3. `pafio` 负责

1. workspace members 与 package graph
2. `lib / bin / test` targets
3. toolchain pin 解析
4. lock/vendor/build 状态
5. `pafio --json fetch / vendor / pack / publish / tool install / tool use / tool pin / build / run / test` 的 machine-readable success payload

## 4. 当前最关键的三项 handoff

1. `project_graph v1` 所需字段的正式 machine contract
2. `workflow_success_payloads v1` 与 supporting command success JSON，而不是只有 failure JSON
3. toolchain / registry / publish preflight / source-state 的 machine contract

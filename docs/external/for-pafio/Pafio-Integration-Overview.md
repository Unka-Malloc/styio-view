# Pafio Integration Overview

**Purpose:** 说明 `Vityo` 与上游 `pafio` 的总体责任边界，避免把前端项目模型和包管理器内部实现绑死。

**Last updated:** 2026-07-30

## 1. 总体判断

`pafio` 是项目、workspace、依赖、target、lock/resolution/vendor 和本地项目
workflow 的 canonical owner。

`Vityo` 只通过 `pafio metadata --json` 与稳定 workflow JSON 消费这些能力，
不读取 Pafio 私有目录或内部源码结构。

## 2. `Vityo` 负责

1. metadata view、target selector 与 compiler capability 的 UI
2. lock/vendor/build 状态的展示
3. `build/run/test` 项目执行路由与结果展示
4. package tree、publish preflight、registry 状态的前端表达

## 3. `pafio` 负责

1. workspace members 与 package/dependency graph
2. `lib / bin / test` targets
3. lock/resolution/vendor 状态
4. `pafio --json check / build / run / test` workflow envelope
5. `vendor / pack / publish` 客户端工作流

## 4. 当前最关键的三项 handoff

1. `metadata v1`
2. `workflow v1`
3. pack/publish 的稳定 machine result

Styio 编译器能力由 `styio --machine-info=json` 直接提供；hosted workspace 与
registry control 由 Styio Platform 提供。

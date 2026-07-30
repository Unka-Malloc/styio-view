# For Pafio Docs

**Purpose:** 集中维护 Vityo 消费的 Pafio metadata 与项目 workflow 合同。

**Last updated:** 2026-07-30

## Scope

这里的文档只回答一个问题：

`Vityo` 还需要 `pafio` 提供什么，双方如何对接。

## Entry Points

1. 目录索引：[INDEX.md](./INDEX.md)
2. 对接总览：[Pafio-Integration-Overview.md](./Pafio-Integration-Overview.md)
3. metadata 合同：[Pafio-Metadata-Contract.md](./Pafio-Metadata-Contract.md)
4. workflow success payload：[Pafio-Workflow-Success-Payloads.md](./Pafio-Workflow-Success-Payloads.md)

## Rules

1. 本目录只提 `Vityo` 需要的 machine handoff，不替 `pafio` 规划内部实现。
2. 文档聚焦输入输出、稳定字段、能力等级和失败语义。
3. API 路由、request/response shape 和 examples 一旦以 published contract 发布，就必须由合同包冻结，前端不能靠口头约定对接。
4. 只要 `pafio` 能满足这里的 machine contract，具体内部设计由 `pafio` 自己决定。
5. Styio compiler 与 Platform hosted API 不属于 Pafio handoff。

# For Pafio Docs

**Purpose:** 集中维护 `styio-view` 需要上游 `pafio` 提供、确认或共同定义的 machine contract；凡是会影响项目图、toolchain、workflow success payload、registry/package 状态的内容，统一收在这里。

**Last updated:** 2026-04-21

## Scope

这里的文档只回答一个问题：

`styio-view` 还需要 `pafio` 提供什么，双方如何对接。

## Entry Points

1. 目录索引：[INDEX.md](./INDEX.md)
2. 对接总览：[Pafio-Integration-Overview.md](./Pafio-Integration-Overview.md)
3. 项目图合同：[Pafio-Project-Graph-Contract.md](./Pafio-Project-Graph-Contract.md)
4. hosted control-plane API：[Pafio-Hosted-Control-Plane-Contract.md](./Pafio-Hosted-Control-Plane-Contract.md)
5. workflow success payload：[Pafio-Workflow-Success-Payloads.md](./Pafio-Workflow-Success-Payloads.md)
6. toolchain 与 registry 状态：[Pafio-Toolchain-And-Registry-State.md](./Pafio-Toolchain-And-Registry-State.md)

## Rules

1. 本目录只提 `styio-view` 需要的 machine handoff，不替 `pafio` 规划内部实现。
2. 文档聚焦输入输出、稳定字段、能力等级和失败语义。
3. API 路由、request/response shape 和 examples 一旦版本化发布，就必须由合同包冻结，前端不能靠口头约定对接。
4. 只要 `pafio` 能满足这里的 machine contract，具体内部设计由 `pafio` 自己决定。

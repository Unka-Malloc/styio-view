# For Styio Docs

**Purpose:** 集中维护 `Vityo` 需要上游 `styio` 提供、确认或共同定义的对接内容；凡是会影响语言服务、执行、runtime 事件、compile-plan consumer 与 machine-info 的内容，统一收在这里。

**Last updated:** 2026-04-12

## Scope

这里的文档只回答一个问题：

`Vityo` 还需要 `styio` 提供什么，双方如何对接。

## Entry Points

1. 目录索引：[INDEX.md](./INDEX.md)
2. 对接总览：[Styio-Integration-Overview.md](./Styio-Integration-Overview.md)
3. 语言桥接合同：[Styio-Language-Service-Adapter-Contract.md](./Styio-Language-Service-Adapter-Contract.md)
4. 编译运行合同：[Styio-Compile-Run-Contract.md](./Styio-Compile-Run-Contract.md)

## Rules

1. 这里不记录 `Vityo` 单仓可以独立完成的 UI/壳层工作。
2. 这里的内容必须尽量写成接口、输入输出和责任边界，而不是泛泛愿景。
3. 若某项长期边界已被接受 ADR 覆盖，以 ADR 为准；本目录只写实施级接口与交付物。
4. 本目录只提 `Vityo` 需要的 handoff，不替 `styio` 规划内部模块拆分、仓库结构或实现步骤。

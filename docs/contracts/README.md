# Contracts Docs

**Purpose:** 冻结 `Vityo` 产品拥有的 adapter 合同；这些合同定义前端需要什么，而不是上游当前碰巧提供什么。

**Last updated:** 2026-06-25

## Scope

本目录维护七类主合同、一个公共能力快照与一个缓存合同：

1. `LanguageServiceAdapter`
2. `ProjectGraphAdapter`
3. `ExecutionAdapter`
4. `RuntimeEventAdapter`
5. `DependencySourceAdapter`
6. `DeploymentAdapter`
7. `ToolchainManagementAdapter`
8. `AdapterCapabilitySnapshot`
9. `CacheContract` — 定义 Vityo 内所有缓存家族的统一接口、键空间、失效规则与分层策略

## Rules

1. 合同只定义输入输出、能力等级和失败语义，不绑定具体实现形态。
2. 任一合同都允许 `CLI Adapter`、`FFI Adapter`、`Cloud Adapter` 三种实现。
3. `Vityo` 主线只依赖这里的合同，不依赖 `styio` 或 `pafio` 的内部目录、类名或私有 ABI。
4. 需要 `pafio` 提供的 hosted/cloud API 路由与 payload，不在这里重复定义；统一指向 `../external/for-pafio/Pafio-Hosted-Control-Plane-Contract.md` 和后端 published contract package。
5. 上游缺能力时，不降低产品语义；把缺口记录到 `../external/for-styio/` 或 `../external/for-pafio/`。
6. adapter 切换不能改变 UI 语义，只能改变实现 route 与能力等级。
7. 这些合同是前端侧需求声明，不是对上游内部实现的规划文档。

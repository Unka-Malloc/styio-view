# AdapterCapabilitySnapshot

**Purpose:** 给 `Vityo` 一个统一的 adapter 能力视图，让 UI 在 `CLI / FFI / Cloud` 三类 route 之间保持同一套降级语义。

**Last updated:** 2026-04-21

## 1. Contract

### `AdapterCapabilitySnapshot`

1. `adapterKind = cli | ffi | cloud`
2. `languageService`
3. `projectGraph`
4. `execution`
5. `runtimeEvents`

### `AdapterEndpointCapability`

1. `level = unavailable | partial | available`
2. `detail`
3. `supportedContractVersions[]`

## 2. UI Rules

1. `Vityo` 必须在缺能力时继续可用，并明确显示 capability gap。
2. 替换 adapter 实现不能改变编辑器和工程 UI 的产品语义。
3. `CLI / FFI / Cloud` 同时存在时，由宿主和平台策略决定主路由；不是由单个模块随意写死。

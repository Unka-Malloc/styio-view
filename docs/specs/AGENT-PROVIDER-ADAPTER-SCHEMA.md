# Agent Provider Adapter Schema

**Purpose:** Preserve the minimum provider-adapter contract for compatible Agent runtimes; this is not an IDE adapter or Vityo product boundary.

**Last updated:** 2026-07-30

**Status:** Agent-runtime schema baseline

**Ownership:** Model/provider adapters belong to Vityo Coding Agent or another compatible Agent.
Vityo connects to the Agent through `packages/vityo_agent_protocol` and does not consume this
provider contract directly. Existing IDE implementations of these fields are migration inputs
tracked in [Vityo Implementation Gaps](../design/Vityo-Implementation-Gaps.md).

## 1. 适用范围

本 schema 覆盖：

1. OpenAI-compatible providers used inside an Agent runtime.
2. Local model/provider bridges used inside an Agent runtime.
3. Provider adapters mounted into an Agent runtime.

本 schema 不覆盖：

1. 具体模型权重格式
2. provider 内部计费逻辑
3. Vityo Agent Workbench presentation
4. IDE/Agent protocol messages

## 2. 枚举

### 2.1 `kind`

- `cloud_openai_compatible`
- `local_bridge`

### 2.2 `authMode`

- `none`
- `bearer_token`
- `api_key_header`
- `local_session`

### 2.3 `requestFormat`

- `openai_compatible_chat`
- `local_bridge_rpc`

## 3. Canonical Shape

`AgentProviderAdapterSpec` 必须包含：

1. `adapterId: string`
2. `schemaVersion: string`
3. `kind: enum`
4. `displayName: string`
5. `moduleId: string`
6. `distributionPolicyRef: string`
7. `enabledByDefault: boolean`
8. `capabilityFlags: object`
9. `routing: object`
10. `auth: object`
11. `limits: object`
12. `uiHints: object`

## 4. 字段细化

### 4.1 `capabilityFlags`

1. `chat: boolean`
2. `codePatch: boolean`
3. `stream: boolean`
4. `attachments: boolean`
5. `workspaceContext: boolean`
6. `runtimeContext: boolean`

### 4.2 `routing`

1. `endpointBase?: string`
2. `defaultModel?: string`
3. `modelAliases?: map<string, string>`
4. `localSocketPath?: string`
5. `localBinaryRef?: string`
6. `timeoutMs: integer`
7. `fallbackOrder?: string[]`

### 4.3 `auth`

1. `authMode: enum`
2. `headerName?: string`
3. `secretRef?: string`

### 4.4 `limits`

1. `maxInputBytes: integer`
2. `maxOutputTokens: integer`
3. `maxAttachmentBytes: integer`

### 4.5 `uiHints`

1. `settingsSection: string`
2. `badgeLabel?: string`
3. `requiresNetwork: boolean`
4. `userVisibleName: string`

## 5. 校验规则

1. `adapterId` must be unique within one Agent runtime installation.
2. `distributionPolicyRef` 必须引用 [DISTRIBUTION-CHANNEL-POLICY-SCHEMA.md](./DISTRIBUTION-CHANNEL-POLICY-SCHEMA.md) 中存在的 policy。
3. `kind=cloud_openai_compatible` 时，`routing.endpointBase` 必填，且 `requestFormat` 必须为 `openai_compatible_chat`。
4. `kind=local_bridge` 时，`routing.localSocketPath` 或 `routing.localBinaryRef` 至少存在一个，且 `requestFormat` 必须为 `local_bridge_rpc`。
5. `auth.secretRef` 只允许引用本地安全存储或云端 secret handle，不得在 profile sync 中明文同步。
6. `fallbackOrder` 中的 adapter id 必须已安装且不能包含自己。

## 6. 默认行为

1. When no provider adapter is mounted, the Agent runtime reports a structured unavailable or
   configuration-required state to its client.
2. When a local bridge is unavailable, the Agent runtime may follow its configured fallback order.
3. Unknown capability flags must not crash the Agent runtime or its protocol client.

## 7. 最小响应 envelope

`AgentProviderResponseEnvelope` 至少包含：

1. `requestId: string`
2. `providerMessageId?: string`
3. `role: string`
4. `contentParts: object[]`
5. `finishReason: string`
6. `usage?: object`

## 8. 首发建议默认值

1. `timeoutMs = 30000`
2. `maxInputBytes = 262144`
3. `maxOutputTokens = 8192`
4. `maxAttachmentBytes = 10485760`

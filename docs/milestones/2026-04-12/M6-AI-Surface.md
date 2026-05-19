# M6 — AI Surface

**Purpose:** 把 AI 协作面板做成 IDE 一等能力，支持自定义 prompt、上下文注入、provider adapter 和外接组件接入。

**Last updated:** 2026-05-18

**Status:** In Progress

## 1. 目标

1. 用户无需离开 IDE 即可与 coding agent 交互。
2. prompt profile、文件上下文、诊断和运行态上下文可注入。
3. 在没有本地 agent 和没有云 sync 组件的情况下，基础 AI 面板仍可工作。

## 2. 任务

| Task ID | Deliverable | Dependency | Exit |
|---------|-------------|------------|------|
| M6-T01 | 定义 `AgentSession` 与 provider 抽象 | M1 | 本地/云端接口统一 |
| M6-T02 | 实现底部或侧边 AI 面板骨架 | M1-T03 | 面板可用 |
| M6-T03 | 设计 prompt profile 数据模型 | M6-T01 | prompt 可持久化 |
| M6-T04 | 注入当前文件、选区、诊断上下文 | M4-T05 | agent 收到 IDE 上下文 |
| M6-T05 | 注入运行态上下文 | M5 | agent 可读执行信息 |
| M6-T06 | 设计本地 provider 与云 provider 选择逻辑 | M6-T01 | provider 可切换 |
| M6-T07 | 为后续补丁/代码建议预留应用接口 | M6-T04 | UI 能承载建议结果 |
| M6-T08 | 定义 OpenAI-compatible cloud provider adapter | M6-T01 | 可接通标准兼容端点 |
| M6-T09 | 预留本地外接 agent bridge | M6-T01 | 本地 agent 可后接入 |
| M6-T10 | 定义 `ProfileSyncAdapter` 与 local-only fallback | M6-T03 | 无 sync 时也可用 |
| M6-T11 | 准备预上线 OpenRouter 类 provider 配置位 | M6-T08 | 预上线可直接接云 provider |
| M6-T12 | 让 AI surface 跟随统一视窗族切换桌面/移动排版 | M1-T10 / M6-T02 | AI 面板不再与主壳布局脱节 |

## 3. 门禁

1. AI 面板不再是外部链接，而是 IDE 内建面板。
2. 用户可编辑和保存预输入 prompt。
3. agent 至少能读取当前工作上下文。
4. 无本地 agent 和无 sync 组件时，基础 AI 面板仍不失效。

## 4. Current implementation anchor

当前代码入口：

1. `frontend/vityo_app/lib/src/agent/agent_surface.dart`
2. `frontend/vityo_app/lib/src/app/layout/vityo_shell_scaffold.dart`

当前已落地：

1. `AgentSurface` 已按 `ViewportProfile` 切换桌面/移动两套排版
2. agent 相关模块过滤已切到 `ModuleSlot.agentSurface / cloudRuntime`
3. iOS cloud-first 合规路径和 desktop local-bridge 预留已经进入 UI 占位结构
4. `AgentSessionContext` 已将当前文件、选区、诊断和最近运行态序列化为 provider adapter 可消费的上下文对象
5. `AgentProviderAdapter` 请求/响应 envelope 与 local-only fallback 已落地，为云 provider 和本地 bridge 接入预留统一发送接口
6. `AgentCodePatchApplier` 已将 agent code patch 转入 `EditorSessionController.applyFormattingEdits`，避免绕过编辑器事务、undo 和语言重新分析
7. `AgentPromptProfileStore` 已通过 Foundation DataStore 持久化 prompt profile，为可编辑 prompt 和 local-only profile 留出正式存储路径
8. `OpenAICompatibleAgentProviderAdapter` 已通过可注入 transport 生成 `/chat/completions` 请求并解析响应 envelope，避免把具体网络实现耦合进 Agent Surface
9. `NetworkAgentProviderTransport` 已消费 Environment / `NetworkManager.postJson`，把 provider HTTP 发送收口到系统兼容网络层
10. `ConfiguredAgentProviderAdapterFactory` 已通过 `ConfigurationStore.resolveCredential` 解析 endpoint 的 credential reference，避免 prompt profile 或 UI 持有明文 token
11. `AgentCodingSessionController` 已承载 prompt 草稿、发送状态、响应 envelope 和待确认 code patch，`AgentSurface` 已提供输入和响应展示入口
12. `ShellRuntimeModel.applyAgentPendingPatch` 已把 Agent pending patch 接入 `AgentCodePatchApplier` 和当前 `EditorSessionController`，让 UI 可以显式应用或丢弃智能体代码建议
13. `AppBootstrap.createAgentCodingSessionController` 已把持久化 profile、credential/network provider factory 和 local-only fallback 组合成启动期装配策略；未配置 profile 时不会默认访问外部模型服务
14. `AgentCodingSessionController.mountProvider` 已提供运行期安全切换 profile/provider 的入口，`AgentSurface` 会展示当前 profile、adapter、provider kind 和 code patch 支持状态
15. `AgentConversationTurn` 已进入 provider request 和 controller，会把上一轮 user/assistant turn 传给下一次请求，Agent Surface 也会展示最近对话并支持清空会话
16. `AgentProviderConfigurator` 已把 profile 保存、provider adapter 创建、mount fallback 和 controller 切换封装成运行期配置服务，`ShellRuntimeModel.saveAndMountAgentProfile` 为后续 Settings UI 暴露单一入口
17. `AgentSurface` 已提供最小 provider profile 表单，可编辑 display name、OpenAI-compatible base URL、model、system prompt 和可选 bearer token；token 会经 `AgentProviderConfigurator` 写入 Credential DataStore，profile 只保留 credential reference
18. `OpenAICompatibleAgentProviderAdapter` 已支持从 assistant JSON content 中解析 `contentParts` 和 `code_patch`，让云 provider 的结构化代码修改能进入 pending patch / Apply Patch 流程
19. OpenAI-compatible 请求的 system message 已追加 Vityo structured response contract，明确 `contentParts` / `code_patch` schema、`baseRevision`、UTF-16 offset 语义和 secret 禁止规则
20. `AgentCodePatchApplier` 会在进入编辑器事务前检查 active document revision 和 edit range，拒绝 stale revision、越界、反向 offset 和重叠 edits，避免 provider 错误 patch 破坏文档
21. `AgentCodingSessionController` 已用 request serial 隔离进行中的 provider 请求；运行期切换 provider 后，旧响应会被丢弃，不会污染当前会话或 pending patch
22. `AgentCodingSessionController.cancelActiveRequest` 已提供用户主动取消入口，Agent Surface 会在发送中显示 Cancel，并复用 request serial 丢弃晚到响应
23. `AgentSurface` 会在应用前展示 pending patch 的 patch id、base revision 和每条 edit 的 document/range/replacement 长度，避免用户只能看到 summary 就应用代码修改
24. `OpenAICompatibleAgentProviderAdapter` 会同时接受裸 JSON 和 ```json fenced JSON 的 structured response，降低模型格式波动导致 patch 丢失的概率
25. `AgentCodingSessionController` 已限制 conversation turns 窗口，默认最多保留并发送最近 20 条 turn，避免 provider 请求无限膨胀
26. `AgentWorkspaceCodePatchApplier` 已支持 workspace 级多文件 patch：先校验所有目标文档和 documentId，再应用其它 `WorkspaceDocumentStore` 文档，最后应用 active document；workspace load/save 失败会返回失败结果并保持 active document 不变
27. `ShellRuntimeModel.applyAgentPendingPatch` 已切到 workspace 级 applier，Agent Surface 的 Apply Patch 入口现在可以应用多文件 patch
28. `OpenAICompatibleAgentProviderAdapter` 的 structured patch parser 同时接受 camelCase 与 snake_case 字段，兼容 `contentParts/content_parts`、`patchId/patch_id`、`baseRevision/base_revision`、`documentId/document_id` 和 `replacementText/replacement_text`
29. `AgentSessionContext` 已加入 workspace snapshot，包含 active file、workspace file count、截断后的 file list 和 truncated 标志，为多文件 coding agent 提供文件范围上下文
30. `AgentSurface` 的 IDE Context 区会展示 active file 和 workspace file count，让用户能看到当前发给 Agent 的工作区范围
31. `AgentDocumentContext` 已加入截断后的 active document text 和 `textTruncated`，默认最多发送 50000 字符，让 coding agent 不只看到文件元数据
32. `AgentSessionContext.schemaVersion` 已提升到 `5`，明确区分新增 workspace snapshot、document text、selection-aware document window、diagnostics truncation 和 runtime truncation metadata 后的上下文合同
33. OpenAI-compatible request metadata 已加入 `contextSchemaVersion`，让 provider adapter 或远端服务可以按上下文合同版本解析
34. `AgentPromptProfile.defaultForPlatform` 的默认 `contextChannels` 已加入 `workspace`，让请求 metadata 与实际发送的 workspace snapshot 对齐
35. `AgentPromptProfile.fromJson` 会在旧 profile JSON 缺少 `contextChannels` 时回退到标准默认 channels，避免历史配置读成空上下文声明
36. `AgentSessionContext.toJsonForChannels` 已让 profile 的 `contextChannels` 真正控制发送给 provider 的 context 字段，不再只是 metadata
37. `AgentSurface` 的 Provider Profile 表单已提供 context channel FilterChip，用户可配置发送给 provider 的 file / selection / diagnostics / runtime / workspace 范围
38. Provider Profile 表单会拒绝空 `contextChannels`，避免用户保存一个几乎不向 coding agent 提供上下文的配置
39. `LocalOnlyAgentProviderAdapter` 的 fallback usage 已加入 context schema version 和 workspace file count，便于无 provider 时确认 IDE context 捕获范围
40. OpenAI-compatible endpoint builder 同时支持 provider base URL 和完整 `/chat/completions` URL，避免用户配置完整路径时重复拼接
41. OpenAI-compatible response parser 会从 content block 数组中继续尝试解析 structured `contentParts` / `code_patch`，避免兼容端点用 blocks 返回时丢失可应用代码补丁
42. Agent workspace code patch 已加入显式 `operation:create` 语义，新增文件时不再依赖 seed document 副作用，并会在目标文档已存在时拒绝覆盖
43. Agent workspace code patch 已加入显式 `operation:delete` 语义，删除文件通过 `WorkspaceDocumentStore.deleteDocument` 执行，并会拒绝删除不存在的文档
44. Agent workspace code patch 写入非 active 文档时会记录 best-effort rollback 信息；后续 save/delete 失败会回滚已经成功写入的 workspace 文档，降低多文件 Agent patch 半应用风险
45. Agent Surface 的 pending patch 预览会显示 `replace/create/delete` operation，避免用户在应用前无法区分普通编辑与文件级新增/删除
46. OpenAI-compatible request 现在按 system、history、IDE context、current prompt 的顺序组织 messages，让当前用户请求保持最后一条 user message，降低模型把 context JSON 当成最终请求的风险
47. OpenAI-compatible structured response parser 会从带说明文字的 assistant content 中提取首个 JSON object 候选，避免模型在 JSON 前加解释时丢失 code patch
48. OpenAI-compatible request 会把 `AgentRequestAttachment` 序列化为独立的 `vityo_agent_attachments` 上下文消息，并继续保证 current prompt 是最后一条 user message
49. OpenAI-compatible response parser 会在 `message.content` 为空时读取 `tool_calls[].function.arguments`，兼容把 structured code patch 放进 tool call arguments 的 provider 返回形态
50. OpenAI-compatible response parser 已支持 `type: output_text` 的 content block，避免 Responses 风格普通文本回答被解析为空字符串
51. `AgentCodingSessionController` 已管理 prompt attachments，发送请求时带入 provider request，成功后清空，provider 失败时保留以便用户重试或移除
52. Agent Surface 会展示当前 prompt attachments 的名称和类型，让用户在发送前确认附件范围
53. Agent Surface 的 prompt 区已通过 `AnimatedBuilder` 订阅 `AgentCodingSessionController`，发送、取消、响应、pending patch 和附件变化后 UI 能自动刷新
54. Agent Surface 的 Provider Profile 表单已订阅 `AgentCodingSessionController`，运行期 mount provider 后 display name、base URL、model、system prompt 和 context channels 会同步刷新
55. Agent Surface 的 Provider Profile 表单切换 provider 时会清空 bearer token 输入框，避免旧 token 被误带入新 provider 配置
56. `AgentProviderConfigurator` 会忽略空白 bearer token，不写入 Credential DataStore，也不把空 credential reference 挂到 profile
57. Agent provider credential resolver 和 OpenAI-compatible adapter 都会 trim bearer token，避免 Credential DataStore 中的空白字符进入 Authorization header
58. OpenAI-compatible request 会在 provider 序列化层截断超大 attachments，并通过 `contentTruncated` 标志让远端知道附件内容已被裁剪
59. Agent document context 对 oversized active document 采用 selection-aware window，并在 JSON 中提供 `textStart/textEnd`，避免长文件里光标附近代码被截断掉
60. OpenAI-compatible structured response contract 已明确 code patch edit offsets 使用完整文档 UTF-16 offset；当 `document.textStart > 0` 时，模型需要把窗口内 offset 加上 `textStart`
61. Agent workspace context 截断文件列表时会强制保留 active file，避免工作区文件过多时 agent 看不到当前文件路径
62. Agent workspace context 会按顺序去重 workspace file list，避免重复路径浪费 provider 上下文窗口并误导文件数量
63. Agent session context 会把 diagnostics 限制在前 100 条，并提供 `diagnosticCount/diagnosticsTruncated`，避免错误量过大时 provider request 失控
64. Agent runtime context 的 `stdoutTail/stderrTail` 会只保留最近 50 条日志，避免长运行输出撑爆 provider 请求
65. Agent runtime context 的 `eventKinds` 会按出现顺序去重并限制最多 50 个，避免运行事件类型过多撑大 provider 请求
66. Agent runtime context 会提供 `stdoutEventCount/stdoutTruncated/stderrEventCount/stderrTruncated/eventKindCount/eventKindsTruncated`，让 provider 知道 runtime context 是否被裁剪
67. FileSystemWorkspaceDocumentStore 会拒绝相对 documentId 中的 `.` / `..` 路径穿越片段，Agent create/delete 最终落盘时不能越过 workspace root
68. Agent code patch validator 会在进入 workspace store 前拒绝 documentId 中的 `.` / `..` 路径穿越片段，避免不安全路径流入任意 store 实现
69. Agent code patch validator 会拒绝单个超大 `replacementText`，避免 provider 返回异常大 edit 直接进入编辑器事务或文件写入
70. Agent workspace code patch 会在访问 `WorkspaceDocumentStore` 前拒绝 unsafe documentId，避免 create/delete/load 分支先触碰不安全路径
71. Agent code patch 会拒绝 oversized edit list，避免 provider 返回过多小 edit 直接拖垮编辑器事务或 workspace 写入路径
72. Agent Surface 的 prompt 输入框会跟随 `AgentCodingSessionController.draftPrompt` 清空，避免发送成功后 UI 仍显示旧 prompt
73. Agent Surface 在 patch application in-flight 时会禁用 `Apply Patch`，避免同一个 pending patch 被连续点击重复应用
74. Agent Surface 的 attachment chip 支持发送前移除附件，避免错误附件继续进入 provider request
75. Agent Surface 的 patch preview 在隐藏超过 5 个 edit 的剩余部分时会显示 hidden edit count，避免用户误以为预览完整
76. Agent Surface 支持从 IDE context 直接添加 active document 与 selection attachments，让用户可显式控制发送给 provider 的代码上下文
77. Agent attachments 支持 metadata，并把 document / selection 的 documentId、revision 和 range 传给 provider，便于后续 code patch 精确绑定来源
78. Agent attachments 会过滤 non-json-safe metadata，避免外部附件来源把不可序列化对象带进 provider request
79. Agent conversation history 会截断 oversized turn text，避免长 prompt 或长 assistant response 被完整带入后续 provider request
80. Agent prompt attachments 会按数量上限保留最新附件，避免扩展或 UI 连续添加附件导致 provider request 膨胀
81. Agent file operation edits 不再继承 `patch.baseRevision`，避免 active document 的全局 revision 阻止 create/delete workspace edit
82. OpenAI-compatible structured response contract 明确 `patch.baseRevision` 只作为 replace edit fallback，create/delete 需使用 `edit.baseRevision` 表达目标文件 revision
83. Agent code patch application result 会记录 replace/create/delete operation counts，便于 UI、日志和后续审计区分补丁行为
84. Agent Surface 会展示已应用 patch 的 operation counts，让用户直接看到 replace/create/delete 行为摘要
85. OpenAI-compatible provider metadata 会记录 attachment kinds、attachment truncated count 和 conversation turn count，便于请求规模调试
86. Agent pending patch 被 dismiss 时会同步清理 patch application result，避免 UI 残留已放弃补丁的应用结果
87. Agent 新请求开始时会清理 stale lastResponse，避免 provider 失败后 UI 同时显示旧回答和新错误
88. Agent clear conversation 会同步清理 lastError，避免用户清空对话后错误状态继续残留
89. Agent Surface 在只有 provider error 且没有 conversation turns 时也显示 Clear Conversation，让用户可清理错误状态
90. Local-only agent fallback usage 会暴露 attachment 和 conversation 规模信息，与 OpenAI-compatible metadata 保持调试信号一致
91. Agent patch application result message 会包含 operation counts，让 shell/runtime log 与 UI 复用同一行为摘要
92. Agent provider error 会 redacts bearer token 和 token query 片段，避免敏感凭据直接进入 UI 或日志
93. AgentCodingSessionController 会拒绝空 id、kind、name 或 content 的 prompt attachment，避免无意义附件进入 provider request
94. Agent Surface 会在 active document 或 selection 只有空白内容时禁用 attachment actions，避免 UI 暗示可发送无效上下文
95. Agent Surface 在 patch application in-flight 时也会禁用 Dismiss Patch，避免 dismiss 与异步应用结果竞态
96. Agent Surface 在 patch application in-flight 时禁用 Send，避免新 prompt 请求和异步 patch 应用竞争 pending/result 状态
97. AgentCodingSessionController 会拒绝 concurrent patch application，避免外部调用绕过 UI 防重入导致同一 pending patch 被重复应用
98. AgentCodingSessionController 会在 patch application in-flight 时阻止 sendPrompt，避免外部调用绕过 UI 发送新请求
99. AgentCodingSessionController 会在 provider remount 后忽略旧 patch application result，避免异步旧结果污染新 provider 会话
100. Agent clearPendingPatch 会让 in-flight patch application result 失效，避免 programmatic dismiss 后旧异步结果写回 controller
101. Agent Surface 会读取 `controller.applyingPatch` 状态，外部触发 patch application 时 UI 也进入同样的发送和补丁操作禁用态
102. Agent clearConversation 会让 in-flight patch application result 失效，且 UI 在应用中禁用 Clear Conversation，避免清状态与异步结果竞态
103. Agent Surface 会捕获 unexpected patch application error 并写入 redacted patch result，避免异常丢失或 token 泄露
104. Agent Provider Profile 保存失败时会复用 token redaction，避免 credential 出现在 profile form 错误提示中
105. Agent provider mount message 会经过 token redaction，避免外部配置消息把 credential 显示到 Agent Surface
106. Agent Provider Profile 表单会拒绝非 http(s) 且非 root-relative 的 base URL，避免错误 endpoint 被保存后到请求阶段才失败
107. Agent Provider Profile 表单会接受 Web hosted 默认 root-relative base URL，避免 `/api/styio-agent/v1` 被 endpoint 校验误拒绝
108. Agent code patch 会拒绝同一 offset 的多个零长度 insert edits，避免缺少显式 ordering 时产生不稳定补丁结果
109. OpenAI-compatible Agent Provider 会跳过非 JSON markdown fence 并解析后续结构化 patch JSON，避免模型解释代码块遮蔽真实补丁
110. OpenAI-compatible Agent Provider 在 assistant content 为空字符串但 tool_calls 存在时会解析 tool call arguments，避免空 content 遮蔽结构化 patch
111. OpenAI-compatible Agent Provider 会合并 assistant text content 与 tool call patch，避免带说明文字的 tool_calls 响应丢失结构化补丁
112. OpenAI-compatible Agent Provider 会解析 Responses API 风格 `output[]` message 与 function_call，避免非 chat choices 响应丢失结构化补丁

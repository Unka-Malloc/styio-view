# Next Stage Gap Ledger

**Purpose:** 压缩记录 `Vityo` 仍与三仓统一文件治理基线存在的活跃缺口，确保治理债务能以 checkpoint 大小推进，而不是继续靠人工兜底。

**Last updated:** 2026-05-19

## Active Gaps and Closure Evidence

## Closed (Minimal / Verified)

1. 代码与适配层最小闭环具备可复测锚点：`frontend/vityo_app` 的 `flutter analyze` + `flutter test` 本地通过；`VITYO_PRODUCT_GATE=1` 相关 product 工作流测试目前默认跳过（非缺陷，属于 gate 策略）。
2. `FG4` 及 docs/test 治理链路在文档/脚本面保持持续可验证状态。
3. 2026-04-22 外部审计的 ignored scratch defect queue 已迁入 tracked 审计报告和本 ledger；`docs/audit/defects/` 继续保持 transient/ignored，不作为提交内容。
4. 下游 `nightly` 的仓库级 CI 面统一到 `local-ci-gate`，与独立的 `styio-audit` policy gate 和 `audit` handoff gate 分离。
5. Shell run-route gating 已在 route snapshot 层阻断 preview-only 路径，`Run` 命令不会把不可用路径下沉给 execution adapter 失败。
6. stale async document-load rejection 已通过 binding open generation 与 shell workspace load generation 落地，晚到的旧文件加载不会覆盖当前 active editor。
7. Runtime route text precision 已改为按 primary adapter 选择 execution detail，hosted/cloud 路径不再误显示 CLI fallback 文案。
8. Web hosted-control-plane failure parsing 已在共享 hosted execution codec 中支持顶层 failure envelope，diagnostics、stderr 与 runtime events 不再依赖 `error_payload` 包装。
9. 主题编辑面板持久化已从 Settings Surface 接到 ShellRuntimeModel 与 `VityoThemeOverrideStore`，保存后会驱动 `MaterialApp.theme` 更新。
10. 真实 Agent provider 调用链已具备可复测闭环：Web 平台 NetworkManager 使用 browser fetch，Agent provider JSON transport 支持真实 POST，Configured provider factory 可把 OpenAI-compatible adapter 挂入 AgentCodingSessionController 并完成 prompt 请求与响应解析。
11. AgentSessionContext schema v16 已在 workspace channel 中暴露 capped `documentSamples`，ShellRuntimeModel 会把 active/cached/open 文档样本交给 Agent，OpenAI-compatible provider metadata 与 structured response contract 也会声明该受限读取边界。
12. 默认 Agent coding skill 已覆盖 C++/Clang、compile database、CMake build graph、clangd-style symbol facts、test/debug loop 与 Styio C++ compiler 项目约束；默认 prompt 明确 native-code 工作优先消费这些工程事实。
13. `workspace.buildFacts` 已能从 workspace file list 探测 `compile_commands.json`、`CMakeLists.txt`、`CMakePresets.json` 与 `.clangd`，让 Agent 在生成 C++ 补丁前先识别编译数据库、CMake 和 clangd 事实来源。
14. Shell 应用 Agent workspace patch 时已增加 sampled document preflight：未被 active/open/cached `documentSamples` 覆盖的既有 inactive 文件不会被直接修改，避免智能体对未读文件凭空生成 offset patch。
15. Agent command catalog 已加入 `openWorkspaceFile`，Shell 白名单可执行该 command suggestion 并打开 workspace 文件，让智能体在被拒绝修改未采样文件后有正式路径请求采样目标文件。
16. Agent command catalog 已加入 `searchWorkspace`，Shell 白名单可执行受限 workspace 文本搜索，并把结果写入下一轮 `workspace.lastSearch`，让智能体可以先搜索再请求打开或修改目标文件。
17. `commands.lastResult` 已进入 AgentSessionContext schema v16，Shell 会记录最近一次用户确认的 Agent IDE command outcome，provider metadata 和 structured contract 会提示智能体基于该结果继续下一步。
18. Toolchain 层已把 CMake、Ninja 与 clangd 纳入 native C++ 工具发现，与 `clang`/`clang++` 一起形成编译器、工程模型、构建执行和 language-service 的可读 toolchain facts。
19. Toolchain 层已把 LLDB、GDB、clang-format、clang-tidy 与 CTest 纳入 native C++ 工具发现，形成 debug、format、static-analysis 与 test-runner 的可读 toolchain facts。
20. Agent toolchain context 已把 native C++ 工具按 build/debug/format/static-analysis/test-runner/language-service 分类输出到 `toolchains.nativeTools`，避免智能体从未结构化 metadata 猜测工具能力。
21. Agent workspace build facts 已识别 CMakeUserPresets、clang-format、clang-tidy 与 CTest 配置，并通过 `workspace.buildFacts.toolingHints` 暴露给智能体。
22. Agent 默认 prompt、OpenAI-compatible provider metadata 与 structured response contract 已明确要求消费 `workspace.buildFacts.toolingHints` 和 `toolchains.nativeTools`，避免 C++ 智能体忽略真实工具链事实。
23. Agent command catalog 已暴露 native tool commands，Shell 白名单可接收 `formatActiveDocument` / `runStaticAnalysis` / `runTests` suggestion；缺少 ToolchainManager 时记录受控 blocked result，存在 formatter/static-analyzer/test-runner toolchain 时可通过 ToolchainManager 格式化 active document、运行静态分析和运行测试。
24. Shell 的 `runStaticAnalysis` native tool command 已解析 clang-tidy 常见单行输出，并把当前 active document 的 warning/error/note 映射为 editor diagnostics。
25. Shell 的 `runTests` native tool command 已解析 CTest 常见 summary 输出，并把结构化 `testResult` 写入 `commands.lastResult.metadata` 供 Agent 下一轮读取。
26. OpenAI-compatible structured response contract 已明确要求智能体消费 `commands.lastResult.metadata.testResult`，确保下一轮补丁、调试或测试建议基于结构化测试结果而不是自由文本猜测。
27. Agent command catalog 已暴露 `runBuild` native tool command，Shell 可通过 CMake build toolchain 发起 workspace build，并把 clang/GCC 风格构建诊断映射回 editor diagnostics 与 `commands.lastResult.metadata.buildResult`。
28. 用户直接从 IDE 触发 `runBuild` / format / static-analysis / test native tool command 时，Shell 会把结果写入 `commands.lastResult`，让下一轮智能体编码能读取用户刚执行过的真实工具反馈。
29. ShellRuntimeModel 已维护 capped native tool result history，Build/Test/format/static-analysis 面板后续可读取同一份结构化结果，而不是重新解析 debug log。
30. Runtime Surface 已渲染 `Build / Test Results` 区块，展示 ShellRuntimeModel 的 native tool result history 中的 build/test summary，避免用户只能从 debug log 查找构建和测试反馈。
31. Runtime Surface 的 Build/Test result card 在存在 build diagnostics 时提供 `Open diagnostics` 动作，并通过 Shell command 路径跳转到 editor diagnostic，形成结果面板到编辑器的最小导航闭环。
32. Native tool result history 已保留本次工具产生的 diagnostics，Runtime Surface 会把具体 commandId 回传给 Shell，Shell 可精确跳转到该 command 的首个 build/static-analysis diagnostic。
33. ShellRuntimeModel 已提供 debugger session model、line breakpoint toggling 与 start/stop/continue/stepOver 命令入口；缺少 ToolchainManager 或 debugger 时进入受控 blocked 状态，存在 LLDB/GDB toolchain 时进入 configured 状态等待真实 launch adapter。
34. Debug Console 已渲染 Debugger Session 摘要，展示 debug status、debugger label、blocked/configured message 与 breakpoint 列表，避免调试状态只存在于 ShellRuntimeModel 内部。
35. Debugger Session Snapshot 已可承载 call stack frames 与 variables，Debug Console 会渲染 Call Stack 和 Variables 区块，为后续 LLDB/GDB launch adapter 输出提供稳定 UI 合同。
36. AgentSessionContext 已暴露 Debugger Session facts、breakpoints、stackFrames、variables 与 registered debugCommands，让智能体编码能基于真实 IDE 调试状态请求受控动作，而不是猜测调试器状态。
37. Debug Launch Contract 已从 debugger toolchain metadata 生成 DAP launch configuration；缺少 `programPath` 或协议不支持时会阻断启动，避免 IDE 只因发现 debugger 工具就伪装成可调试。
38. Debug Adapter Protocol codec 已支持 Content-Length framing、启动请求计划和常用调试查询/控制 request builders，为后续 LLDB/GDB DAP session adapter 提供可复测协议底座。
39. DAP Session Controller 已能记录 outbound request、关联 response、维护 pending requests，并根据 stopped/continued/terminated/failed response 更新会话状态，为后续真实 debugger process transport 提供可复测状态机。
40. DAP Transport Bridge 已抽象 debugger 字节传输，负责编码 outbound request、处理 split inbound frame 并把 response/event 喂给 DAP Session Controller，为 LLDB/GDB 进程 transport 接入保留清晰边界。
41. IO DAP Process Transport 已能通过 `dart:io` 启动 debugger adapter 进程，把 stdout bytes 接入 DAP Transport Bridge，并把 outbound request 写入 stdin，为桌面 LLDB/GDB DAP 接入提供真实进程传输底座。
42. DAP Debug Adapter Launcher 已能从 ready launch configuration 创建 transport、attach bridge 并发送 launch plan，向 ShellRuntime 暴露可关闭的 session handle，避免 Shell 直接耦合 DAP codec/session/transport 细节。
43. ShellRuntimeModel 已可注入 DAP Debug Adapter Launcher；Start Debugging 在 launch configuration ready 且 launcher 存在时发送真实 DAP launch plan，并把 adapter session status / pending request count 暴露给 Debug Session 与 Agent context。
44. ShellRuntimeModel 已可刷新 active DAP session snapshot，把 stopped/continued/terminated/failed 等 adapter session status 与 event/pending 计数同步到 Debug Session 和 Agent context。
45. DAP Session Controller 已解析 `stackTrace` 与 `variables` response body，Shell refresh 会把真实 stackFrames / variables 同步到 Debug Session 和 Agent context。
46. ShellRuntimeModel 的 Continue / Step Over 已在 active DAP session paused 且 stopped event 提供 threadId 时发送真实 DAP `continue` / `next` request，并把 adapter session 更新为 running。
47. ShellRuntimeModel 的 Stop Debugging 已在 active DAP session 存在时发送真实 DAP `disconnect` request，再关闭 session handle，并把 stop 结果同步到 Debug Session。
48. DAP Transport Bridge 已暴露 session snapshot stream，ShellRuntimeModel 可自动同步 stopped/continued/terminated 事件到 Debug Session 与 Agent context，并在 continued/terminated 后清理过期 stackFrames / variables。
49. ShellRuntimeModel 已在 DAP paused snapshot 后自动按 `stackTrace -> scopes -> variables` 编排检查请求，DAP Session Controller 已解析 scopes response，让暂停态可以主动拉取 call stack 与 locals 供 Debug Session / Agent context 使用。
50. DAP Session Controller 已解析 threads response；ShellRuntimeModel 在 stopped event 缺少 threadId 时会自动请求 `threads` 并选择可检查线程继续 `stackTrace -> scopes -> variables`，线程事实已同步给 Agent context。
51. C++ DAP smoke readiness gate 已能发现 `lldb-dap` / `lldb-vscode` / `codelldb` 和 `clang++` / `g++`，并支持 `VITYO_DAP_ADAPTER` / `CXX` 覆写；缺少真实 adapter 或 compiler 时返回明确 blocked reason，避免把不可运行的真实调试器 smoke 伪装为通过。
52. Debug Launch Contract 已区分 DAP adapter 进程参数 `debuggerArguments` 与被调试程序参数 `arguments`；IO DAP Process Transport 会把 `debuggerArguments` 传给 adapter process，Agent launch context 也暴露该 argv。
53. Debug Launch IO Readiness Probe 已在启动 DAP adapter process 前检查 launch contract、debugger executable、programPath 与 cwd；IO DAP Process Transport 已接入该 probe，缺失真实文件时会以明确 blocked reason 失败。
54. Debug Console 已渲染 Debug Session threads 列表，展示 DAP threads response 同步后的线程 id / name，避免线程事实只存在于 ShellRuntimeModel 或 Agent context。
55. ShellRuntimeModel 已支持选择 DAP stack frame 并为该 frame 重新请求 `scopes -> variables`；DAP Session Controller 会在新的 scopes 请求开始或 response 到达时清理旧 variables，避免跨栈帧显示过期变量。
56. Debug Console 的 call stack frame 行已可触发 stack frame selection，VityoShellScaffold 已将该 UI 动作接到 ShellRuntimeModel.selectDebugStackFrame，形成用户选择栈帧后重新拉取变量的交互入口。
57. ShellRuntimeModel 已支持选择 DAP thread 并重新请求该线程 `stackTrace`；DAP Session Controller 会在新的 stackTrace 请求开始时更新 activeThreadId 并清理旧 frames/scopes/variables，Debug Console thread 行已接到该选择动作。
58. Agent command catalog 已暴露 `selectDebugThread` / `selectDebugStackFrame`，Shell 白名单可执行这两个受控 debug command suggestion，让智能体编码能请求切换线程或栈帧并复用既有 DAP `stackTrace` / `scopes` 检查链路。
59. Shell 白名单已覆盖 registered debug command suggestion：`toggleBreakpoint` / `startDebugging` / `stopDebugging` / `continueDebugging` / `stepOver`，让智能体编码看到的调试命令目录和实际可执行能力保持一致。
60. OpenAI-compatible provider metadata 已暴露 `debugThreadCount`，structured response contract 已要求智能体从 `debug.threads` / `debug.stackFrames` 读取真实 id 再提出调试选择命令。
61. 默认 AgentPromptProfile 系统提示已同步调试上下文规则，要求智能体读取 `debug.threads` / `debug.stackFrames` 并使用 `commands.debugCommands` 提出 debugger action。
62. Agent Surface registered command gate 已接受 `nativeToolCommands` 与 `debugCommands`，避免已注册的 build/test/debug suggestion 在 UI 上被误判为 unsupported。
63. Agent command catalog 已暴露 `save` / `saveAll` persistence commands，Shell 白名单可执行保存 suggestion 并记录保存结果，让智能体编码能在 build/test/debug 前请求磁盘状态同步。
64. Shell 白名单会在 dirty workspace 下阻断 Agent 的 disk-backed native tool suggestion：`runBuild` / `runStaticAnalysis` / `runTests`，并要求先执行 `saveAll`，避免智能体基于旧磁盘文件获得误导性工具反馈。
65. Agent structured response contract 与默认 profile 已明确消费 `commands.lastResult.metadata.requiredCommand`，让智能体在下一轮先提出 required registered command，再重试被阻断操作。
66. Shell 白名单会在 dirty workspace 下阻断 Agent `startDebugging` suggestion，并要求先执行 `saveAll`，避免 dirty source 与调试二进制/符号状态脱节。
67. Agent 执行 `saveAll` required command 后，保存结果 metadata 会带回 `completedRequiredCommandFor`，让下一轮智能体能知道此前被阻断且现在可重试的 command。
68. NetworkAgentProviderTransport 已将真实 Agent provider HTTP 调用失败映射为结构化 `AgentProviderTransportException`，区分 http status、timeout 与 invalid response，并验证 provider timeout 会传递到底层 NetworkManager。
69. AgentCodingSessionController 已保留最近一次结构化 provider failure，后续恢复 UI、重试策略和 telemetry 可以读取 timeout/http/invalid-response 类型，而不是解析字符串错误。
70. Agent Surface 已在 provider error 区展示结构化 failure kind、HTTP status 与 recovery hint，并在 Clear Conversation 后清理该恢复提示。
71. Agent Surface 已在结构化 provider failure 后提供 Retry Provider Request 操作，复用保留的 draft prompt 重新发送请求，并在成功后清理 provider error/failure 状态。
72. Agent provider cancel 已从 AgentCodingSessionController 传递到 CancellableAgentProviderAdapter / CancellableAgentProviderTransport，并通过 CancellableNetworkManager token 取消活动 provider HTTP 请求，取消结果映射为结构化 `cancelled` failure。
73. Agent Surface 已在结构化 provider failure 后提供 Use Local Fallback 操作，可切换回 LocalOnlyAgentProviderAdapter 并清理 provider error/failure 状态，避免云端 provider 持续不可用时阻断本地 IDE 工作流。
74. Provider Profile section 已在结构化 provider failure 时展示 reconfiguration guidance，提示用户检查 base URL、model 和 bearer token，并在 Clear Conversation 后清理该提示。
75. Provider Profile reconfiguration flow 已可在 provider failure 后修改 base URL/model/token、保存 profile、重新 mount provider，并清理 provider error/failure guidance。
76. OpenAI-compatible Agent provider 已可通过真实 loopback HTTP server 完成 live local E2E，覆盖 AgentCodingSessionController、OpenAICompatibleAgentProviderAdapter、NetworkAgentProviderTransport、LocalNetworkManager 与本地 provider response。
77. AgentSessionContext 默认 skills channel 已暴露 reference-grounded IDE development skill，默认 prompt 与 provider contract 要求 IDE 功能参考成熟开源实现并通过 Vityo 本地测试或门禁验证，避免智能体编码只依据自由文本经验推进。
78. AgentSessionContext 的 language channel 已暴露 StyioService capability serviceStatus，provider metadata 与 structured contract 会区分 available、derived、unsupported 与 unavailable 语言能力，避免智能体把 fallback 或空能力当作真实编译器事实。
79. Agent command catalog 已暴露 `refreshLanguageService` language-service command，Shell 白名单和直接命令路径都可触发刷新，并把 Agent suggestion 刷新后的 languageService status 写入 `commands.lastResult.metadata`，让智能体在 stale/unavailable 语言事实前有受控刷新路径。

## Open (Need Product-Stage Close)

1. `W7/W8/W9/W10` 仍有非完整产品级部分：移动端交互与真机/模拟器矩阵、真实模块包 staged update + 平台文件回收仍未完成。
2. `active/history/archive` 生命周期与 docs 历史脚本核验尚未完成到完整平台级阶段 gate。
3. `FG4`: 只有当出现 `docs/**` 或 `frontend/vityo_app/test/**` 外的新构建/临时资产追踪需求时，才继续扩展 negate 与 hygiene 规则。
4. Product workflow coverage 仍由 `VITYO_PRODUCT_GATE=1` 显式触发，不作为默认 CI 成功的产品全矩阵证明。

## Exit Condition

当 `Vityo` 具备以下能力时，这个 ledger 可以转入维护态：

1. `active/history/archive` 生命周期清晰，
2. docs 索引和 lifecycle 可脚本校验，
3. repo hygiene 会显式发现 docs/file governance 漂移，
4. GitHub Ruleset 对 `nightly` 强制要求 PR 合入，以及 `audit`、`styio-audit`、`local-ci-gate` 三个检查。

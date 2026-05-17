# ADR-0016: Language Service Separates Highlighting, Diagnostics, And Formatting

**Purpose:** 记录 `Vityo` 的语言服务如何分层，以及为什么不让 `linter` 负责基础高亮。

**Last updated:** 2026-05-10

**Status:** Accepted

**Date:** 2026-04-12

## Context

`Vityo` 需要：

1. 在输入时立即更新基础 token 高亮
2. 在稍慢但更准确的分析结果到达后刷新语义高亮
3. 以独立通道返回 diagnostics、quick fix 和格式化结果
4. 保持未来与云端服务、外部编辑器或桥接层的数据合同稳定
5. 让 declaration、reference、definition、rename edit 和 current-file usage 能在本地输入链路中先落地，再交给上游语言服务替换

如果把基础高亮交给 `linter`：

1. 输入链路会被不必要地拉长
2. 诊断失败会连带影响基础显示
3. 职责边界会变得混乱

## Decision

语言服务分为四层：

1. `Token Layer`
   负责词法 token、高亮基色与基础操作符类别
2. `Semantic Layer`
   负责 type / function / pipeline / state 等语义高亮和语义装饰
3. `Diagnostics Layer`
   负责 error / warning / hint / fix，不负责基础高亮
4. `Symbol / Resolve Layer`
   负责 document symbols、reference ranges、go-to-definition、rename plan 和当前文件 usage 结果
5. `Formatting And Assist Layer`
   负责 `TextEdit` 风格格式化结果、补全与 hover

共享合同采用 `LSP-like` 数据结构，但实现仍保持自研：

1. `TokenSpan { start, end, tokenKind }`
2. `SemanticSpan { start, end, semanticKind, modifiers[] }`
3. `Diagnostic { severity, code, message, range }`
4. `TextEdit { range, newText }`
5. `CompletionItem { label, kind, insertText, detail }`
6. `HoverPayload { range, markdown }`
7. `DocumentSymbol { name, kind, nameRange, declarationRange, detail }`
8. `ReferenceSpan { name, kind, range, targetRange, isDeclaration }`
9. `DefinitionTarget { symbol, originRange }`
10. `RenamePlan { target, newName, references[], edits[] }`

## Alternatives

1. 让 linter 同时决定高亮、诊断和格式化：职责过重，输入链路不稳定
2. 只保留 token 高亮、不做语义高亮：无法支撑 Styio 的语义化界面
3. 把 reference / resolve 暂时留到 compiler handoff：会阻塞编辑器侧的 navigation、usage、rename 和补全 ranking 验证
4. 直接强制采用完整 LSP server：当前阶段引入成本高于收益

## Consequences

1. 编辑器文本层先消费 `TokenSpan`，再叠加 `SemanticSpan`
2. linter 失败不得导致基础高亮消失
3. 格式化必须返回 `TextEdit[]` 一类补丁，而不是静默改写 Source Buffer
4. `FFI Adapter` 与 Flutter bridge 需要显式暴露多类结果，而不是单一“分析结果”对象
5. 本地 fallback 可以先用 token-derived symbol index 支撑 IntelliJ-style reference/resolve 行为，但不得把它声明成上游编译器的完整语义结果
6. `unresolved-reference` diagnostics 可以先复用本地 symbol index 暴露体验，但必须保持 warning 级别和可替换的 compiler-owned 语义边界

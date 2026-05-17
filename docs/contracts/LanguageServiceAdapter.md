# LanguageServiceAdapter

**Purpose:** 冻结 `Vityo` 需要的语言层结果；任何上游实现只要满足本合同，就能驱动当前编辑器语义。

**Last updated:** 2026-05-10

## 1. Responsibilities

`LanguageServiceAdapter` 必须提供：

1. `tokens[]`
2. `semanticSpans[]`
3. `diagnostics[]`
4. `quickFixes[]`
5. `formattingEdits[]`
6. `completionItems[]`
7. `hover`
8. `semanticBlocks[]`
9. `documentSymbols[]`
10. `referenceSpans[]`
11. `definition`
12. `renamePlan`

## 2. Snapshot Contract

### 2.1 `LanguageServiceSnapshot`

1. `documentId`
2. `revision`
3. `tokens[]`
4. `semanticSpans[]`
5. `diagnostics[]`
6. `formattingEdits[]`
7. `completionItems[]`
8. `hover`
9. `semanticBlocks[]`
10. `documentSymbols[]`
11. `referenceSpans[]`
12. `definition`
13. `renamePlan`

### 2.2 Required Types

1. `TokenSpan { range, kind, lexeme }`
2. `SemanticSpan { range, kind, modifiers[] }`
3. `Diagnostic { severity, code, message, range }`
4. `DiagnosticQuickFix { label, detail, edits[] }`
5. `FormattingEdit { range, newText }`
6. `CompletionItem { label, kind, insertText, detail }`
7. `HoverPayload { range, markdown }`
8. `SemanticBlockRange { range, label }`
9. `DocumentSymbol { name, kind, nameRange, declarationRange, detail }`
10. `ReferenceSpan { name, kind, range, targetRange, isDeclaration }`
11. `DefinitionTarget { symbol, originRange }`
12. `RenamePlan { target, newName, references[], edits[] }`

## 3. Non-Negotiable Rules

1. 基础高亮由 `TokenSpan` 与 `SemanticSpan` 驱动，不由 linter 决定。
2. diagnostics 必须带 source range，不能只返回纯文本消息。
3. quick fix 和 formatting 必须返回补丁，不直接修改前端 buffer。
4. semantic block ranges 必须能驱动函数体灰底圆角块，不要求前端猜测结构。
5. definition 必须由 reference 解析到 declaration，不得只按字符串跳转。
6. reference spans 必须标记 declaration 和 usage，使 find-usages、rename 和当前文件高亮有同一套源数据。
7. rename plan 必须返回可应用的 `TextEdit` 集合，并复用 reference spans；不允许前端执行独立的全局字符串替换。
8. `unresolved-reference` diagnostics 必须复用 symbol / reference 模型和明确 range；本地 fallback 不能把纯 token 名称误报成编译器语义错误。

## 4. Adapter Modes

允许三种实现：

1. `CLI Adapter`
2. `FFI Adapter`
3. `Cloud Adapter`

只要 snapshot shape 一致，`Vityo` 不关心实现方式。

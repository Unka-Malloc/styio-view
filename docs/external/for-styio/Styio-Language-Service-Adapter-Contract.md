# Styio Language Service Adapter Contract

**Purpose:** 冻结 `Vityo` 需要上游 `styio` 提供的语言服务 handoff；允许 `CLI` 或 `FFI` 任一实现路径，但输出 shape 必须满足产品合同。

**Last updated:** 2026-04-12

## 1. Required Result Sets

上游 `styio` 至少需要提供：

1. `tokens[]`
2. `semanticSpans[]`
3. `diagnostics[]`
4. `quickFixes[]`
5. `formattingEdits[]`
6. `completionItems[]`
7. `hover`
8. `semanticBlocks[]`

## 2. Required Fields

### 2.1 Tokens

1. `range`
2. `kind`
3. `lexeme`

### 2.2 Semantic Spans

1. `range`
2. `kind`
3. `modifiers[]`

### 2.3 Diagnostics

1. `severity`
2. `code`
3. `message`
4. `range`

### 2.4 Quick Fixes And Formatting

1. `label`
2. `detail`
3. `edits[]`

## 3. Acceptable Delivery Modes

`Vityo` 接受两种本地交付路径：

1. `CLI Adapter`
2. `FFI Adapter`

规则：

1. 可以只先交付其中一种。
2. 一旦交付，输出 shape 必须与 `docs/contracts/LanguageServiceAdapter.md` 对齐。
3. `Vityo` 不解析人类 stderr 来猜测 token、diagnostic 或 hover 结果。

## 4. Machine Handshake Requirements

`styio --machine-info=json` 后续必须扩展为至少包含：

1. `active_integration_phase`
2. `supported_contract_versions`
3. `supported_adapter_modes`
4. `feature_flags`

## 5. Current Frontend Baseline

当前 `Vityo` 已有：

1. `TokenSpan / SemanticSpan / Diagnostic / FormattingEdit / CompletionItem / HoverPayload` 数据合同
2. inline glyph substitution
3. semantic block surface
4. inline quick fix / completion / formatting apply

因此，上游交付后主要替换数据源，不重做编辑器产品语义。

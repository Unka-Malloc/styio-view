# M3 — Semantic Surfaces And Adapter Contracts

**Purpose:** 冻结语言层产品合同、adapter 槽位和语义表面；先让编辑器围绕产品合同稳定，再替换真实上游实现。

**Last updated:** 2026-04-12

**Status:** In Progress

## 1. 目标

1. 建立语言层 adapter 合同与实现槽位。
2. 让编辑器能根据 token 与 block 范围做显示层替换和块表面装饰。
3. 冻结 token highlighting、semantic highlighting、diagnostics、formatting 的职责边界。
4. 建立 `LanguageServiceAdapter` 与 `AdapterCapabilitySnapshot`。

## 2. 任务

| Task ID | Deliverable | Dependency | Exit |
|---------|-------------|------------|------|
| M3-T01 | 冻结 `LanguageServiceAdapter` 产品合同 | M1 | 合同 SSOT 冻结 |
| M3-T02 | 定义 `TokenSpan / SemanticSpan / Diagnostic / TextEdit / CompletionItem / HoverPayload` 合同 | M3-T01 | 语言服务协议冻结 |
| M3-T03 | 建立 `CLI / FFI / Cloud` 三类 adapter 的能力快照 | M3-T01 | capability gap 统一表达 |
| M3-T04 | 建立 Flutter adapter 消费层 | M3-T01 | Flutter 主线不依赖上游内部实现 |
| M3-T05 | 确立 `linter` 只负责 diagnostics / fix，不负责基础高亮 | M3-T02 | 编辑器文本层不依赖 linter 才能着色 |
| M3-T06 | 实现 `->` 的 visual substitution | M2 | 显示替换不改写源码 |
| M3-T07 | 实现 `|>` 的 visual substitution | M2 | 显示与光标映射正确 |
| M3-T08 | 以 block ranges 实现函数体灰底圆角块 | M3-T02 | 块表面与语义边界一致 |
| M3-T09 | 定义最小可编译单元计算接口 | M3-T04 | 后续编译触发可消费 |
| M3-T10 | 实现 substitution 用户开关 | M2 / M3-T06 | 关闭后恢复原始文本显示 |
| M3-T11 | 建立 substitution 开/关性能对比基线 | M3-T10 | 可比较两种模式性能 |

## 3. 门禁

1. 分析结果可稳定进入 Flutter。
2. 基础高亮由 token / semantic 层驱动，而不是由 linter 决定。
3. `->` 与 `|>` 的图形替换不会污染文件内容。
4. 函数块表面由语义边界驱动，不依赖纯正则规则。
5. substitution 可被用户显式关闭，且关闭后性能基线可测。
6. `CLI / FFI / Cloud` 任一路径补齐后，只替换 adapter 实现，不重构 UI。

## 4. Current implementation anchor

当前代码入口：

1. `frontend/vityo_app/lib/src/integration/adapter_contracts.dart`
2. `frontend/vityo_app/lib/src/language/language_contract.dart`
3. `frontend/vityo_app/lib/src/language/styio_language_service.dart`
4. `frontend/vityo_app/lib/src/language/simple_styio_language_service.dart`
5. `frontend/vityo_app/lib/src/editor/editor_controller.dart`
6. `frontend/vityo_app/lib/src/editor/editor_surface.dart`

当前已落地：

1. `TokenSpan / SemanticSpan / Diagnostic / FormattingEdit / CompletionItem / HoverPayload` 数据合同
2. 本地 `SimpleStyioLanguageService` skeleton
3. `EditorSessionController` 内建分析结果刷新链路
4. 编辑器面板中的 token / semantic / diagnostic / formatting 分层预览
5. `AdapterCapabilitySnapshot` 已成为主壳的一等状态
5. `->` 与 `|>` 已在 Flutter 编辑器预览中作为 inline glyph 渲染
6. 函数 block range 已映射成灰底圆角语义表面容器
7. widget smoke test 已覆盖 glyph 预览存在性
8. 编辑器内部 language inspector 已接入 `ViewportProfile`，宽屏 `iOS/Android` 仍保持 mobile 语义和堆叠布局
9. widget smoke test 已覆盖 `desktop family / mobile family / wide iOS still mobile` 三条路径
10. language inspector 已分化为 `desktop card stack / mobile section tabs` 两套表现，diagnostics、semantic blocks、hover、completion、formatting 均有独立 section
11. active line 已接入 inline language feedback，直接在源码流中展示 diagnostics、hover、completion 或 caret context
12. inline language feedback 和 language inspector 都已支持直接应用 completion / formatting action，开始从“分析展示”转向“可操作的语言面板”
13. diagnostics 已接入最小 quick-fix 回路，当前支持 `missing assignment / stray brace / unclosed block` 三类基础修复
14. 光标所在 token 已接入正文高亮与 token context 展示，hover / completion 开始真正围绕具体 token 而不是只围绕 active line

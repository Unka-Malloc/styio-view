# Shell / Editor Runbook

**Purpose:** 提供 Flutter 主壳、编辑器核心、language UI 外壳与手写 Web Editor 主线的日常维护入口。

**Last updated:** 2026-06-28

## Mission

负责 app shell、editor core、source buffer fidelity、language inspector 外壳和手写 `editor.html` 主线。该团队不拥有 adapter 合同本身，也不定义上游 `styio` 的语言语义。

## Owned Surface

Primary paths:

1. `frontend/vityo_app/lib/src/app/`
2. `frontend/vityo_app/lib/src/view_render/shell/`
3. `frontend/vityo_app/lib/src/view_render/editor/`
4. `frontend/vityo_app/lib/src/view_render/runtime/`
5. `frontend/vityo_app/lib/src/view_render/agent/`
6. `frontend/vityo_app/lib/src/view_render/theme/`
7. `frontend/vityo_app/lib/src/view_render/platform/`
8. `frontend/vityo_app/lib/src/view_ide/editor/`
9. `frontend/vityo_app/lib/src/editor/`
10. `frontend/vityo_app/lib/src/view_ide/language/`
11. `frontend/vityo_app/lib/src/language/`
12. `prototype/editor.html`
13. `prototype/editor.css`
14. `prototype/editor.js`
15. `prototype/editor-modules/`
16. `prototype/workspace/`
17. `prototype/README.md`
18. `prototype/dev_server.py`
19. `prototype/test_dev_server_security.py`
20. `frontend/vityo_app/lib/src/frontend_shell/`
21. `prototype/PROTOTYPE-GOVERNANCE.md`
22. `prototype/prototype-manifest.json`
23. `prototype/scripts/check-prototype-governance.mjs`
24. `prototype/scripts/check-editor-load.mjs`

Key SSOTs:

1. `产品规格 -> ../design/Vityo-Product-Spec.md`
2. `系统架构 -> ../design/Vityo-System-Architecture.md`
3. `手写 Web IDE handbook -> ../specs/HANDWRITTEN-WEB-IDE-ENGINEERING-HANDBOOK.md`

## Daily Workflow

1. 先确认变更属于“显示层”还是“源码层”；不得把显示替换误写成源码改写。
2. 改动 `prototype/editor.html` 主线前，先按 handbook 检查分层、渲染切片和工作流约束。
3. 若 Flutter 壳层和手写原型都受影响，先明确哪条是主验证线，再同步另一条的约束或 handoff。
4. 变更编辑语义、光标、selection 或 inspector 流程时，同时检查测试目录映射是否要补。
5. 手写原型入口或自测说明变化时，同批更新 `prototype/README.md`，不要把 focused editor 运行方式留在仓库级入口里漂移。
6. Flutter 主壳与手写原型的工具链说明必须保持显式版本钉住：Flutter `3.41.7` / Dart `3.11.5`、Node.js `v24.15.0` LTS、Chromium `147.0.7727.116`。
7. `prototype/package.json` 与 `package-lock.json` 的 Node 依赖必须用锁文件可复现的精确版本，并优先用 `npm ci` 而不是 `npm install`。
8. Flutter shell 的 app bootstrap、workspace controller、document store 和 command registry 只能消费 `backend_toolchain` 的正式 adapter surface；legacy `integration/` export 只用于兼容测试。
9. product gate 测试若需要 `VITYO_PRODUCT_GATE=1`，在本轮最小闭环中保持显式跳过策略，不把 gated workflow 写成默认 shell 验证要求。
10. 手写 prototype selftest 的布局几何断言必须等待 grid/sidebar CSS transition 收敛后再采样；容差只能覆盖 headless Chromium 子像素取整，不得掩盖实际 drawer 宽度或 inset 漂移。
11. Prototype dev-server API 变更必须保持 Host allowlist、same-origin mutation、session credential、default-off mutation 和 workspace-limited file-content reads，并同步运行 `python3 prototype/test_dev_server_security.py`。
12. Top-level `prototype/*.html` 只能通过 `prototype/prototype-manifest.json` 增删改名；`editor.html` 是唯一 canonical 产品行为入口，`index.html` gallery 和 style experiment 页面不得定义 workspace mutation、adapter contract 或 dev-server API 语义。
13. 当上游 `styio` 语法仍在实现中时，`frontend/vityo_app/lib/src/language/styio_syntax_highlighter.dart` 只能提前提供宽容 token、nested-comment-safe token、line-contained literal-safe token、typed-declaration-safe semantic、parameter semantic、operator-hover copy 和 resource-aware block-range 支持；language service 可以复用这些结果提供 completion、hover 和 TODO/FIXME comment hint diagnostics，但不得把 mock 支持描述成编译器已可执行能力，compile/run 仍必须通过 adapter capability gap 或真实 handoff 表达。
14. IntelliJ-style navigation 的本地 fallback 放在 `frontend/vityo_app/lib/src/language/styio_symbol_index.dart`：它可以从 token 结果建立 document symbol、reference、definition、rename edit、rename conflict preflight、current-file Safe Delete preflight、current-file Inline Variable initializer / usage preflight、current-file Introduce Variable selection / name-conflict preflight、current-file Extract Function selection / parameter / duplicate-fragment / name-conflict preflight、current-file Change Signature function rename / parameter reorder / parameter rename / unused parameter removal preflight、带 declaration / read / write 分类的 current-file usage、支持 `///` 与 `/** ... */` 的 doc-comment-backed function-call parameter info 和 `@param` / `@param[name]` active-argument docs、named-argument active-parameter mapping、named-argument-safe Change Signature、default-parameter signature display、symbol-aware hover / doc-comment-backed quick documentation、parameter-name / local-binding / precedence-aware binary / parenthesized / unary-expression type inlay hints、Specify type explicitly / Remove explicit type intentions、call-site arity diagnostics / argument-list quick fixes、named-argument issue diagnostics / quick fixes、argument type diagnostics / literal and parameter-type quick fixes、binary / unary operator operand diagnostics / quick fixes、local initializer type diagnostics / quick fixes、typed local assignment type diagnostics / quick fixes、`when` condition type diagnostics / quick fixes、function return type diagnostics / quick fixes、unused parameter diagnostics / removal quick fixes、top-level import optimization diagnostics / quick fixes、same-scope duplicate declaration diagnostics / unique rename quick fixes、支持中段与首字母匹配的 symbol-scoped completion、doc-comment-backed symbol completion documentation、call-site named-argument completion、Alt+Enter Add argument names / Add current argument name / Remove current argument name / Remove all argument names / Negate when condition / Simplify negated boolean literal / Simplify double negation / Simplify boolean comparison（literal / stable-term） / Simplify boolean expression（literal / duplicate / complement / absorption operand） / Simplify negated comparison / Invert comparison / Remove redundant parentheses / Apply De Morgan's law / Flip comparison operands intentions、`.emit` / `.task` / `.await` / `.stdout` / `.not` / `.when` expression postfix completion、warning 级 `unresolved-reference` / `unused-local-symbol` diagnostics、unresolved usage 的 current-file Change To Similar Symbol / Create Local Binding / Create Function quick fixes；`frontend/vityo_app/lib/src/view_render/editor/editor_surface.dart` 可以用 document symbols 驱动 structure-view style Symbols pane，并消费 reference ranges、completion items、parameter info、surround templates 与 diagnostic ranges 做 caret usage 高亮、definition / usage navigation、`Alt+F7` current-file Find Usages panel、`Alt+Delete` current-file Safe Delete blockers / declaration-delete preview、`Ctrl+Alt+N` current-file Inline Variable blockers / inline-all preview、`Ctrl+Alt+V` current-file Introduce Variable name input / edit preview、`Ctrl+Alt+M` current-file Extract Function name input / duplicate replacement preview、`Ctrl+F6` current-file Change Signature name / parameter-order / parameter-removal input 与 edit preview、`Alt+Enter` context actions lookup 与 edit preview、`Ctrl+Alt+Shift+N` current-file symbol lookup、typing auto-popup 与 `Ctrl+Space` completion lookup、选中项 preview / documentation action 和 `Ctrl+Q` completion documentation、`Ctrl+Alt+T` Surround With lookup、`Ctrl+P` parameter info popup、`Ctrl+Q` quick documentation panel、`Ctrl+W` / `Ctrl+Shift+W` structural selection、semantic block folding、`Ctrl+-` fold toggle、`Ctrl+Shift+M` matching brace navigation、`Home` smart line-start navigation、`Ctrl/Alt+Left` / `Ctrl/Alt+Right` token-aware word navigation、`Ctrl/Alt+Backspace` / `Ctrl/Alt+Delete` token-aware word deletion、typed brace/quote pair insertion、selection wrapping、empty-pair backspace、smart Enter indentation 和 `Tab` / `Shift+Tab` line indent / outdent、`Ctrl+/` line comment toggle、`Ctrl+D` duplicate line/selection、`Alt+Shift+Up` / `Alt+Shift+Down` move line/selection、`Ctrl+Shift+J` join lines、`Ctrl+Y` delete line、problems-list selection、diagnostic navigation、quick-fix keymap actions、side-pane rename apply 和 `Shift+F6` inline rename bar，但只能作为编辑器体验预览，不能替代上游 compiler-owned 语义解析。
15. Editor core 实现只能落在 `frontend/vityo_app/lib/src/view_ide/editor/document/`、`selection/`、`controller/`、`transactions/`、`render_plan/`、`actions/` 子模块；顶层 `view_ide/editor/*.dart` 和 legacy `src/editor/*.dart` 必须保持 façade/barrel。
16. Workspace navigation and command discovery changes must keep `StyioCommandRegistry`, shell bottom-surface routing, command/workspace services, and runtime execution/file loading in one slice. The shell top bar owns current-file breadcrumbs from workspace path segments plus the active document-symbol context, while workspace navigation history owns Go Back / Go Forward and Recent Locations. `Cmd/Ctrl+Shift+P` is reserved for shell Command Palette, `Cmd/Ctrl+P` is reserved for shell Quick Open, `Alt+Left` / `Alt+Right` are reserved for shell workspace navigation history, `Cmd/Ctrl+Shift+E` is reserved for shell Recent Locations, the Document Links route owns active-file `@import` link collection and resolved import opening, the Document Highlights route owns active-file symbol occurrence collection with declaration/read/write/text filters and occurrence opening, the Code Lens route owns active-file symbol lenses with project-visible usage/reference counts and symbol opening, `Ctrl+B` is reserved for shell workspace Go to Declaration, `F12` is reserved for shell workspace Go to Definition, `Ctrl+Shift+B` is reserved for shell workspace Go to Type Definition, `Ctrl+F12` is reserved for shell workspace Go to Implementation, `Ctrl+H` is reserved for shell workspace Type Hierarchy, `Cmd/Ctrl+Shift+O` is reserved for shell workspace Outline, `F2` is reserved for shell workspace Rename Symbol, `Cmd/Ctrl+T` is reserved for shell workspace symbol search, `Shift+F12` is reserved for shell workspace Find Usages with declaration/read/write access filters, `Ctrl+Alt+H` is reserved for shell workspace Call Hierarchy, the shell Problems route owns workspace-wide diagnostics, `Cmd/Ctrl+.` is reserved for shell workspace Code Actions, and `Cmd/Ctrl+Shift+F` is reserved for shell Find in Files plus workspace replace preview/apply, while editor-local `Ctrl+P` parameter info remains scoped to the editor surface.

17. Prototype dev-server security tests must cover Windows filesystem behavior with native paths, junction/symlink fallbacks, and retryable cleanup so the handwritten web editor remains safe without WSL or Linux-only path assumptions.
18. Prototype editor selftest launcher changes must preserve `PYTHON_BIN`, `STYIO_CHROME_PATH` / `CHROME_EXECUTABLE`, and `STYIO_EDITOR_URL` behavior across Linux, Windows, and macOS CI hosts.

## Change Classes

1. Small: 局部输入、选区、布局或 inspector 文案修正。运行最小自测。
2. Medium: focused editor 主线、language feedback、source fidelity、workspace document store、command route 或 editor state 行为变化。补测试目录映射并跑两条主验证线。
3. High: 显示替换与源码关系、最小可编译单元交互、editor 主工作流或主布局架构变化。走协调 review，并同步设计/ADR/里程碑。

## Required Gates

Minimum:

```bash
cd prototype && npm run governance
cd prototype && npm run selftest:editor
cd frontend/vityo_app && flutter analyze && flutter test
```

## Cross-Team Dependencies

1. Adapter / Contracts 必须 review 任何新 payload 假设、diagnostic/text edit 语义或上游 handoff 依赖。
2. Theme / UX 必须 review 影响层级、排版、容器约束和视觉基线的变更。
3. Runtime / Agent 必须 review 会影响 runtime/debug/agent surface 入口或布局的变更。
4. Docs / Delivery 必须 review handbook、里程碑和测试目录映射的更新。

## Handoff / Recovery

Record:

1. 受影响的编辑主线是 Flutter、handwritten web，还是两者同时。
2. 已跑的自测命令与失败截图或失败场景。
3. 当前是否仍满足 source buffer fidelity。
4. 下一步要改的 surface、回滚点和对应 history 记录。
5. prototype/dev_server.py rejects removed legacy entrypoint assets (`/app.js`, `/styles.css`); the test `test_removed_legacy_entrypoint_assets_are_not_served` validates 404 responses.

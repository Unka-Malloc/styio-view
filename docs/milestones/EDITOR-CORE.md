# Editor Core

**Purpose:** 交付自研编辑器的最小核心，包括文档模型、光标、选择、撤销与基础文本渲染。

**Last updated:** 2026-04-12

**Status:** In Progress

## 1. 目标

1. 不依赖传统 IDE 组件构建可编辑文本核心。
2. 确保后续 visual substitution 与 semantic block surface 有稳定基础。

## 2. 任务

| Workstream | Deliverable | Dependency | Exit |
|------------|-------------|------------|------|
| Document and selection model | 定义 `DocumentState`、`SelectionState`、撤销/重做模型 | Foundation and desktop shell | 可表达单文档编辑状态 |
| Text editing operations | 实现基础文本输入、删除、换行、选择 | Document and selection model | 可完成基础录入 |
| Multiline layout and scrolling | 实现多行布局与滚动模型 | Document and selection model | 文本可正确滚动 |
| Desktop editor commands | 实现桌面快捷键：保存、运行、导航基础骨架 | Command routing | 快捷键可被分发 |
| Cursor and selection movement | 实现鼠标/键盘光标移动和选择扩展 | Text editing operations | 光标语义稳定 |
| Editor render layers | 定义编辑器渲染层：文本层、装饰层、overlay 层 | Multiline layout and scrolling | 后续装饰可插入 |
| Source buffer fidelity tests | 建立 source buffer fidelity 测试基线 | Text editing operations | 文本操作不破坏源码 |
| Shared editor core boundary | 明确共享核心框架与分端渲染/交互调优分层 | Foundation and desktop shell | 桌面与移动共享核心模型 |

## 3. 门禁

1. 单文档输入、删除、撤销/重做可用。
2. 光标、选择和滚动稳定。
3. 代码仍然是纯文本存储，未引入任何源码级图形替换。
4. 桌面与移动端共享同一套核心文档模型。

## 4. Current implementation anchor

当前代码入口：

1. `frontend/vityo_app/lib/src/editor/document_state.dart`
2. `frontend/vityo_app/lib/src/editor/selection_state.dart`
3. `frontend/vityo_app/lib/src/editor/editor_render_layers.dart`
4. `frontend/vityo_app/lib/src/editor/editor_controller.dart`
5. `frontend/vityo_app/lib/src/editor/editor_surface.dart`

当前已落地：

1. `DocumentState`、`SelectionState` 与基础撤销/重做快照栈
2. `EditorRenderPlan` 三层骨架：`text / decoration / overlay`
3. 共享 `EditorSessionController`
4. 工作区文件切换时的文档 seed 装载
5. 主壳内可见的 source buffer 分层预览
6. 预览层已按 token range 逐行渲染，并能承载 inline widget span
7. 桌面键盘输入、`Backspace/Delete/Enter/Tab`、方向键与 `Home/End` 已接入
8. 文件切换时的文档内存缓存已接入，当前会话内不会因切文件丢失编辑结果
9. `Shift + 方向键/Home/End` 的基础选择扩展已接入，并有选区高亮
10. `Save` 已接入跨端 `WorkspaceDocumentStore`，当前为 `native file system > web shared_preferences`
11. 鼠标拖拽选区已接入，并已由 widget smoke test 覆盖
12. 编辑器面板已跟随统一视窗族自适应密度收缩，避免桌面/移动共用壳时的窄高视口溢出
13. 编辑器内部 `source preview + language inspector` 已改为跟随 `ViewportProfile`，不再按纯宽度自行切换桌面/移动语义

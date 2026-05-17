# UX Maintenance Guidelines

**Purpose:** 把外部 UX / accessibility / performance 基准转成 `Vityo` 的长期开发和维护准则。

**Scope:** 覆盖 Flutter 主壳 `frontend/vityo_app/`、手写 Web IDE 原型 `prototype/editor.html` 线，以及两者之间需要保持一致的产品行为。

**Last updated:** 2026-04-16

## 1. 外部基准

本项目的 UX 判断至少参考以下公开基准：

1. Nielsen Norman Group: [Jakob's Ten Usability Heuristics](https://www.nngroup.com/articles/ten-usability-heuristics/)。
2. W3C: [WCAG 2.2](https://www.w3.org/TR/WCAG22/) 与 [Target Size Minimum](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html)。
3. web.dev: [Core Web Vitals thresholds](https://web.dev/articles/defining-core-web-vitals-thresholds)。
4. Flutter: [Accessibility](https://docs.flutter.dev/ui/accessibility)、[Web accessibility](https://docs.flutter.dev/ui/accessibility/web-accessibility)、[Performance best practices](https://docs.flutter.dev/perf/best-practices)。
5. Vercel Labs: [Web Interface Guidelines](https://raw.githubusercontent.com/vercel-labs/web-interface-guidelines/main/command.md)。

这些资料不是视觉风格模板，而是验收基线。若本项目的视觉表达与通用建议冲突，优先保留 `Vityo` 的 IDE 产品定位，但不能牺牲可理解性、可访问性、错误恢复和响应性能。

## 2. 产品 UX 立场

`Vityo` 是编辑器和运行视窗，不是营销页。用户体验的核心不是装饰感，而是让用户稳定完成高频工作：

1. 打开工作区。
2. 理解当前文件、路由、平台能力和运行状态。
3. 编辑源码并看到可信的语义反馈。
4. 保存、运行、查看 diagnostics，并从错误中恢复。
5. 在桌面、移动和 Web 窄屏之间保持同一套心智模型。
6. 在 agent patch、runtime result、debug console、module update 等复杂状态之间不迷失。

后续所有前端改动都应先回答三个问题：

1. 这个改动是否降低了用户完成主任务的认知负担？
2. 这个改动是否让状态、后果和错误恢复路径更清楚？
3. 这个改动是否保持键盘、触控、屏幕阅读器和低性能设备的可用性？

## 3. 维护原则

### 3.1 状态必须可见

所有异步、危险、持久化或跨系统动作都必须有明确状态反馈：

1. 保存：`clean / dirty / saving / saved / failed` 必须能被看见。
2. 运行：`queued / running / blocked / failed / succeeded` 必须区分。
3. diagnostics：错误位置、严重性、quick fix 是否可用必须就近呈现。
4. agent patch：预览、应用、撤销、失败原因必须独立于普通编辑状态。
5. staged update：当前会话未生效和下次重启生效必须清楚分开。

不要只靠颜色表达状态；需要文字、图标、位置或语义标签共同表达。

### 3.2 用户必须能退出和恢复

高风险动作不能立即吞掉用户状态：

1. 删除文件、关闭云工作区、应用 patch、切换会影响保存目标的 workspace，都需要确认或可撤销窗口。
2. 有未保存内容时，导航、关闭、切换文件或切换 workspace 必须提示。
3. 错误信息必须包含下一步，而不是只暴露内部错误码。
4. agent 和 runtime 失败不能覆盖用户正在编辑的源码。

### 3.3 识别优先于记忆

编辑器产品可以支持快捷键，但不能要求用户记住隐形流程：

1. 主要动作需要可见入口。
2. 快捷键应作为增强，而不是唯一入口。
3. 图标按钮必须有 tooltip / `aria-label` / Flutter semantics label。
4. 文件树、tabs、runtime page、settings section 的命名要稳定，避免同一概念在不同界面使用不同词。
5. 配置项需要按用户目标分组，不按内部实现分组。

### 3.4 一致性优先

Flutter 主壳和手写 Web IDE 可以实现不同，但用户可见行为要统一：

1. 同一动作使用同一文案、图标含义和状态顺序。
2. 桌面和移动可以布局不同，但导航层级、状态含义和恢复路径不能变。
3. `Theme / Editor / Block / Line / Selection / Symbol Colors` 这些 surface 名称应保持稳定。
4. 任何新 surface 必须声明所属状态、刷新范围、持久化位置和回退状态。

### 3.5 可访问性是默认验收项

默认按 WCAG 2.2 AA 思路设计和复查：

1. 所有交互控件都必须可键盘访问，并有可见 focus。
2. 触控目标在 Flutter 里按至少 `48x48` 设计；Web 里不低于 WCAG 2.2 的 `24x24 CSS px` 底线，并优先做得更大。
3. 文本和控件对比度目标为至少 `4.5:1`，disabled 状态除外。
4. 自定义绘制、canvas、editor layer 和图标按钮必须补 semantics / ARIA。
5. 屏幕阅读器应能描述控件名称、角色、当前状态和主要结果。
6. 大字号、系统缩放、色盲模式、灰度模式下不能丢失关键信息。

### 3.6 性能属于 UX

编辑器体验的性能标准高于普通内容页：

1. 输入、光标移动、选区、hover feedback 不应触发全局重绘。
2. Flutter 大列表、文件树、diagnostics 列表和 runtime logs 必须使用 lazy builder 或等效增量策略。
3. Flutter `build()` 中避免重复昂贵计算；状态更新要局部化。
4. 谨慎使用 `saveLayer()`、大面积 `Opacity`、不必要 clipping 和 intrinsic layout。
5. Web 原型避免 `transition: all`、render 内 layout reads、DOM 读写交错和超过 50 项的大数组直接整量渲染。
6. Web 验收参考 Core Web Vitals：LCP `<= 2.5s`、INP `<= 200ms`、CLS `<= 0.1`，按第 75 百分位看。

### 3.7 布局必须抗坏输入

这个项目有大量路径、源码、日志、diagnostics、配置 JSONC 和平台能力文本。所有容器都必须承受长内容：

1. flex/grid 子项默认考虑 `min-width: 0`。
2. 长路径、长 token、长错误文本需要截断、换行、内部滚动或可展开详情。
3. 子元素不得溢出父容器；空间不足时重排或降低密度。
4. 移动端要考虑 safe area、软键盘、抽屉遮挡和横竖屏变化。
5. 文本不能和按钮、图标、焦点环、浮层或下一段内容重叠。

## 4. Flutter 主壳规则

1. 优先使用具备原生 semantics 的标准 widget；自定义绘制或手势层必须显式补 `Semantics`。
2. 图标按钮、editor action、runtime action 必须提供可读 label 和 tooltip。
3. 使用 `Shortcuts` / `Actions` / focus 管理来表达键盘路径，不把快捷键散落在具体控件里。
4. 大块 UI 按状态变化范围拆分 widget，避免一个大 `build()` 承担编辑器、侧栏和 runtime 全部刷新。
5. 高频编辑路径只刷新 caret、selection、active line、inline feedback 等必要层。
6. 任何会触发平台差异的交互，要在 `ViewportProfile` 或等效适配层中表达，不在单个 view 里硬编码。
7. Flutter Web 若作为用户可访问入口，必须显式处理 Semantics tree 的可用性，而不是假设 canvas 渲染天然可访问。

## 5. 手写 Web IDE 规则

1. Icon-only button 必须有 `aria-label`，装饰图标必须 `aria-hidden="true"`。
2. 抽屉、tabs、菜单、picker 要维护 `aria-expanded`、`aria-controls`、active state 和键盘操作。
3. 所有交互元素必须使用合适元素：动作用 `button`，导航用 `a`。
4. focus 样式必须通过 `:focus-visible` 或等效类明确呈现，不允许裸 `outline: none`。
5. async toast、保存结果、validation 和 runtime 状态变化需要可被辅助技术感知。
6. animation 要尊重 `prefers-reduced-motion`，只动画 `transform` / `opacity` 等低成本属性。
7. 主题切换、配置导入、settings 改动必须走既有 surface action 和 render slice，不绕过统一调度器。

## 6. PR / 变更验收清单

每次涉及 UI、交互、状态或布局的变更，至少检查：

1. 主任务路径是否更短或更清楚。
2. loading / empty / error / disabled / success / dirty 状态是否齐全。
3. 键盘、触控、屏幕阅读器路径是否可用。
4. 窄屏、宽屏、长文本、大字号、低性能设备是否不会破版。
5. 危险动作是否有确认、撤销或明确恢复路径。
6. 高频交互是否局部刷新，并有测试或手动验证。
7. Flutter 主壳和 Web 原型是否没有引入同一概念的不同命名。

## 7. UX 质量指标

后续可逐步把以下指标纳入测试或人工验收：

1. First edit time: 从打开页面到能输入第一字符的时间。
2. Save confidence: 用户能否明确知道当前文件是否已保存。
3. Error recovery time: 从 compile blocked 到定位并应用 quick fix 的时间。
4. Input latency: 编辑、光标、选区在常规项目规模下无明显卡顿。
5. Layout robustness: 多 viewport、多字号、长路径、长日志下无内容溢出。
6. Accessibility coverage: 主要动作有 label、role、focus、keyboard path 和状态播报。

这些指标不要求一次全部自动化，但任何新功能都不应让它们明显倒退。

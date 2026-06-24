# Prototype Changelog

## 2026-04-12 / Round 1

1. 新建首个可直接打开的高保真原型页。
2. 加入顶部 workspace 壳、桌面/移动模式切换和主题切换。
3. 加入 visual substitution 开关与 semantic block surface 展示。
4. 加入模块挂载 strip 与 runtime surface registry 侧栏。
5. 加入底部 runtime surface，包含 thread lanes 与 directed graph。
6. 加入 AI surface，展示 prompt profile 和 workspace context 注入方向。
7. 加入 hosted workspace 关闭弹窗，体现 7 天保留与核心文件导出入口。

## 2026-04-12 / Round 2

1. 编辑器区补上 diagnostics rail、选中态和底部 source fidelity / diagnostics 元信息。
2. runtime surface 补上 event console，不再只有线程轨和 directed graph。
3. 侧栏加入 staged update 队列和 profile sync / local-only 状态表达。
4. 增加 mobile interaction preview，展示纵向卡片流和长按 pipeline selector 方向。
5. 增强交互：运行按钮会刷新 event console，模块卸载会影响 registry，可视化模块移除后会退化到 console-only 提示。

## 2026-04-12 / Round 3

1. 主界面从双栏改成三栏，新增左侧 workspace explorer 与 symbol 列表。
2. runtime surface 改成 tabbed workspace，支持 Graph / Console / Debug 三个视图切换。
3. AI surface 新增 patch preview 区，开始表达“建议队列”和“未写回 source buffer”的状态。
4. 文件树点击会切换当前文件 chip、selection 状态和 diagnostics 文案。
5. 页面更接近真实 IDE 骨架，而不是概念板块拼贴。

## 2026-04-12 / Round 4

1. 编辑器区新增 open file tabs，让文件树与顶部标签都能切换当前文件上下文。
2. 顶部新增 staged update restart banner，开始表达“旧模块继续运行，重启后挂载新模块”的真实产品语义。
3. 新增 Distribution + Module Library 区，直接展示模块安装、卸载、阻止挂载和按平台能力分发。
4. 新增 platform capability matrix，加入 macOS / Android / iOS / Web 四套规则，iOS 与 Web 会自动隐藏 local compile。
5. 模块 strip、右侧 registry、runtime debug、provider state 现在全部跟随当前平台和模块状态联动。
6. graph runtime 被卸载后，Graph 视图会退化成明确的 fallback 提示，不再假装还能展示状态图。

## 2026-04-12 / Round 5

1. 编辑器主区从静态代码示意改成了可输入的 `raw source buffer + render projection` 双面板。
2. 左侧 source buffer 现在能真实输入源码，右侧 render projection 会根据当前源码重新生成行号、符号替换和块级表面。
3. `->` 和 `|>` 的渲染从文字标签改成真实符号 glyph，projection 里会显示箭头和三角管线符号。
4. 函数块会根据源码中的 `fn ... { ... }` 边界自动包成灰底圆角 semantic block surface。
5. diagnostics rail、footer meta、symbol cards 现在不再是死数据，而是跟随当前源码内容实时更新。
6. `Ctrl+Enter` 现在会先检查当前最小可编译单元是否闭合；源码不完整时会直接在 runtime console 里显示 compile blocked。

## 2026-04-12 / Round 6

1. 原型服务从纯静态 `http.server` 升级成了带本地 API 的开发服务，端口保持 `127.0.0.1:4173`。
2. 新增 `prototype/workspace/*.styio` 作为真实工作区文件，页面启动时会从磁盘加载这些源码。
3. 编辑器新增显式 `Save` 按钮和 `disk: dirty / saving / saved / failed` 保存状态提示。
4. `Command+S` 和 `Ctrl+S` 现在都会拦截浏览器默认行为，并把当前文件写回本地工作区目录。
5. 页面关闭前如果还有未保存文件，会触发浏览器级未保存提醒，避免误关窗口丢编辑状态。

## 2026-04-12 / Round 7

1. 新增独立的 focused editor 页面：`editor.html`。
2. 新页面只保留一个编辑面，不再做 `raw source buffer + render projection` 双栏对照。
3. 文本输入、glyph 替换和函数块背景都发生在同一块编辑区域里，改成更接近真实编辑器的 overlay 结构。
4. `->` 和 `|>` 会在编辑区内直接渲染成 inline glyph，不再单独放到另一块预览面板。
5. 函数块背景改成 block layer 绝对定位覆盖，和文本共处同一个编辑视口。
6. focused editor 继续复用本地 workspace API，所以 `Save`、`Command+S` 和真实落盘仍然可用。

## 2026-04-12 / Round 8

1. 修复 focused editor 中行号层与 render 层的严重错位问题。
2. 根因是 render/block overlay 容器错误地保留了模板空白和 `white-space: pre`，导致产生不可见空白行。
3. 现在 render 容器改回正常流，真正的 `pre` 只留给 `textarea` 和逐行文本节点本身。
4. render 行节点和 block 高亮节点的 HTML 输出也改成单行字符串，不再插入模板缩进空白。
5. gutter、textarea、render line 三层现在统一使用同一组像素级字体、行高和 padding 变量。

## 2026-04-12 / Round 9

1. focused editor 的 glyph 编辑语义改成“视觉压缩，但源码仍按两字符编辑”。
2. 新增自定义 caret layer，textarea 只负责接收输入，不再直接显示原生光标。
3. 点击编辑区时，会按照渲染后的视觉宽度反算回原始源码 offset，再设置真实光标位置。
4. 当 caret 进入 `|>` / `->` 的内部边界时，当前 token 会自动解除组合显示原始字符；从 token 尾部按 `Backspace` 时会自然删掉最后一个字符。
5. glyph 自身继续保持极简 inline 渲染，但不再影响对原始两字符源码的删除和回退行为。

## 2026-04-12 / Round 10

1. focused editor 页面改成“主区只保留编辑卡片，设置与目录树迁入右侧抽屉”。
2. 编辑卡片右上角新增侧边栏呼出按钮，打开后主区会自动压缩，不再覆盖主页面。
3. 侧边栏顶部改成 Tab 结构：`目录树` 和 `设置`。
4. 原先主页面上的文件切换、glyph 开关、保存按钮、状态信息都迁进了右侧抽屉。
5. 主页当前只留下编辑器本体和一个最小标题区，视觉重心完全回到编辑面本身。

## 2026-05-18 / Route Cleanup

1. 默认入口统一为 `/editor`。
2. `/editor` 只绑定 focused editor 页面，不再展示原型画廊或引导页。
3. 旧引导页从静态入口、manifest 和治理分类中移除。
4. 删除旧引导页依赖的 `app.js` / `styles.css`，避免 `/editor` 之外残留可访问入口。

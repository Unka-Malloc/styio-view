# Prototype Surface

**Purpose:** Describe the handwritten `Vityo` prototype surfaces, their local server, and the repo-local governance checks that keep them owned and testable.

**Last updated:** 2026-05-02

当前目录是 `Vityo` 的高保真原型与本地开发壳，不依赖 Flutter 工具链。

这里同时也是当前仓库里“给人维护的 Web Editor 入口”。
`frontend/vityo_app/build/web` 之类的 Flutter 生成物只用于构建验证，不作为人工维护页面。

仓库级 bootstrap、共享工具链和常用验证命令见 [../docs/BUILD-AND-DEV-ENV.md](../docs/BUILD-AND-DEV-ENV.md)；本页只描述手写原型本身。

当前标准原型工具链固定为 `Node.js v24.15.0 LTS` 与 `Chromium 147.0.7727.116`。

## Files

1. `index.html`: 页面结构
2. `styles.css`: 视觉系统与布局
3. `app.js`: 编辑器、模块、runtime 与保存交互
4. `dev_server.py`: 本地开发服务，提供静态资源和受保护的工作区 API
5. `workspace/*.styio`: 原型编辑器真实加载和保存的本地文件
6. `CHANGELOG.md`: 每轮页面可见变化记录
7. `editor.html` / `editor.css` / `editor.js`: 当前人工维护的 focused Web Editor 页面
8. `editor-modules/*.js`: focused editor 的配置、枚举、主题模板、渲染调度与默认状态模块
9. `GRID-STYLE-REFERENCE.md`: `Grid` 风格的布局结构、共享变量、几何约束与自测规则
10. `GRID-STYLE-PRACTICE.md`: `Grid` 风格在重构、调样和验证过程中沉淀下来的工程经验与维护方法
11. `PROTOTYPE-GOVERNANCE.md`: top-level HTML 原型的治理规则、分类和 gate
12. `prototype-manifest.json`: top-level HTML 原型清单，声明 canonical / gallery / style experiment 边界
13. `scripts/check-prototype-governance.mjs`: manifest 与治理文档的可执行校验

## Current Focus

1. 顶部壳与 workspace 状态
2. 编辑器区的 visual substitution 与 semantic block surface
3. 模块/特性注册表
4. runtime surface
5. AI surface
6. mobile 交互预览
7. workspace explorer 与 tabbed runtime workspace
8. module library 与 platform capability matrix
9. staged update restart banner
10. raw source buffer 与 render projection 双面板编辑器
11. disk-backed workspace save flow
12. focused inline editor page
13. focused editor drawer layout

## Interaction Notes

1. 点击 `Substitution` 可切换显示替换
2. 点击 `Desktop / Mobile` 可切换布局方向
3. 点击模块 pill 可模拟安装/卸载
4. 点击 `Ctrl+Enter` 可触发 runtime 状态变化
5. 点击 `Close Cloud Workspace` 可查看 hosted workspace 关闭提示
6. 点击 `Staged: 1` 可模拟 staged update 在本会话保留、下次重启生效的语义
7. 点击左侧文件树可切换当前文件上下文
8. 点击 `Graph / Console / Debug` 可切 runtime 工作区页签
9. 点击 `Preview Patch` / `Apply Preview` 可演示 AI patch suggestion 流程
10. 点击顶部 open tabs 可切换打开中的源码上下文
11. 点击 `macOS / Android / iOS / Web` 平台卡可切换当前 capability profile
12. 点击 `Module Library` 中的 `Install / Unmount` 可演示按平台挂载和卸载模块
13. 点击 `Staged: 1` 后会出现 restart banner，表达热更新在下次重启时切换新模块
14. 在左侧 `Raw Source Buffer` 里直接输入源码，右侧 `Render Projection` 会实时重绘符号和函数块表面
15. 当前 `Ctrl+Enter` 会先检查最小可编译单元；未闭合的函数块会直接给出 compile blocked
16. 启动服务时显式设置 `STYIO_DEV_SERVER_ENABLE_MUTATION=1` 后，点击 `Save` 或按 `Command/Ctrl+S` 会把当前文件写回 `prototype/workspace/<file>.styio`
17. 访问 `http://127.0.0.1:4173/editor.html` 可以打开只保留单一编辑面的 focused editor 界面
18. focused editor 右上角按钮会呼出右侧抽屉，里面分成 `目录树` 和 `设置` 两个 Tab
19. focused editor 当前固定只维护 `main.styio`，不再混入其它非主线示例文件
20. 当前默认视觉基线为 `Graphite` 壳层，并以 `#F4C76A` 作为默认强调色和 symbol 高亮色
21. 当前原型支持导入 / 编辑一份参考 VS Code 结构的 JSONC 调色盘配置，示例见 `theme-config.example.jsonc`
22. 当前 canonical 配置存放在浏览器 `localStorage` 的 `Vityo:custom-palette-config`
23. 手写 Web IDE 的设计理念、分层规则和标准工作流，见 `../docs/specs/HANDWRITTEN-WEB-IDE-ENGINEERING-HANDBOOK.md`

## Module Structure

1. `editor.js`: 事件、状态流、渲染与工作区交互主入口
2. `editor-modules/runtime-config.js`: 运行时默认配置、存储 key、初始状态模板
3. `editor-modules/enums.js`: 语言、自动保存、主题模式、抽屉页签等枚举
4. `editor-modules/theme-presets.js`: Theme / Editor 相关字体、字号、背景、文字和 palette 模板
5. `editor-modules/glyph-presets.js`: glyph、symbol color、block / line / selection 与 palette 模板
6. `editor-modules/render-pipeline.js`: 渲染切片枚举与分模块批量调度器，避免编辑器、侧边栏和设置区互相直接整刷
7. `editor-modules/surface-actions.js`: `Theme / Editor` 风格行为的层级定义，区分 `surface / section / leaf`
8. `editor-modules/grid-style/layout-config-store.js`: `Grid` 风格的单例布局配置源，负责配置持有、订阅更新与页面自动同步
9. `editor-modules/grid-style/layout-manager.js`: `Grid` 风格的纯布局推导器，负责把配置换算成 CSS 变量
10. `scripts/check-editor-load.mjs`: focused editor 页面加载自测，覆盖页面启动、侧边栏展开、设置区渲染、Theme 切换、`Symbol Highlight` 展开与 `Grid` 运行时布局配置更新
11. `GRID-STYLE-PRACTICE.md`: `Grid` 风格这一轮重构和调样的经验文档，和规则文档配套维护

`editor.js` 中和 `Theme / Editor` 相关的模式切换、palette 切换，应优先通过 surface controller 入口处理，再由渲染切片调度对应区域刷新；不要在事件处理器里直接串行调用多个 UI 同步函数。

`Theme / Editor` 的风格控件现在按三层动作建模：
1. `surface`: 例如 `Theme/Editor` 的 `Dark / Light` 和 `Palette`，会统一下发到整块 surface
2. `section`: 例如 `Font / Color`，只刷新该 section 对应的 appearance slice
3. `leaf`: 例如 `Block / Line / Selection / Symbol Colors`，只刷新对应叶子样式，不再误走整块 editor 流程

动作定义集中在 `editor-modules/surface-actions.js`，按钮层只负责传 action，不负责拼接渲染管线。

## Self-Test

1. 在 `prototype/` 下运行 `npm run governance`，确认 top-level HTML 原型都被 `prototype-manifest.json` 声明并归属到 owner。
2. 运行 `npm run selftest:editor`，检查当前 canonical focused editor。
3. 若使用仓库内的 `dev_server.py`，请显式设置 `STYIO_EDITOR_URL=http://127.0.0.1:4180/editor.html`
4. 这条脚本会自动检查 `editor.html` 是否可打开，并在需要时自动启动 `dev_server.py`
5. 自测会覆盖：
   - 页面基础资源加载
   - 侧边栏展开
   - 设置页切换
   - `Theme` 的 `Palette` 和 `Light / Dark`
   - `Symbol Highlight` 展开
6. 若失败，会在 `prototype/.artifacts/editor-load-failure.png` 写出失败截图

## Local Dev Server Security

1. `dev_server.py` 只绑定 `127.0.0.1:4180`，并拒绝非 `localhost` / `127.0.0.1` / `::1` 的 `Host`。
2. 静态页面响应会设置 `HttpOnly; SameSite=Strict` 的本进程 session cookie；所有 `/api/` 路由都必须携带这个 cookie，或携带 `X-Styio-Dev-Server-Token` / `Authorization: Bearer` 中的当前 session token。
3. 所有 `POST /api/` 写入路由还必须带同源 `Origin`，并且只有设置 `STYIO_DEV_SERVER_ENABLE_MUTATION=1` 后才会执行本地文件写入。
4. 若需要固定 token 供本地自动化调用，可在启动服务前设置 `STYIO_DEV_SERVER_TOKEN=<token>`。
5. 边界回归验证：在仓库根目录运行 `python3 -m unittest prototype/test_dev_server_security.py`。

## Maintenance Rule

1. 后续需要人工调整网页版 IDE 时，优先修改 `editor.html` / `editor.css` / `editor.js`
2. `build/web/*` 不接受人工维护；它只是 Flutter 构建产物
3. 若 Flutter Web 行为需要回归到手写页，先在这里验证交互，再考虑是否同步回 Flutter 主壳
4. 任何内部组件都不得超过外部容器；若空间不足，优先收紧盒模型、加 `min-width: 0`、改成内部滚动或重排，而不是允许内容溢出父容器
5. 默认界面字体、编辑器字体、数学 glyph 字体和用户可见主题预设名必须优先采用开源、低争议来源；不得把商业专有字体作为默认值，也不得把第三方商业产品名直接当作默认主题标签
6. 新增、删除或重命名 top-level `*.html` 原型时，必须同步更新 `prototype-manifest.json` 并运行 `npm run governance`
7. 只有 `prototype-manifest.json` 中的 `canonical` entry 可以定义当前产品行为；`style-experiment` 页面只提供视觉参考，不能引入 workspace mutation、adapter contract 或 dev-server API 语义

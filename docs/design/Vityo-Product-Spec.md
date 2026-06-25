# Vityo Product Spec

**Purpose:** 作为 `Vityo` 的产品级单一事实来源，定义产品定位、术语、不变量、功能域、平台策略与验收边界。

**Last updated:** 2026-06-25

**Status:** Draft SSOT

## 1. 产品定位

`Vityo` 是 Styio 的专属原生 IDE 与运行视窗，不以复用传统 IDE 控件或传统编辑器壳为前提，而是以 Styio 语言特性和现代交互系统为中心，重写：

1. 编辑器文本显示与交互
2. 编译与运行反馈面板
3. 运行逻辑与状态图视图
4. AI 协作编程入口
5. 桌面与移动端各自原生的交互模型
6. 按设备挂载、卸载与更新的模块系统

## 2. 主要用户

1. Styio 语言设计者与核心贡献者
2. 使用 Styio 编写流式、状态化和资源拓扑程序的开发者
3. 希望在桌面或支持本地运行的设备上直接运行 Styio 程序，并在其它设备上接入云执行的用户
4. 需要用 AI 辅助编写、解释和改写 Styio 程序的用户

## 3. 非目标

1. 不把 `Vityo` 做成 VS Code 皮肤或传统 IDE 主题包。
2. 不以兼容任意第三方插件生态作为首发目标。
3. 不在产品级语义上承诺 iOS 支持任意 unrestricted 本地 JIT。
4. 不要求桌面与移动端拥有完全一致的操作方式。

## 4. 术语表

| 术语 | 定义 |
|------|------|
| Source Buffer | 用户真实编辑和保存的 Styio 源文本。 |
| Visual Substitution | 仅在显示层把某些 token 渲染成图标或特殊形态，不改变 Source Buffer。 |
| Semantic Block Surface | 由 parser / typecheck 结果驱动的块级视觉容器，例如函数体灰底圆角块。 |
| Minimal Compilable Unit | 当前光标或编辑上下文中可独立触发编译或运行的最小合法单元。 |
| Runtime Surface | 展示程序执行状态、图模型、线程轨和日志的底部区域。 |
| Runtime Surface Feature Entry | 一条可视化能力声明，说明某个模块能把哪些运行事件映射成何种视图。 |
| Runtime Event Protocol | 执行层发给 UI 的有序事件契约，用于驱动线程轨、状态图、日志与退化提示。 |
| Token Span | 词法层返回给编辑器的基础 token 范围，用于快速基础高亮。 |
| Semantic Span | 语义层返回给编辑器的范围结果，用于类型、函数、pipeline、state 等语义高亮。 |
| Formatting Edit | 格式化层返回的文本补丁结果，采用 `range + newText` 风格，而不是静默重写 Source Buffer。 |
| Pipeline Selector | 对类型检查已通过的 pipeline 候选进行替换或滚动选择的 UI。 |
| Agent Panel | IDE 内建的 AI 交互区，支持 prompt profile、自定义上下文与本地/云端执行。 |
| Agent Provider Adapter | 把本地 agent、云 provider 或外接组件统一成同一调用接口的适配层。 |
| Profile Sync Adapter | 可选挂载的 profile / prompt 同步组件；未挂载时应用仍以本地模式工作。 |
| Local Runtime | 设备本地的 Styio 编译、运行或解释环境。 |
| Cloud Runtime | 云端容器中的 Styio 编译、运行或 agent 能力。 |
| Hosted Workspace | 由云环境托管的工作区实例，Web 端以此作为主运行形态。 |
| Workspace Retention Window | Hosted Workspace 关闭后到最终删除之间的保留时间窗口。 |
| Core Module | 构成应用主壳的不可卸载模块，例如基础窗口、编辑器宿主与设置中心。 |
| Optional Module | 可按设备安装、卸载或禁用的功能模块，例如本地编译、运行视图增强、特定 agent provider。 |
| Mounted Module | 当前客户端已装载并参与运行的模块实例。 |
| Staged Module Update | 已下载但尚未激活的 module package；当前已挂载模块继续运行，客户端重启后再切换到 staged package。 |
| Capability Matrix | 某个模块在不同平台、设备或订阅状态下可否挂载的声明矩阵。 |

## 5. 核心不变量

1. 用户文件的 canonical representation 永远是原始 Styio 源文本。
2. `->`、`|>` 等符号的图形化呈现属于显示层行为，不得静默改写文件。
3. `{ ... }` 灰底圆角块等结构化呈现必须由语言服务或结构分析驱动，不能只靠脆弱的正则推断。
4. 保存、完成最小可编译单元、或显式运行命令可以触发编译；触发规则必须可配置。
5. `Ctrl + Enter` 或平台等效手势表示“运行当前最小合法单元或当前运行目标”。
6. 运行可视化是产品一等能力，不是附属 debug 面板。
7. AI agent 也是产品一等能力，不是外链聊天框。
8. 主题系统必须支持预设主题和细粒度自定义。
9. 桌面、Android、iOS 可以有不同的执行策略和交互模型。
10. 除核心壳能力外，长期功能应优先设计为可挂载模块。
11. 用户可以按设备安装、卸载或禁用可选模块。
12. 模块更新必须采用 staged update 语义：运行中的当前已挂载模块持续到重启前，重启后挂载 staged package。
13. 平台不支持的模块不得暴露入口，例如 iOS 客户端不得暴露本地编译模块入口。
14. 模块能力必须受 capability matrix 约束，而不是由 UI 临时硬编码。
15. 桌面端与移动端共享核心框架、文档模型、语言服务与模块系统。
16. 桌面端与移动端允许在展示层、渲染调优层和交互层做分端优化。
17. visual substitution 必须可由用户显式开关。
18. 运行可视化只允许消费已声明支持的 `Runtime Surface Feature Entry`，不得伪造未声明语义。
19. 运行可视化必须由有序 `Runtime Event Protocol` 驱动，而不是由 UI 从源码静态猜图。
20. AI 与 profile 集成必须通过可替换 adapter 或组件接入，不得把单一 provider 硬编码进主壳。
21. 本地 agent 首发只预留外接组件接口，不把模型 runtime 内建到主壳。
22. 云端 agent provider 至少支持 OpenAI-compatible endpoint adapter。
23. 若未挂载 `ProfileSyncAdapter`，prompt / profile 必须完整工作在 local-only 模式。
24. 登录不是使用 Vityo 的前置条件；用户账户、profile sync 和远端身份能力必须作为可选服务模块挂载。
25. iOS 是唯一受 App Store 审核与分发限制的平台，并作为共享架构的合规下限；iOS 客户端最后上线。
26. Web 端只作为 hosted workspace 客户端；关闭云环境前必须提示清空后果并提供核心文件导出入口。
27. Hosted workspace 默认保留 7 天后删除。
28. 移动端模块卸载默认全量回收；桌面端模块卸载必须给用户保留或清除数据的选择。
29. 基础高亮必须先由 token / semantic 层驱动，`linter` 只负责 diagnostics、fix 和 hint，不负责基础高亮。
30. 格式化结果必须以 `TextEdit` 风格补丁返回，而不是绕过编辑器直接改写 Source Buffer。
31. 任何 UI 容器内的子组件都不得溢出父容器；若空间不足，必须通过重排、内部滚动、局部折叠或尺寸约束处理，而不是允许内容越界。

## 6. 功能域

### 6.1 编辑器引擎

必须支持：

1. 自研文档模型、光标、选择、撤销/重做
2. 视觉替换：例如 `->` 显示为箭头图标，`|>` 显示为右向三角图标
3. 结构装饰：函数体、块级体、资源/状态结构的语义化表面
4. 结构感知输入：基于 token、block、pipeline 的交互反馈
5. 桌面与移动端不同输入系统
6. visual substitution 的用户开关与即时重绘
7. 在 substitution 开启时，复制、搜索、diff、诊断定位仍必须以原始 `Source Buffer` 为准

### 6.2 语言服务

必须支持：

1. 词法 token 范围输出，用于基础高亮
2. 语义范围输出，用于类型、函数、pipeline、state 等语义高亮
3. diagnostics / quick fix 与高亮分离
4. 结构范围、token 范围、块边界暴露给 UI
5. 最小可编译单元识别
6. pipeline 候选筛选与类型安全替换
7. `TextEdit` 风格格式化返回
8. `CompletionItem` 与 `HoverPayload` 一类辅助协议
9. 内部数据合同借鉴 LSP 结构，但实现可完全自研

### 6.3 执行与运行时

必须支持：

1. 保存后自动编译
2. 完成最小可编译单元后可配置自动编译
3. 显式运行快捷键
4. 桌面本地运行为首发主路径
5. iOS 允许以云执行作为主产品方案
6. 执行能力应作为可挂载模块存在，允许用户按设备安装或移除

### 6.4 运行可视化

必须支持：

1. 底部运行视图区
2. 用状态机、简化有向图或线程轨道表达程序运行逻辑
3. 允许仅覆盖明确声明为可视化的代码子集
4. 运行时数据可实时刷新到视图
5. 启动时从已安装模块加载 `Runtime Surface Feature Entry` 列表
6. 新增可视化支持可通过模块 staged update 下发，并在重启后激活

### 6.5 AI 协作层

必须支持：

1. 底部或侧边一等对话区
2. 用户可编辑的预输入 prompt
3. 后续可接云端 profile
4. 移动端内建输入预测 agent
5. 用户可选择本地或云端 agent 路径
6. `Agent Provider Adapter` 抽象，本地/云端 provider 可替换
7. 本地 agent 以外接组件形式挂载，首发不内建模型 runtime
8. 云端 provider 至少支持 OpenAI-compatible endpoint adapter
9. 若未挂载 profile sync 组件，AI 面板仍可在 local-only 模式下工作

### 6.6 主题与个性化

必须支持：

1. 常见 IDE 主题预设
2. token 级颜色定制
3. 语义块表面、面板、运行图区和 AI 面板的独立主题层
4. 后续与用户 profile 同步
5. `ProfileSyncAdapter` 未挂载时仍能完整使用本地 profile
6. 内建默认主题以 `Graphite` 表面基线为主，并以 `#F4C76A` 作为默认强调色与 symbol 高亮色

### 6.7 模块系统与交付

必须支持：

1. 基于 manifest 的模块注册
2. core module 与 optional module 区分
3. 按设备安装、卸载和禁用模块
4. 平台 capability matrix
5. staged module update
6. 重启前后 module package 激活状态切换
7. 平台不支持模块时自动隐藏入口
8. 模块级能力开关可进入用户配置
9. 运行可视化特性也作为模块入口声明的一部分
10. 模块必须声明分发渠道与平台兼容边界
11. 卸载必须按平台 reclaim policy 回收菜单、配置与数据

## 7. 平台策略

| Platform | UI | Compile / Run | Agent | Distribution | Notes |
|----------|----|---------------|-------|--------------|-------|
| Desktop | Flutter 本地 UI | 本地为主，可挂载云执行模块 | 外接本地组件或云端 | 自分发 / 自更新 | 默认挂载本地编译/运行模块；卸载模块时由用户选择保留或清除数据。 |
| Android | Flutter 本地 UI | 本地优先，可卸载本地编译模块 | 外接本地组件或云端 | 自分发 / 自更新 | 用户可移除本地编译模块；当前接受的本地运行模块体积预算目标为 `<= 50 MB`；卸载默认全量回收。 |
| iOS | Flutter 本地 UI | 云执行主路径 | 云端优先，本地仅限非编译类辅助能力 | App Store / 最后上线 | 唯一受商店审核约束；不暴露本地编译模块入口；只挂载 iOS-safe 模块。 |
| Web | Flutter Web | Hosted Workspace 主路径 | 云端 | 托管访问 | 关闭云环境前提示清空并提供核心文件导出；默认保留 7 天后删除。 |

## 8. 首发范围

首发优先覆盖：

1. 桌面版
2. 基础自研编辑器引擎
3. 视觉替换与语义块表面
4. 诊断与编译反馈
5. 桌面本地运行入口
6. 基础运行视图区
7. AI 面板骨架
8. 模块挂载、卸载与 staged update 骨架

## 9. 质量要求

1. 编辑输入必须保持低延迟，视觉替换不能破坏光标语义，也不能破坏源码级复制、搜索与定位语义。
2. 编译反馈必须可理解、可追踪到当前源代码位置。
3. 运行视图允许覆盖不完整，但不能伪造运行语义。
4. 移动端必须是原生本地支持，不是桌面 UI 强行缩放。
5. 模块安装、卸载和更新状态必须对用户可见且可恢复。
6. Android 本地运行模块当前以 `<= 50 MB` 作为可接受体积预算目标。
7. substitution 开与关都必须具备可接受性能，且应有对比基线。
8. 无本地 agent、无云 provider、无 sync 组件时，基础壳仍必须能正常启动和配置。
9. Hosted workspace 的关闭提示、导出入口、保留期限与删除时点必须对用户清晰可见。
10. iOS-safe 与 non-iOS-only 模块必须能由 capability matrix 和发布流程明确区分。
11. diagnostics 失效或延迟时，基础 token 高亮不得消失。
12. 格式化和补全必须通过显式补丁或候选结果进入编辑器，不得绕开文档模型。
13. 侧边栏、弹窗、设置面板和窄视口下的任意子组件都必须保持容器完整性，不能出现内部组件超出外部边界的情况。

## 10. 首批验收问题

1. 用户能否在不离开编辑界面的前提下完成编写、编译、运行、观察和提问？
2. 视觉替换是否提升了 Styio 的读写体验，而不是制造源码与显示的错觉？
3. 运行视图是否真实反映了当前实现支持的语义子集？
4. 新安装或更新的运行可视化特性，是否只在其声明支持的事件和语义范围内生效？
5. AI 面板是否真正接入 IDE 当前上下文，而不是独立聊天窗口？
6. 卸载模块或关闭 hosted workspace 时，用户是否得到清晰、可恢复或可导出的退出路径？

# Vityo Repository Map

**Purpose:** 说明 `Vityo` 与上游 `styio` 主仓库之间的职责边界，以及本仓库当前和未来可能承担的内容；本文件不追踪具体实现进度。

**Last updated:** 2026-04-12

## 1. 总体说明

`Vityo` 不再被规划为纯展示页，而是定位为：

- Styio 的专属编辑器
- Styio 的本地/云运行控制台
- Styio 的运行可视化视窗
- Styio 的 AI 协作编程前端

语言本体、编译器、Parser、Analyzer、IR、LLVM CodeGen 仍以上游 `styio` 主仓库为核心事实来源。

## 2. 仓库职责边界

| Repository | Role | Owns What | Does Not Own |
|------------|------|-----------|--------------|
| `styio` | 语言与编译器主仓库 | 语言语义、词法、文法、AST、类型系统、IR、CLI、JIT、测试基线 | IDE 产品体验、编辑器交互、运行可视化、AI 面板 |
| `Vityo` | 专属 IDE 与运行视窗 | UI、编辑器引擎、交互模型、运行视图、主题系统、AI 面板、Profile 与云工作区集成 | 语言 SSOT、编译器核心语义、LLVM 主实现 |

## 3. `Vityo` 当前拥有的文档边界

1. IDE 产品目标与 UX 约束。
2. Flutter 前端架构与跨端交互模型。
3. `styio` 原生核心接入方式。
4. 本地执行、云执行、移动端运行时的产品策略。
5. 运行可视化、AI 面板、主题系统的产品和架构设计。

## 4. 仍然必须回到上游 `styio` 的问题

1. Styio 语言语义与符号规则。
2. Parser 与类型系统接受哪些程序。
3. 编译器输出的 AST、IR、diagnostic 合同。
4. JIT / IR / CodeGen 的真正运行时语义。

## 5. 潜在未来拆仓

以下内容如果复杂度继续提升，未来可拆到独立仓库，但当前先不拆：

1. `Vityo-cloud`：云工作区与远程执行控制平面
2. `Vityo-profile`：用户 profile、主题市场、Prompt 配置中心
3. `Vityo-mobile-runtime`：移动端本地推理/输入代理与运行封装

在真正拆仓前，这些能力仍视为 `Vityo` 的文档与产品边界。

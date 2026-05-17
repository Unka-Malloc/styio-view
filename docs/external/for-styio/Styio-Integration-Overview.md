# Styio Integration Overview

**Purpose:** 说明 `Vityo` 与上游 `styio` 的总体责任边界，避免把 UI 壳层工作与编译器集成工作混在同一个任务队列里。

**Last updated:** 2026-04-12

## 1. 总体判断

是的，后续真正的编译、分析、运行和 runtime 可视化都会和 `styio` 有大量交互。

但这些交互主要集中在两个窄边界：

1. 语言服务边界
2. 编译运行边界

`Vityo` 不应该直接依赖 `styio` 的内部 C++ ABI，也不应该把 UI 与编译器实现细节绑死。

`Vityo` 拥有产品合同，`styio` 只需要通过 `CLI`、`FFI` 或云端实现去满足这些合同；具体内部做法由 `styio` 自己决定。

## 2. 责任划分

### 2.1 `Vityo` 负责

1. Flutter 主壳
2. 产品合同与 adapter 边界
2. 编辑器文档模型、输入、选择、撤销/重做
3. display-only substitution
4. semantic surface 的 UI 容器和交互逻辑
5. runtime / debug / agent / theme / module host 的壳层
6. compile/run session 的前端状态模型
7. runtime event 的消费与可视化

### 2.2 `styio` 负责

1. 词法 token 结果
2. semantic span、diagnostic、quick fix、formatting edit
3. 最小可编译单元解析
4. compile / run 触发与结果
5. AST / IR / type 信息
6. runtime event 原始流
7. compile-plan consumer
8. `machine-info` 的正式 capability 扩展

## 3. 当前阻塞面

目前 `Vityo` 已经可以先用本地假服务推进 UI，但下面这些能力如果不和 `styio` 对接，就只能停在 mock 阶段：

1. 真实语义高亮
2. 真实 diagnostics 与 quick fix
3. 保存后自动编译
4. `Ctrl + Enter` 运行最小合法单元
5. 底部 runtime surface 的真实事件流

## 4. 对接优先级

### 4.1 Priority A

最先要对接：

1. `TokenSpan / SemanticSpan / Diagnostic / QuickFix / TextEdit`
2. semantic block ranges
3. `machine-info` 扩展

### 4.2 Priority B

随后要对接：

1. `compileUnit`
2. `runUnit`
3. compile / run session 状态
4. stdout / stderr / diagnostic 回流
5. compile-plan consumer

### 4.3 Priority C

再往后：

1. runtime event stream
2. AST / IR / type inspection
3. 更复杂的 graph/state-machine 映射

## 5. 当前建议

当前开发策略应该是：

1. `Vityo` 继续完成独立可做的 UI 与编辑器部分
2. 与 `styio` 的所有正式输入输出边界统一冻结到本目录
3. 先用已发布的 single-file CLI 能力和 `jsonl diagnostics` 走主线
4. 上游一旦发布 `CLI` 或 `FFI` handoff，就只替换 adapter 实现，不重构 UI

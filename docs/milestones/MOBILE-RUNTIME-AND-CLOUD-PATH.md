# Mobile Runtime And Cloud Path

**Purpose:** 建立移动端专属交互与云执行路径，覆盖 Android 本地优先、iOS 云执行主路径、Web hosted workspace 和移动端输入预测 agent 骨架。

**Last updated:** 2026-04-12

**Status:** Planned

## 1. 目标

1. 移动端不照搬桌面交互。
2. Android 具备本地优先路径。
3. iOS 具备云执行主路径。
4. 移动端 pipeline selector 与输入预测 agent 有基础骨架。
5. iOS 不暴露本地编译模块入口。
6. Android 本地运行模块体积控制在当前接受预算 `<= 50 MB`。
7. Web 端具备 hosted workspace 的关闭、导出与保留窗口规则。

## 2. 任务

| Workstream | Deliverable | Dependency | Exit |
|------------|-------------|------------|------|
| Mobile interaction model | 定义移动端交互模型与手势映射 | Editor core | 与桌面清晰分层 |
| Android local runtime module | 设计 Android 本地 runtime 模块接入方案 | Desktop compile and run and module runtime | Android 本地路径冻结 |
| iOS cloud execution workflow | 设计 iOS 云执行工作流与仅云模块矩阵 | Desktop compile and run and module runtime | iOS 云执行主路径冻结 |
| Mobile pipeline selector | 设计移动端 pipeline selector 长按滚动交互 | Pipeline visual substitution | 类型安全候选可滚动选择 |
| Mobile predictive input agent | 建立移动端输入预测 agent 骨架 | AI surface | 本地/云端输入辅助可插入 |
| Connectivity capability notice | 设计离线/在线能力切换提示 | Android local runtime module and iOS cloud execution workflow | 用户知道当前运行路径 |
| iOS compile-entry suppression | 确保 iOS 客户端不暴露本地编译入口 | iOS cloud execution workflow | iOS UI 与模块矩阵一致 |
| Android runtime size gate | 建立 Android 本地运行模块体积预算门禁 | Android local runtime module | 构建产物可检查 `<= 50 MB` |
| Mobile e2e acceptance map | 建立移动端基础 e2e 验收清单 | Mobile runtime and cloud path | 能映射到测试目录 |
| iOS distribution compliance | 冻结 iOS 最后上线与 App Store 合规基线 | iOS cloud execution workflow and module capability matrix | iOS 分发边界清晰 |
| Hosted workspace export flow | 定义 Web hosted workspace 关闭提示与核心文件导出流 | iOS cloud execution workflow | Web 退出路径清晰 |
| Hosted workspace retention flow | 定义 hosted workspace 的 7 天保留与删除流程 | Hosted workspace export flow | 保留窗口可验证 |

## 3. 门禁

1. Android 至少具备一条本地最小执行路径。
2. iOS 至少具备一条云执行最小闭环。
3. 移动端交互与桌面端不混淆。
4. iOS 客户端不存在本地编译模块入口。
5. Android 本地运行模块符合当前 `<= 50 MB` 预算目标。
6. Web hosted workspace 关闭前会提示清空后果并提供核心文件导出。
7. hosted workspace 的默认 7 天保留窗口对用户可见。

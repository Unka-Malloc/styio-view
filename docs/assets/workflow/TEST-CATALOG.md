# Vityo Test Catalog

**Purpose:** 给出 `Vityo` 当前按里程碑组织的测试与验收目录；在实现期作为 `tests/` 与 CI 的映射基线。

**Last updated:** 2026-04-12

## 1. 目录说明

当前仓库尚未建立实际 `tests/` 目录，本文件先冻结测试域、建议命名与自动化缺口，避免后续出现“有里程碑、无验收映射”的情况。

## 2. 测试清单

| Test ID | Scope | Type | Platform | Planned Automation | Status |
|---------|-------|------|----------|--------------------|--------|
| DOC-001 | docs 树存在且索引一致 | docs | all | `gap` | planned |
| MOD-001 | 模块 manifest 与 capability matrix 可正确解析 | unit | all | `gap` | planned |
| MOD-002 | 用户可按设备安装与卸载 optional module | integration | desktop / android | `gap` | planned |
| MOD-003 | staged update 下载后当前已挂载模块保持运行，重启后切换 staged package | integration | all | `gap` | planned |
| MOD-004 | 平台不支持模块时入口自动隐藏 | integration | all | `gap` | planned |
| EDIT-001 | `->` 显示替换不改写源码 | unit / golden | desktop | `gap` | planned |
| EDIT-002 | `|>` 显示替换与光标映射正确 | unit / golden | desktop | `gap` | planned |
| EDIT-003 | `{ ... }` 语义块表面跟随函数边界更新 | integration | desktop | `gap` | planned |
| EDIT-004 | 用户可显式开关 substitution，关闭后恢复原始文本显示 | integration | desktop / mobile | `gap` | planned |
| EDIT-005 | substitution 开启时复制结果仍为原始源码 token | integration | desktop / mobile | `gap` | planned |
| EDIT-006 | substitution 开启时搜索、诊断定位与源码位置一致 | integration | desktop / mobile | `gap` | planned |
| LANG-001 | 保存后自动编译当前文档 | integration | desktop | `gap` | planned |
| LANG-002 | 最小可编译单元识别正确 | integration | desktop | `gap` | planned |
| LANG-003 | token spans 可独立驱动基础高亮，即使 diagnostics 延迟也不丢失基础着色 | integration | desktop / mobile | `gap` | planned |
| LANG-004 | semantic spans 叠加在 token spans 之上，不覆盖 Source Buffer 语义 | integration | desktop / mobile | `gap` | planned |
| LANG-005 | linter 失败或超时不会导致基础高亮消失 | integration | desktop / mobile | `gap` | planned |
| LANG-006 | 格式化结果通过 `TextEdit[]` 补丁进入编辑器，而不是静默重写文档 | integration | desktop / mobile | `gap` | planned |
| RUN-001 | `Ctrl+Enter` 运行当前最小单元 | e2e | desktop | `gap` | planned |
| RUN-002 | 编译失败时诊断能回指到编辑器位置 | integration | desktop | `gap` | planned |
| VIS-001 | runtime event stream 能生成线程轨 | integration | desktop | `gap` | planned |
| VIS-002 | 简化图模型与事件流一致 | golden | desktop | `gap` | planned |
| VIS-003 | 启动时只加载已装模块声明的 runtime surface feature entry | integration | desktop / mobile | `gap` | planned |
| VIS-004 | 卸载可视化模块后入口列表与面板能力同步回收 | integration | desktop / mobile | `gap` | planned |
| VIS-005 | staged update 后重启前保持旧可视化特性，重启后切到新特性 | integration | desktop / mobile | `gap` | planned |
| EVT-001 | `RuntimeEvent.sequence` 在同一 `RunSession` 中单调递增 | integration | desktop / mobile | `gap` | planned |
| EVT-002 | 未识别 `eventKind` 会退化为日志或未支持提示，不导致崩溃 | integration | desktop / mobile | `gap` | planned |
| AI-001 | agent panel 能注入当前文件上下文 | integration | desktop | `gap` | planned |
| AI-002 | prompt profile 可编辑并可持久化 | integration | desktop | `gap` | planned |
| AI-003 | `AgentProviderAdapter` 可接标准 OpenAI-compatible endpoint | integration | desktop / mobile | `gap` | planned |
| AI-004 | 本地 agent bridge 未挂载时，AI 面板仍能进入 local-only 模式 | integration | desktop / mobile | `gap` | planned |
| PROF-001 | `ProfileSyncAdapter` 未挂载时，profile 仍完整保存在本地 | integration | desktop / mobile | `gap` | planned |
| PROF-002 | 挂载 profile sync 组件后，local store 与 cloud mirror 不冲突 | integration | desktop / mobile | `gap` | planned |
| THEME-001 | 主题预设切换不破坏编辑器层级配色 | golden | desktop | `gap` | planned |
| THEME-002 | 用户局部覆写可持久化 | integration | desktop | `gap` | planned |
| PERF-001 | substitution 开启时编辑基线性能达标 | benchmark | desktop | `gap` | planned |
| PERF-002 | substitution 关闭时编辑基线性能达标 | benchmark | desktop | `gap` | planned |
| PERF-003 | substitution 开/关的性能差值在可接受阈值内 | benchmark | desktop / mobile | `gap` | planned |
| MOB-001 | Android 本地最小示例可编译运行 | e2e | android | `gap` | planned |
| MOB-002 | 移动端 pipeline selector 只列出类型安全候选 | integration | android | `gap` | planned |
| MOB-003 | Android 本地运行模块体积不超过 `50 MB` 预算 | build / packaging | android | `gap` | planned |
| IOS-001 | iOS 云执行闭环可用 | e2e | ios | `gap` | planned |
| IOS-002 | iOS 客户端不暴露本地编译模块入口 | integration | ios | `gap` | planned |
| IOS-003 | iOS 在仅云执行场景下给出清晰运行路径提示 | integration | ios | `gap` | planned |
| DIST-001 | iOS 只挂载 iOS-safe 模块并遵循 App Store 分发策略 | integration | ios | `gap` | planned |
| DIST-002 | Desktop / Android 可通过自分发路径获取 non-iOS-only 模块 | integration | desktop / android | `gap` | planned |
| MOD-005 | 手机端卸载 optional module 后模块包、缓存和模块数据被全量回收 | integration | android / ios | `gap` | planned |
| MOD-006 | 桌面端卸载 optional module 时提供保留或清除数据的选择 | integration | desktop | `gap` | planned |
| MOD-007 | 卸载后菜单项、设置入口和失效 workspace 引用被同步回收 | integration | all | `gap` | planned |
| WEB-001 | Web 关闭 hosted workspace 前显示清空提示与核心文件导出入口 | integration | web | `gap` | planned |
| WEB-002 | Hosted workspace 进入 pending-deletion 后默认保留 7 天再删除 | integration / scheduled | web / cloud | `gap` | planned |

## 3. 当前门禁

1. 每新增一个里程碑主功能，至少新增一条对应测试目录条目。
2. 每新增一个平台承诺，至少新增一条该平台的 e2e 或 integration 条目。
3. 在实际测试目录落地前，`Status = planned` 不得被当成“已验证”。

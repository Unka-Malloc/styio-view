# Module Runtime And Staged Hot Update

**Purpose:** 建立模块宿主、capability matrix、按设备安装/卸载和 staged update 机制，使不同平台只挂载可用模块。

**Last updated:** 2026-04-12

**Status:** Planned

## 1. 目标

1. 所有长期功能以 core module 或 optional module 的形式组织。
2. 用户可以按设备安装、卸载或禁用 optional module。
3. 模块更新采用 staged update：当前会话使用已激活模块包，重启后激活已暂存模块包。
4. iOS 客户端不挂载本地编译模块。
5. 平台化卸载回收策略可被宿主执行。

## 2. 任务

| Workstream | Deliverable | Dependency | Exit |
|------------|-------------|------------|------|
| Module manifest | 定义 `ModuleManifest` 与状态字段 | Foundation and desktop shell | manifest schema 冻结 |
| Module capability matrix | 定义 `ModuleCapabilityMatrix` | Module manifest | 各平台可判定可挂载性 |
| Module type classification | 实现 core / optional module 分类 | Module manifest | 基础宿主可区分模块类型 |
| Module user controls | 实现安装、卸载、禁用入口 | Module type classification | 用户可操作 optional module |
| Module lifecycle | 实现 mounted / staged / pending-removal 生命周期 | Module type classification | 生命周期可追踪 |
| Staged activation | 实现 staged update 下载与重启后激活 | Module lifecycle | 当前会话的已激活模块保持稳定 |
| Unsupported-module hiding | 实现平台不支持模块的入口隐藏规则 | Module capability matrix | iOS 不显示本地编译入口 |
| Uninstall state reclamation | 定义模块卸载后的状态回收协议 | Module user controls | 卸载不留下失效入口 |
| Runtime feature slot reclamation | 支持 runtime surface feature module slot 与入口列表回收 | Module manifest and uninstall state reclamation | 可视化入口随模块安装卸载变化 |
| Distribution channel policy | 定义 `DistributionChannelPolicy` 与 iOS-safe 标记 | Module manifest and module capability matrix | 各模块可判定分发边界 |
| Mobile uninstall reclamation | 实现移动端卸载的全量回收协议 | Uninstall state reclamation | 手机端卸载后无残留 |
| Desktop uninstall choice | 实现桌面端卸载的保留/清除数据选择 | Uninstall state reclamation | 桌面端用户可自行决定 |

## 3. 门禁

1. core module 与 optional module 分界清晰。
2. 用户能按设备安装、卸载和更新 optional module。
3. 当前会话中的运行模块在重启前保持稳定。
4. iOS 客户端不暴露本地编译模块入口。
5. 运行可视化入口列表随模块安装、卸载、staged update 正确变化。
6. 移动端与桌面端的卸载回收行为符合各自策略。

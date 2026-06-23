# ADR-0009: Module Runtime Uses Mountable Modules And Staged Updates

**Purpose:** 记录 `Vityo` 如何把功能能力组织为可挂载模块，以及为什么更新采用 staged update 而不是会话内强切。

**Last updated:** 2026-04-12

**Status:** Accepted

**Date:** 2026-04-12

## Context

产品明确要求：

1. 不同设备可以挂载不同能力，例如 iOS 不挂载本地编译模块
2. 用户可以按设备安装、卸载或禁用某些功能模块
3. 模块更新需要只推给装了该模块的客户端
4. 更新下载后，当前已挂载模块应保持稳定，重启后再切到 staged package

## Decision

采用：

1. core module + optional module 的宿主模型
2. manifest + capability matrix 描述模块能力
3. 按设备的安装、卸载、禁用能力
4. staged update：运行中继续使用当前已挂载模块，会话结束并重启后激活 staged package

## Alternatives

1. 单体应用、所有能力永久内建：无法按设备裁剪能力。
2. 会话内直接热替换运行中模块：状态与兼容性风险过高。
3. 每个平台做完全独立产品：共享架构与维护成本过高。

## Consequences

1. 必须定义模块 manifest、生命周期和状态回收协议。
2. 平台 capability matrix 需要进入测试和发布流程。
3. 更新机制必须尊重平台分发、签名和可执行代码边界。

# ADR-0017: Core And Platform Releases Are Versioned Independently

**Purpose:** 记录 Vityo 共享核心与各平台适配层独立版本、独立门禁和独立发布的决定。

**Last updated:** 2026-07-20

**Status:** Accepted

**Date:** 2026-07-20

## Context

Vityo 共享编辑器、语言、执行、运行事件和工作区等核心合同，但 Linux、Windows、macOS、
Android、iOS 与 Web 的 runner、系统 adapter、安装格式、签名/公证、商店政策和更新机制并不
同步成熟。若使用一个全局版本和全平台同时发布门禁，任一平台特有故障都会阻断其他已经可交付
的平台，也无法准确表达某个平台仍停留在旧核心兼容线的事实。

Nightly 与公开稳定版也具有不同的可信度目标：Nightly 需要真实可安装和可启动的验证产物，
但不应在缺少发布凭据时伪造签名或启用不安全的自动更新；公开稳定版则必须完成对应平台的
正式分发证明。

## Decision

### Independent version axes

Vityo 使用三个显式版本轴：

1. `coreVersion`：共享 IDE 核心及其公共合同版本。
2. `adapterVersion`：每个平台适配层独立维护的版本。
3. `packageVersion`：由目标平台安装/分发系统接受的产物版本。

发布清单必须同时记录这三个值以及平台标识。平台原生版本格式如何映射由对应 packaging
实现决定，但不得把核心版本和适配版本折叠成无法恢复的单一值。

### Independent platform release gates

1. 每个平台固定一个声明兼容的 `coreVersion`，并运行自己的构建、适配、安装、签名/公证、
   更新和平台回归门禁。
2. 平台门禁失败只阻断该平台。其他平台无需等待，也无需为了版本对齐而重新发布。
3. 某个平台可以继续维护上一核心兼容线，其他平台可以先升级到新核心。
4. 共享核心候选的通用合同、安全或跨平台不变量门禁失败时，阻断采用该候选版本的平台；
   仍固定旧核心版本且自身门禁通过的平台不被回溯阻断。
5. 产品发布状态用核心与平台组合矩阵表达，不设置一个会把所有平台锁在一起的全局发布布尔值。

### Channel trust levels

1. Nightly 必须提供目标平台可安装、可启动的产物。缺少发布凭据时可以明确标注未签名或未
   公证，但不得声称达到公开稳定版分发标准。
2. 未经签名的 release manifest 不得驱动自动更新。
3. 公开稳定版必须满足目标平台各自的代码签名、公证、完整性、安装/卸载、更新和恢复门禁。
4. 某个平台尚未达到稳定版门槛，不影响其他已达标平台进入稳定通道。

## Consequences

1. CI、release-readiness gate、发布说明和制品清单必须按平台给出结果，不能要求三平台同成同败。
2. 更新源按平台和 channel 分离，并校验 `coreVersion` / `adapterVersion` 兼容关系。
3. UI、诊断包和用户可见版本信息必须能够同时报告核心版本和当前平台适配版本。
4. 核心破坏性变更需要明确的适配兼容范围或迁移，不通过隐式同步升级处理。
5. 相同源码提交可以产生不同平台版本；版本相等也不再被解释为能力完全相等。

## Alternatives

1. 所有平台共享一个版本并同时发布：表面简单，但任何平台特有失败都会造成无关阻塞。
2. 每个平台完全复制核心并独立演进：发布最独立，但会产生领域逻辑分叉和合同漂移。
3. 只使用一个产品版本并把平台差异藏在 build metadata：无法可靠表达兼容线、更新选择和平台回滚。

## Related Records

- `docs/design/Vityo-Product-Spec.md`，第 7.1 节。
- `docs/review/Vityo-Owner-Decision-Queue.md`，VOD-003。
- `docs/adr/ADR-0004-platform-execution-backend-split.md`。
- `docs/adr/ADR-0010-shared-core-cross-platform.md`。
- `docs/adr/ADR-0014-ios-compliance-floor-and-distribution-policy.md`。

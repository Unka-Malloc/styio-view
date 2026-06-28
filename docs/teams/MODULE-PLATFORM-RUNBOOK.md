# Module / Platform Runbook

**Purpose:** 提供 module host、platform capability、六端 runner 与分发路径的日常维护入口。

**Last updated:** 2026-06-28

## Mission

负责 module manifest、capability matrix、平台过滤、六端 runner 和 distribution path。该团队不拥有上游合同本身，也不替 iOS 平台规则做未经文档化的承诺。

## Owned Surface

Primary paths:

1. `frontend/vityo_app/lib/src/module_host/`
2. `frontend/vityo_app/lib/src/platform/`
   - `browser_virtual_file_system_provider.dart` — browser virtual FS provider (Web target)
   - `file_system_operation_result.dart` — structured file system operation result type
   - `file_system_provider.dart` — file system provider abstract contract
   - `memory_file_system_provider.dart` — in-memory FS provider for testing
3. `frontend/vityo_app/assets/module_manifests/`
4. `frontend/vityo_app/lib/src/view_ide/module_host/module_manifest_security.dart`
5. `frontend/vityo_app/assets/capability_matrices/`
6. `frontend/vityo_app/android/`
7. `frontend/vityo_app/ios/`
8. `frontend/vityo_app/linux/`
9. `frontend/vityo_app/macos/`
10. `frontend/vityo_app/windows/`
11. `frontend/vityo_app/web/`
12. `docs/specs/DISTRIBUTION-CHANNEL-POLICY-SCHEMA.md`

Key SSOTs:

1. `系统架构 -> ../design/Vityo-System-Architecture.md`
2. `仓库边界 -> ../specs/REPOSITORY-MAP.md`
3. `活跃缺口登记 -> ../design/Vityo-Implementation-Gaps.md`
4. `卸载与 hosted 保留策略 -> ../adr/ADR-0015-uninstall-reclamation-and-hosted-workspace-retention.md`

## Daily Workflow

1. 变更前先确认属于 module lifecycle、platform gating 还是 runner/config 层。
2. 任何 iOS 执行路径变更都必须先回看平台约束，不得暗示任意本地 JIT。
3. manifest、capability matrix 和对应平台可见性逻辑要一起改，不允许单边漂移。
4. 若 distribution 或 install/unmount 语义变化，同时检查 schema、里程碑和测试目录。
5. `module_lifecycle.dart` 只表达最小 lifecycle plan：mount、leave unmounted、uninstall reclaim 和 blocked core-module uninstall；不要在本轮扩展到真实 staged package update 或远程 module registry。
6. 平台支持、可见性和默认挂载必须来自 manifest/capability rule，不允许用 UI 层临时判断替代 module rule。
7. module manifest security 必须在 activation 前完成 schema、permission、capability 和 trust 检查；未知 privileged capability 默认拒绝，不允许由 UI 层临时放行。

8. Browser and memory file-system provider changes must preserve lexical path/URI behavior across Web, Linux, macOS, and Windows; update Windows path tests when provider normalization, separators, or URI handling changes.

## Change Classes

1. Small: 局部 capability/filter 修正或 runner 配置调整。跑 Flutter 最小验证。
2. Medium: manifest 字段、module lifecycle、平台可见性、uninstall reclaim 标志或分发策略变化。补 schema 和测试目录映射。
3. High: iOS/Android/desktop 执行路线、模块安装卸载语义、staged update 语义或 distribution policy 变化。走协调 review。

## Required Gates

Minimum:

```bash
cd frontend/vityo_app && flutter analyze && flutter test
python3 scripts/check_security_baseline.py
python3 scripts/repo-hygiene-gate.py --mode tracked
```

## Cross-Team Dependencies

1. Adapter / Contracts 必须 review 任何 platform payload、toolchain state 或 project graph handoff 变化。
2. Runtime / Agent 必须 review 会影响 runtime surface 可见性的 capability 变化。
3. Docs / Delivery 必须 review 分发策略、里程碑和测试目录更新。
4. Theme / UX 必须 review 平台切换、module library 或 capability 展示层变更。

## Handoff / Recovery

Record:

1. 变更影响的平台和 module surface。
2. 更新过的 manifest、matrix 和 schema。
3. 已确认的 iOS-safe / non-iOS-only 路径。
4. 下一个平台验证步骤与回滚点。

### 2026-06-25 — Compilation fixes (architecture alignment audit)

- `file_system_provider.dart`, `browser_virtual_file_system_provider.dart`, `memory_file_system_provider.dart`: Added direct import of `file_system_adapter.dart` (`FileSystemCompatibility` not available through transitive import); implemented `supportsScheme()` override required by `implements FileSystemProvider`.
- `file_system_operation_result.dart`: Rewrote sealed-class object patterns to `is`/`as` type checks for Dart SDK compatibility; added explicit `const` constructor for sealed superclass.
- No behavioral changes. All existing API contracts preserved.

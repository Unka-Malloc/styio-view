# Next Stage Gap Ledger

**Purpose:** 压缩记录 `Vityo` 仍与三仓统一文件治理基线存在的活跃缺口，确保治理债务能以 checkpoint 大小推进，而不是继续靠人工兜底。

**Last updated:** 2026-05-02

## Active Gaps and Closure Evidence

## Closed (Minimal / Verified)

1. 代码与适配层最小闭环具备可复测锚点：`frontend/vityo_app` 的 `flutter analyze` + `flutter test` 本地通过；`VITYO_PRODUCT_GATE=1` 相关 product 工作流测试目前默认跳过（非缺陷，属于 gate 策略）。
2. `FG4` 及 docs/test 治理链路在文档/脚本面保持持续可验证状态。
3. 2026-04-22 外部审计的 ignored scratch defect queue 已迁入 tracked 审计报告和本 ledger；`docs/audit/defects/` 继续保持 transient/ignored，不作为提交内容。
4. 下游 `nightly` 的仓库级 CI 面统一到 `local-ci-gate`，与独立的 `styio-audit` policy gate 和 `audit` handoff gate 分离。

## Open (Need Product-Stage Close)

1. `W7/W8/W9/W10` 仍有非完整产品级部分：真实 AI provider 调用、移动端交互与真机/模拟器矩阵、主题编辑面板持久化、真实模块包 staged update + 平台文件回收仍未完成。
2. `active/history/archive` 生命周期与 docs 历史脚本核验尚未完成到完整平台级阶段 gate。
3. `FG4`: 只有当出现 `docs/**` 或 `frontend/vityo_app/test/**` 外的新构建/临时资产追踪需求时，才继续扩展 negate 与 hygiene 规则。
4. Shell run-route gating 仍需在 route snapshot 层阻断不可用路径，避免依赖 adapter 下游失败。
5. Web hosted-control-plane failure parsing 仍需与 hardened IO client 对齐。
6. Runtime route text precision 和 stale async document-load rejection 仍需后续 focused fix。
7. Product workflow coverage 仍由 `VITYO_PRODUCT_GATE=1` 显式触发，不作为默认 CI 成功的产品全矩阵证明。

## Exit Condition

当 `Vityo` 具备以下能力时，这个 ledger 可以转入维护态：

1. `active/history/archive` 生命周期清晰，
2. docs 索引和 lifecycle 可脚本校验，
3. repo hygiene 会显式发现 docs/file governance 漂移，
4. GitHub Ruleset 对 `nightly` 强制要求 PR 合入，以及 `audit`、`styio-audit`、`local-ci-gate` 三个检查。
